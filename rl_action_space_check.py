#!/usr/bin/env python3
"""Action-space check: TrainingBot's multi-discrete contract (issue #422).

Verifies, with zero third-party dependencies, the Python-side Definition of
Done items of issue #422:

1. ``get_action_space()`` (TrainingBot.gd) is a valid multi-discrete
   dictionary: at least two heads, each ``{"size": int >= 2,
   "action_type": "discrete"}``, matching ACTION_SPEC.md (the locked
   contract, issue #411) head for head — name, order and size.
2. Each head's size is justified by the actual number of legal options in
   the game: ``attack == 1 + WeaponInventory.WEAPONS`` count and
   ``target == 1 + GameConfig.MAX_TEAM_MEMBERS`` — parsed from the game
   sources, so a game change that forgets the action space fails loudly.
3. The trainer's ``spaces.MultiDiscrete`` (or an exact stdlib replica when
   gymnasium is not installed — the full-venv trainer run stays covered by
   rl_connectivity_test.py) is constructible from the shipped dict: it
   accepts every legal joint action and rejects out-of-range ones.

Usage: python3 rl_action_space_check.py   (from the repository root)
"""

import json
import math
import os
import random
import re
import sys

REPO = os.path.dirname(os.path.abspath(__file__))


class MultiDiscreteReplica:
    """Stdlib stand-in for gymnasium.spaces.MultiDiscrete([n1, n2, ...]):
    one integer per head, each bounded by its head size."""

    def __init__(self, nvec):
        self.nvec = [int(n) for n in nvec]

    def contains(self, action) -> bool:
        return (
            isinstance(action, (list, tuple))
            and len(action) == len(self.nvec)
            and all(
                isinstance(a, int) and 0 <= a < n
                for a, n in zip(action, self.nvec)
            )
        )

    def sample(self, rng: random.Random):
        return [rng.randrange(n) for n in self.nvec]


def parse_trainingbot_heads():
    src = open(os.path.join(REPO, "scripts/TrainingBot.gd"), encoding="utf-8").read()
    m = re.search(r"func get_action_space\(\) -> Dictionary:(.*?)\nfunc ", src, re.S)
    if not m:
        sys.exit("FAIL: could not locate get_action_space() in TrainingBot.gd")
    heads = re.findall(
        r'"(\w+)": \{"size": (\d+), "action_type": "discrete"\}', m.group(1)
    )
    return [(name, int(size)) for name, size in heads]


def parse_spec_heads():
    src = open(os.path.join(REPO, "ACTION_SPEC.md"), encoding="utf-8").read()
    m = re.search(r"## 1\. `TrainingBot\.gd`.*?(?=\n## )", src, re.S)
    if not m:
        sys.exit("FAIL: could not locate section 1 of ACTION_SPEC.md")
    rows = re.findall(r"^\| `(\w+)` \| (\d+) \| discrete \|", m.group(0), re.M)
    return [(name, int(size)) for name, size in rows]


def parse_game_grounding():
    inv = open(os.path.join(REPO, "scripts/WeaponInventory.gd"), encoding="utf-8").read()
    m = re.search(r"const WEAPONS := \[(.*?)\]", inv, re.S)
    if not m:
        sys.exit("FAIL: could not locate const WEAPONS in WeaponInventory.gd")
    n_weapons = m.group(1).count(",") + 1 if m.group(1).strip() else 0
    cfg = open(os.path.join(REPO, "scripts/GameConfig.gd"), encoding="utf-8").read()
    m = re.search(r"const MAX_TEAM_MEMBERS := (\d+)", cfg)
    if not m:
        sys.exit("FAIL: could not locate const MAX_TEAM_MEMBERS in GameConfig.gd")
    return n_weapons, int(m.group(1))


def main() -> int:
    failures = []

    def expect(cond, what):
        if not cond:
            failures.append(what)

    heads = parse_trainingbot_heads()
    spec = parse_spec_heads()
    n_weapons, max_team = parse_game_grounding()

    # --- 1. valid multi-discrete dictionary, spec-locked ---
    expect(len(heads) >= 2, "multi-discrete needs >= 2 heads, got %d" % len(heads))
    expect(
        all(isinstance(s, int) and s >= 2 for _, s in heads),
        "every head size must be an int >= 2, got %s" % heads,
    )
    expect(heads == spec, "TrainingBot.gd heads %s != ACTION_SPEC.md heads %s" % (heads, spec))

    # --- 2. sizes justified by the actual legal options ---
    sizes = dict(heads)
    expect(
        sizes.get("attack") == 1 + n_weapons,
        "attack size %s != 1 + %d weapon slots" % (sizes.get("attack"), n_weapons),
    )
    expect(
        sizes.get("target") == 1 + max_team,
        "target size %s != 1 + MAX_TEAM_MEMBERS %d" % (sizes.get("target"), max_team),
    )

    # --- 3. the trainer builds a MultiDiscrete from the shipped dict ---
    wire = {
        name: {"size": size, "action_type": "discrete"} for name, size in heads
    }
    json.dumps(wire)  # must be JSON-serializable exactly as env_info ships it
    nvec = [size for _, size in heads]
    try:
        from gymnasium.spaces import MultiDiscrete  # real trainer dependency

        space = MultiDiscrete(nvec)
        space_contains = lambda a: space.contains(a)
        space_sample = lambda: space.sample()
    except ImportError:
        space = MultiDiscreteReplica(nvec)
        rng = random.Random(422)
        space_contains = space.contains
        space_sample = lambda: space.sample(rng)

    rng = random.Random(422)
    for _ in range(500):
        expect(space_contains(space_sample()), "sampled joint action must be in the space")
    expect(space_contains([0] * len(nvec)), "all-neutral joint action must be in the space")
    expect(
        not space_contains([n for n in nvec]),
        "all-max joint action must be OUT of the space",
    )
    expect(
        not space_contains([0] * (len(nvec) - 1)),
        "wrong-width joint action must be OUT of the space",
    )

    flat = sum(nvec)
    joint = math.prod(nvec)
    if failures:
        for f in failures:
            print("FAIL", f)
        return 1
    print(
        "MULTIDISCRETE OK: heads=%s nvec=%s flat-width=%d joint-cardinality=%d "
        "(attack=1+%d weapons, target=1+%d max enemies)"
        % ([n for n, _ in heads], nvec, flat, joint, n_weapons, max_team)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
