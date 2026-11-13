#!/usr/bin/env python3
"""Action-mask check: the Python-side masking convention (issue #423).

Verifies, with zero third-party dependencies, the Python-side Definition
of Done items of issue #423:

1. Cross-language parity: Godot's ``ActionMask.ILLEGAL_LOGIT`` (parsed
   out of ``action_mask.gd``) equals ``rl_action_mask.ILLEGAL_LOGIT`` —
   both consumption paths substitute the same large negative value.
2. Convention: ``mask_logits``/``apply_action_masks`` overwrite exactly
   the illegal slots (flat layout = one contiguous segment per head in
   action-space order, the same walk as ``ActionMask.apply_to_logits``),
   never touch legal slots, never mutate their input, and reject invalid
   masks loudly (missing head / unknown head / wrong size / all-illegal
   head / non-bool element).
3. DoD: with the no-enemies-in-reach wire mask (attack = hold-only,
   target = no-target-only, exactly what TrainingBot.get_action_mask()
   ships when no alive opposing figure stands within ATTACK_REACH), an
   attack-favoring policy NEVER selects an attack action — deterministic
   argmax holds fire and 20000 seeded stochastic draws never fire — while
   the same logits WITHOUT the mask do pick an attack (sanity).
4. Logging: ``format_decision``/``log_decision`` emit the mask arrays
   alongside the chosen actions ("attack=0 mask=100000000 | ...").

Usage: python3 rl_action_mask_check.py   (from the repository root)
"""

import json
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rl_action_mask as am

REPO = os.path.dirname(os.path.abspath(__file__))

# Attack-favoring raw policy output for TrainingBot's action space (issue
# #422: move 6 | aim 3 | attack 9 | target 4 = 22 slots — attack grew to 9
# with the pistol, #526) — the same values tests/test_issue410.gd uses, so
# both languages pin the same fixture: the weapon-fire slots 10-17 carry
# the highest logits, so WITHOUT a mask every path picks an attack action.
ATTACK_FAVORING = [
    0.5, 0.4, 0.3, 0.2, 0.1, 0.0,           # move 0-5
    0.5, 0.3, 0.1,                          # aim 6-8
    0.2, 4.0, 4.1, 4.2, 4.3, 1.0, 0.9, 0.8, 0.7,  # attack 9-17 (fire slots 10-17)
    0.3, 0.25, 0.2, 0.15,                    # target 18-21
]


def parse_godot_illegal_logit():
    src = open(
        os.path.join(REPO, "addons/godot_native_rl/controllers/action_mask.gd"),
        encoding="utf-8",
    ).read()
    m = re.search(r"const ILLEGAL_LOGIT :=\s*(-?[\d.]+e[+-]?\d+)", src)
    if not m:
        sys.exit("FAIL: could not locate 'const ILLEGAL_LOGIT' in action_mask.gd")
    return float(m.group(1))


def parse_trainingbot_heads():
    src = open(os.path.join(REPO, "scripts/TrainingBot.gd"), encoding="utf-8").read()
    m = re.search(r"func get_action_space\(\) -> Dictionary:(.*?)\nfunc ", src, re.S)
    if not m:
        sys.exit("FAIL: could not locate get_action_space() in TrainingBot.gd")
    return [
        (name, int(size))
        for name, size in re.findall(
            r'"(\w+)": \{"size": (\d+), "action_type": "discrete"\}', m.group(1)
        )
    ]


def slice_heads(flat, head_order):
    out = {}
    index = 0
    for name, size in head_order:
        out[name] = list(flat[index : index + size])
        index += size
    return out


