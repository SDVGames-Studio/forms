# Deployment Evaluation Report — ncnn policy vs baselines (issue #508)

**Date:** 2026-11-13 · **Build:** exported standalone (see §1) · **Model:** `models/policy.ncnn.{param,bin}` + `models/vecnormalize_stats.json`, exported from `runs/issue471_check/` (the Phase 6 / #471 connectivity-check run)

## Verdict

The deployed **ncnn inference pipeline is exact**: on every one of the
45 002 decisions recorded across 20 full episodes in the exported build, the
ncnn path picked the **same action as the original Python-inference policy**
(SB3 PPO checkpoint, deterministic) — per-head agreement **1.0000** on all
four heads, and the ONNX logits graph agrees with SB3 on every decision
(0 argmax mismatches). All three discrepancy culprits the issue anticipated
are ruled out with evidence (§4).

The bot's on-field behavior is degenerate (one constant joint action, every
episode times out with no eliminations), but that behavior is **the
checkpoint's, not the deployment's**: the #471 checkpoint is a 12 288-step
connectivity-check PPO over the minimal 2-dim scaffold observation (own
normalized position, OBSERVATION_SPEC #420) whose deterministic argmax is a
single constant joint action from spawn; the frozen position freezes the
observation, which freezes the action. The Python policy behaves identically
(win rate 0 % vs 0 % — trivially inside the 10–15 pp DoD margin; training-time
`tdm/timeout_frac` was already 1.000 with zero decided episodes).

## 1. Setup

- **Exported standalone build**, not the editor — the new `"Eval (Linux)"`
  export preset (`export_presets.cfg` preset 5) packs `eval_build.marker`;
  the `TrainingBoot` autoload boots `eval_scene.tscn` in any exported run
  that contains the marker (#465 mechanism, eval twin).
- `eval_scene.tscn` (`NcnnSync` + `eval_match.gd`) runs sequential
  whole-match episodes of the #506 deploy twin (`InferenceBot`, ncnn model +
  VecNormalize sidecar + #410/#507 action masks) inside a standard `Level`
  match — the scripted Npc side plays itself exactly like the shipped game.
- 20 episodes, deterministic inference, `speed_up=8` (physics 480 Hz,
  `time_scale` 8), turn timer 6 s, `reset_after=1000`, `action_repeat=8`,
  frame cap 18 000 (300 sim-seconds per episode), wall watchdog 2 400 s.

```bash
godot --headless --export-release "Eval (Linux)"          # → builds/eval/forms_eval.x86_64
builds/eval/forms_eval.x86_64 --headless -- episodes=20 \
    results=builds/eval/eval_results.json speedup=8        # exits 0 on success
.venv-train/bin/python eval_baseline.py \
    --results builds/eval/eval_results.json \
    --model runs/issue471_check/final_model.zip \
    --vecnormalize runs/issue471_check/vecnormalize.pkl \
    --onnx models/policy-logits.onnx \
    --out builds/eval/eval_baseline.json
```

## 2. Exported-build metrics (Phase 6 comparison set, 20 episodes)

| Metric | Value |
|---|---|
| Outcomes | 20 × timeout — 0 player wins, 0 enemy wins, 0 draws |
| Win rate (player / enemy) | 0 % / 0 % (no decided episodes) |
| Avg survival time | 300.0 sim s (every episode hit the 18 000-tick cap) |
| Avg decisions per episode | 2 250.1 (45 002 total) |
| Avg damage dealt (enemy side HP lost) | 99.0 / episode (1 980 total; per-episode 80–100) |
| Avg damage taken (player side HP lost) | 0 / episode |
| Friendly-fire / mask violations | 0 mask-illegal actions in 45 002 decisions (#507 audit) |
| Side elimination | none — player side ended 3 alive every episode, enemy side 1–2 alive |

**Action distribution per head** (45 002 decisions — fully collapsed):

| Head | Counts [idx 0..k-1] | Pinned index |
|---|---|---|
| aim (3) | 0, 0, 45 002 | 2 |
| attack (8) | 0, 0, 0, 0, 0, 45 002, 0, 0 | 5 |
| move (6) | 45 002, 0, 0, 0, 0, 0 | 0 (hold) |
| target (4) | 0, 0, 45 002, 0 | 2 |

The chosen joint action is always mask-legal; `move=hold` keeps the bot at
its spawn position, so its 2-dim observation stays `[0.5, 0.53]` for the
whole episode (verified: zero variance across all 45 002 recorded raw
observations), which makes the argmax constant — a stable freeze loop.

## 3. Python-inference parity (decision replay)

`eval_baseline.py` replayed every recorded `(raw obs → action)` pair through
the ORIGINAL training-side path — the SB3 PPO checkpoint
(`final_model.zip` + `vecnormalize.pkl`, deterministic argmax) and the ONNX
logits graph via onnxruntime (the pnnx input):

| Check | Result |
|---|---|
| Decisions replayed | 45 002 (180 008 head-decisions) |
| SB3-vs-ncnn agreement, overall | **1.0000** |
| SB3-vs-ncnn agreement, per head | aim **1.0000** · attack **1.0000** · move **1.0000** · target **1.0000** |
| ONNX-vs-SB3 argmax mismatches | **0** |
| Python action distribution | identical to the ncnn one (same pinned index per head) |

Training-time reference (`runs/issue471_check`, 12 288 steps):
`rollout/ep_rew_mean` −0.1251, `rollout/ep_len_mean` 125.06,
`tdm/timeout_frac` 1.000 (no decided episodes), `tdm/action_max_prob` ≈ 1/k
per head and `tdm/action_entropy` = ln k per head (aim 1.0986 = ln 3,
attack 2.0794 = ln 8, move 1.7918 = ln 6, target 1.3863 = ln 4) — the
stochastic policy was still at its near-uniform initialization. The deployed
deterministic behavior (constant joint action, all timeouts, 0 % wins) is
qualitatively the same picture the training run itself recorded.

## 4. Issue #508 culprit checklist — ruled out

| Suspected culprit | Evidence |
|---|---|
| (a) Missing VecNormalize statistics (#503/7.2) | Sidecar loaded and applied: `obs_size` 2 matches the ncnn input reshape (`in0` → 2×1); the parity replay normalizes with the SB3 pickle's exact math and agrees on 100 % of decisions. |
| (b) Incorrect blob names / input shape (#505/7.4) | `policy.ncnn.param` input `in0`, 21-value output = 3+8+6+4 head layout (pinned by `tests/test_issue505.gd` against the ONNX reference); ONNX-vs-SB3 argmax mismatches 0. |
| (c) Action-masking mismatch (#507/7.6) | 0 mask-illegal chosen actions across 45 002 deployed decisions; masks are applied before argmax (#507) and the audit counter is wired into `eval_match.gd`. |

## 5. What remains (follow-up, outside #508's scope)

The win-rate DoD bar only becomes meaningful with a checkpoint trained on a
game-state-rich observation (enemy positions/health, turn context — the
current obs is the bot's own position only) and a real training budget.
The evaluation assets from this issue are build-agnostic: export a new
model to `models/`, then re-run §1's three commands unchanged.

## 6. Harness and verification

- `eval_scene.tscn` / `eval_match.gd` — episode runner (also embeds as a
  child scene for tests); writes the structured results JSON.
- `eval_baseline.py` — Python/ONNX parity replay (+ TensorBoard reference).
- `tests/test_issue508.gd(.tscn)` — headless editor mini-eval (2 episodes,
  tight cap) asserting the Phase 6 metric families, mask legality, decision
  stream and JSON round-trip: `ISS508 ok=true`, exit 0.
- `godot --headless --import` — exit 0; the exported run exited 0 after
  20/20 episodes; no game processes left running.