def main() -> int:
    failures = []

    def expect(cond, what):
        if not cond:
            failures.append(what)

    # --- 1. cross-language parity of the ILLEGAL_LOGIT convention ---
    godot_const = parse_godot_illegal_logit()
    expect(
        godot_const == am.ILLEGAL_LOGIT == -1.0e9,
        "rl_action_mask.ILLEGAL_LOGIT %r != action_mask.gd ILLEGAL_LOGIT %r"
        % (am.ILLEGAL_LOGIT, godot_const),
    )

    head_order = parse_trainingbot_heads()
    head_sizes = dict(head_order)
    expect(
        list(head_sizes) == ["move", "aim", "attack", "target"] and len(head_sizes) == 4,
        "unexpected TrainingBot heads: %s" % head_order,
    )
    expect(
        sum(head_sizes.values()) == len(ATTACK_FAVORING) == 22,
        "flat width %d != 22 (heads %s)" % (sum(head_sizes.values()), head_order),
    )

    # The no-enemies-in-reach wire mask, JSON-round-tripped exactly as it
    # travels in info["action_mask"] (TrainingBot.get_action_mask() with an
    # empty battlefield: hold/no-target only on attack/target).
    no_enemies = json.loads(
        json.dumps(
            {
                "move": [True] * head_sizes["move"],
                "aim": [True] * head_sizes["aim"],
                "attack": [True] + [False] * (head_sizes["attack"] - 1),
                "target": [True] + [False] * (head_sizes["target"] - 1),
            }
        )
    )
    expect(am.validate_action_mask(no_enemies, head_sizes), "well-formed wire mask validates")
    for bad, what in [
        ({k: v for k, v in list(no_enemies.items())[:3]}, "missing head is invalid"),
        (
            dict(no_enemies, extra=[True]),
            "unknown head key is invalid",
        ),
        (
            dict(no_enemies, attack=[True] + [False] * 6),
            "wrong-size entry is invalid",
        ),
        (
            dict(no_enemies, move=[False] * head_sizes["move"]),
            "all-illegal head is invalid (the neutral index must stay legal)",
        ),
        (
            dict(no_enemies, aim=[1, 0, "x"]),
            "non-bool/0-1 element is invalid",
        ),
    ]:
        expect(not am.validate_action_mask(bad, head_sizes), what)
    expect(not am.validate_action_mask({}, head_sizes),
           "empty mask reads as 'no mask' (parity with Godot's validate)")

    # --- 2. the masking convention itself ---
    per_head = slice_heads(ATTACK_FAVORING, head_order)
    masked_attack = am.mask_logits(per_head["attack"], no_enemies["attack"])
    for i in range(head_sizes["attack"]):
        if i == 0:
            expect(
                masked_attack[i] == per_head["attack"][i],
                "legal slot %d untouched" % i,
            )
        else:
            expect(
                masked_attack[i] == am.ILLEGAL_LOGIT,
                "illegal slot %d overwritten with ILLEGAL_LOGIT (got %r)"
                % (i, masked_attack[i]),
            )
    expect(per_head["attack"][3] == 4.2, "mask_logits never mutates its input")

    flat_masked = am.apply_action_masks(ATTACK_FAVORING, no_enemies, head_order)
    expect(len(flat_masked) == 22, "flat application keeps the 22-slot width")
    # Flat layout (issue #422): move 0-5, aim 6-8, attack 9-17, target
    # 18-21 — the fire slots 10-17 and the no-enemy target slots 19-21 go
    # to ILLEGAL_LOGIT; every other slot stays untouched.
    for i in list(range(10, 18)) + list(range(19, 22)):
        expect(
            flat_masked[i] == am.ILLEGAL_LOGIT,
            "flat illegal slot %d == ILLEGAL_LOGIT (got %r)" % (i, flat_masked[i]),
        )
    for i in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 18]:
        expect(
            flat_masked[i] == ATTACK_FAVORING[i],
            "flat legal slot %d untouched (got %r)" % (i, flat_masked[i]),
        )
    expect(ATTACK_FAVORING[12] == 4.2, "apply_action_masks never mutates its input")

    try:
        am.apply_action_masks(ATTACK_FAVORING, dict(no_enemies, attack=[True] * 7), head_order)
        expect(False, "apply_action_masks must reject a wrong-size mask")
    except ValueError:
        pass
    try:
        am.apply_action_masks(ATTACK_FAVORING[:-1], no_enemies, head_order)
        expect(False, "apply_action_masks must reject a flat-width mismatch")
    except ValueError:
        pass

    # --- 3. DoD: a masked policy never selects an attack action ---
    # Sanity first: the same logits WITHOUT the mask do pick an attack
    # (argmax lands on the strongest fire slot, index 4 within the head).
    expect(
        max(range(head_sizes["attack"]), key=lambda i: per_head["attack"][i]) == 4,
        "sanity: unmasked argmax picks an attack (fire slot 4)",
    )
    expect(am.argmax_masked(per_head["attack"], no_enemies["attack"]) == 0,
           "masked argmax holds fire (attack==0)")
    expect(am.argmax_masked(per_head["target"], no_enemies["target"]) == 0,
           "masked argmax keeps no target (target==0)")

    rng = random.Random(423)
    draws = 20000
    illegal_selected = 0
    seen = {name: set() for name in head_sizes}
    for _ in range(draws):
        action = {
            name: am.sample_masked(per_head[name], no_enemies[name], rng)
            for name in head_sizes
        }
        if action["attack"] != 0 or action["target"] != 0:
            illegal_selected += 1
        for name in head_sizes:
            seen[name].add(action[name])
    expect(illegal_selected == 0,
           "DoD: %d stochastic draws never select an attack action" % draws)
    expect(seen["attack"] == {0}, "attack head only ever draws hold-fire")
    expect(seen["target"] == {0}, "target head only ever draws no-target")
    # The sampler is not degenerate: unconstrained heads still explore.
    expect(len(seen["move"]) > 1 and len(seen["aim"]) > 1,
           "legal heads still sample multiple actions (sampler not collapsed)")

    # Partial legality (one enemy in reach): fire slots become legal and
    # ARE drawn, while the masked-out slots still never are.
    one_enemy = dict(no_enemies, attack=[True, True] + [False] * 7)
    seen_attack = set()
    for _ in range(2000):
        seen_attack.add(am.sample_masked(per_head["attack"], one_enemy["attack"], rng))
    expect(seen_attack <= {0, 1},
           "partially-masked attack only draws legal slots (got %s)" % sorted(seen_attack))
    expect(seen_attack == {0, 1},
           "partially-masked attack draws both legal slots (got %s)" % sorted(seen_attack))

    # --- 4. the mask arrays are logged alongside the chosen actions ---
    chosen = {
        name: am.argmax_masked(per_head[name], no_enemies[name]) for name in head_sizes
    }
    line = am.format_decision(chosen, no_enemies)
    expect("attack=0 mask=100000000" in line, "log line carries attack choice + mask: %s" % line)
    expect("target=0 mask=1000" in line, "log line carries target choice + mask: %s" % line)
    expect(
        all("%s=" % name in line for name in head_sizes),
        "log line carries every head: %s" % line,
    )
    logged = []
    expect(am.log_decision(chosen, no_enemies, logger=logged.append) == line,
           "log_decision returns the line it emits")
    expect(logged == [line], "log_decision emits exactly one line through the logger")

    if failures:
        for f in failures:
            print("FAIL", f)
        return 1
    print(
        "ACTIONMASK OK: parity=%r heads=%s draws=%d illegal-selected=%d log=%r"
        % (am.ILLEGAL_LOGIT, [n for n, _ in head_order], draws, illegal_selected, line)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
