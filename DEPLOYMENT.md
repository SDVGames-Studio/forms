# Forms — ncnn AI deployment pipeline

End-to-end guide for training the Forms bots, converting them to ncnn, and running
them in-game. Target audience: contributors and the autonomous agent. Versions are
pinned in [`requirements-train.txt`](requirements-train.txt) and
[`requirements-convert.txt`](requirements-convert.txt).

The pipeline in one line:

```
Python (godot-rl + SB3 PPO)  →  ONNX export  →  pnnx convert  →  *.ncnn.param/.bin
                              →  NcnnAIController2D (control_mode = NCNN_INFERENCE)
```

No Python, .NET, or ONNX runtime ships with the game — inference is a
statically-linked C++ GDExtension (ncnn) bundled in
[`addons/godot_native_rl/`](addons/godot_native_rl/README.md).

---

## 1. Toolchain and pinned versions

| Tool | Pinned version | Role |
|---|---|---|
| Godot | 4.7.2.stable (engine requirement: 4.5+) | editor + headless verification (`TOOLCHAIN-TEST.md`) |
| godot-native-rl addon | **v0.4.0** (bundled in `addons/godot_native_rl/`, `plugin.cfg`) | in-game ncnn inference + training bridge |
| godot-rl | **0.8.2** (`requirements-train.txt`) | Python trainer, speaks the NcnnSync wire protocol |
| Stable-Baselines3 | **2.4.0** (godot-rl 0.8.2 declares `stable-baselines3<=2.4.0`) | PPO implementation |
| gymnasium | **1.0.0** (godot-rl 0.8.2 declares `gymnasium<=1.0.0`) | RL API shim |
| torch | **>=2.3,<3** (CPU wheels are enough — validated on CPU in PR #371) | tensor backend + ONNX export |
| pnnx | **20261020** (`requirements-convert.txt`) | ONNX → ncnn converter |
| ncnn | 1.0.20261020 (`requirements-train.txt`) | Python ncnn bindings — conversion parity check only |
| onnx / onnxruntime | 1.23.2 / 1.31.1 (`requirements-train.txt`) | export + parity check only |

Two virtualenvs (mirrors the upstream split — the trainer and the converter have
disjoint dependency sets):

```bash
python3 -m venv .venv-train && .venv-train/bin/pip install -r requirements-train.txt
python3 -m venv .venv-convert && .venv-convert/bin/pip install -r requirements-convert.txt
```

## 2. Training workflow (Python + godot_rl_agents)

**Game side (already wired).** `training_scene.tscn` contains an `NcnnSync` node
(`control_mode = 1`, TRAINING) with tiled `Environment_*` children — each a Level
instance plus a `Bot` node running [`TrainingBot.gd`](TrainingBot.gd)
(extends `NcnnAIController2D`; implements the minimal obs/reward/action-space
contract so the scene steps against the trainer out of the box — issue #341;
registers itself in the `AGENT` group at `_ready()` for NcnnSync discovery).
Game-specific observations, reward shaping, and actions are layered on in
follow-up issues; the training scene needs no changes for the pipeline itself.

**Trainer side.** The stock godot-rl flow, as wired up by
[`train.py`](train.py) (issues #466/#467): `StableBaselinesGodotEnv` →
`VecMonitor` → `VecNormalize` → SB3 `PPO` ("MultiInputPolicy"). **VecNormalize
(issue #468)** normalizes both observations and rewards with running statistics
(`norm_obs=True`, `norm_reward=True`, `clip_obs=10.0`, `clip_reward=10.0`) —
critical for PPO stability, since raw rewards may have large magnitudes or high
variance across components and would otherwise let a single component dominate
the gradient updates. `train.py` saves the running statistics to
`<experiment_dir>/vecnormalize.pkl` next to `final_model.zip`, and after every
run verifies a sample batch of normalized observations has mean ≈ 0 and
std ≈ 1. The repo also ships the validated end-to-end connectivity harness —
run it first on any new machine:

### Checkpoints and final artifacts (issue #471)

Every `--checkpoint_every` timesteps (default 100 000, `0` disables)
`train.py` saves a checkpoint into `<experiment_dir>/checkpoints/` using SB3's
standard `CheckpointCallback` naming — `rl_model_<timesteps>_steps.zip`, each
with a co-located `rl_model_<timesteps>_steps_vecnormalize.pkl` normalization
snapshot, so any intermediate checkpoint can be resumed or exported exactly
like the final model (with the default 500 k `--timesteps` that is 5
checkpoints per run). The checkpoint directory lives inside the experiment
directory — this repo's SB3-convention experiment root (`runs/<experiment_name>/`,
the role `./logs/sb3/<experiment_name>/` plays in the upstream examples) — so
TensorBoard event files, checkpoints, model and statistics all sit under one
path per experiment and stay discoverable together.

At the end of training the deployment artifacts are written to the same
experiment directory:

| Artifact | Path |
|---|---|
| final policy (`model.save()`) | `runs/<experiment_name>/final_model.zip` |
| VecNormalize statistics (REQUIRED at inference) | `runs/<experiment_name>/vecnormalize.pkl` |

**These two files are the input to the Phase 7 export pipeline (§3)** — e.g. for
the Phase 6 run `runs/issue471_check/final_model.zip` +
`runs/issue471_check/vecnormalize.pkl`.

### Monitoring training (issue #469)

Watch every experiment live with TensorBoard pointed at the runs directory:

```bash
tensorboard --logdir runs/        # all experiments
# or one experiment: tensorboard --logdir runs/tdm_v1
# then open http://localhost:6006
```

PPO writes the standard SB3 curves (`rollout/ep_rew_mean`,
`rollout/ep_len_mean`, `train/policy_gradient_loss`, `train/value_loss`,
`train/entropy_loss`, …) on its own. `train.py --metrics_every N`
(default 4096) adds the team-deathmatch curves from
[`training_metrics.py`](training_metrics.py), written every N timesteps:

| Tag | Meaning |
|---|---|
| `tdm/win_rate` | decided episodes won (episode carried a REWARD_SPEC §2.9 `episode_outcome`) — the scripted-baseline side is the training env itself |
| `tdm/timeout_frac` | episodes ended without an outcome (horizon truncations) |
| `tdm/avg_episode_length` | mean VecMonitor episode length |
| `tdm/reward/<component>` | per-step mean of each REWARD_SPEC §2 component — the reward breakdown |
| `tdm/action_dist/<head>/<i>` | mean probability of action index `i` on head `move`/`aim`/`attack`/`target` |
| `tdm/action_max_prob/<head>` | the head's largest mean probability — the collapse indicator (one index dominating every head ⇒ revisit `--ent_coef` or reward shaping) |
| `tdm/action_entropy/<head>` | mean action entropy in nats (`ln(k)` = uniform) |

`rl_metrics_check.py` verifies the whole callback offline (no Godot build
needed) against a miniature stand-in env.

```bash
.venv-train/bin/python rl_connectivity_test.py --godot /usr/local/bin/godot --steps 96
```

Success = godot-rl's "connection established", PPO step logs, zero socket errors,
and NcnnSync staying in TRAINING mode (validated in issue #356 / PR #371).
For real training run `train.py` (see its `--help`; hyperparameters in
[`HYPERPARAMETERS.md`](HYPERPARAMETERS.md)).

**Standalone training executable (issue #465).** The "Training (Linux)" export
preset in `export_presets.cfg` builds the subprocess binary the Python trainer
launches (godot-rl expects an `*.x86_64` executable) — no editor needed, so
`n_parallel` is no longer capped at 1:

```bash
godot --headless --export-debug "Training (Linux)"
# → builds/training/forms_training.x86_64 (+ .pck and the GDExtension .so)
```

- Needs the Godot **4.7.2 export templates** installed
  (`~/.local/share/godot/export_templates/4.7.2.stable/`).
- Export presets cannot override `application/run/main_scene`, so the
  `TrainingBoot` autoload (`scripts/TrainingBoot.gd`) routes exported builds
  that carry `training_build.marker` (packed only by this preset's
  `include_filter`) to `training_scene.tscn`. Every other build — the editor,
  and the normal Linux/Windows/Web/Android exports — boots the main menu
  unchanged (verified: the marker is absent from their `.pck`).
- The three `Environment_*` instances in `training_scene.tscn` are tiled
  **3200 units apart** (the 3000+ required so physics never crosses between
  parallel environments); `NcnnSync.control_mode = 1` (TRAINING).
- Sanity check without a trainer: launch the binary — it runs without crashing
  and NcnnSync logs it couldn't connect to the Python server ("Start training
  with `gdrl`"). With a trainer listening on the default port **11008**
  (`--port` overrides), NcnnSync connects and handshakes; point godot-rl at the
  binary via `StableBaselinesGodotEnv(environment_path=...)`.

**Shared policies by role (issue #445).** Team deathmatch trains multiple
bots of the same role on ONE shared network: every controller in the scene
carries an explicit `policy_name` naming its role. Current role-to-policy
mapping:

| Role | `policy_name` | Controllers |
|---|---|---|
| soldier (scaffold training bot) | `soldier` | the 3 `Bot` nodes in `training_scene.tscn` |

`NcnnSync` reports each agent's `policy_name` in the handshake's
`agent_policy_names` field; `rl_connectivity_test.py` prints
`POLICIES OK: N distinct policy_name(s) …` after a run (`--expected-policies`
asserts the count). Today's single-role scene reports **1**. Rules for
extending the roster:

- Same role → same `policy_name`: the agents share network weights, which is
  significantly more sample-efficient for homogeneous teams.
- Distinct role (e.g. a medic with different abilities) → its own
  `policy_name`. Multi-policy training needs RLlib, not SB3 (SB3 trains a
  single shared policy); with SB3 keep one role per training run. For
  separate *training identities* beyond the role name there is also
  `NcnnSync.multi_policy = true`, which switches the wire to each agent's
  `policy_group` (issue #73) — `policy_name` stays the role key.
- **Critical constraint:** every agent sharing a `policy_name` must return
  IDENTICAL `get_obs()` and `get_action_space()` shapes — the trainer builds
  the wire spaces from the group's first agent and any drift fails the
  pipeline with a space-mismatch error. `tests/test_issue445.gd` (headless:
  `godot --headless res://tests/test_issue445.tscn`) guards the shipped
  scene and demonstrates the legal two-role layout.

## 3. Export to ONNX, convert to ncnn via pnnx

1. **Export the trained policy to ONNX** with
   [`export_onnx.py`](export_onnx.py) (issue #502). It wraps `model.policy` in
   a deterministic module (argmax per MultiDiscrete head), exports the actor
   only at opset 17, names the tensors `input` `(1, OBS_SIZE)` and `action`,
   and verifies the graph in one pass: `onnx.checker.check_model` + an
   onnxruntime inference whose output must exactly match the PyTorch
   `deterministic=True` output. Input artifacts (issue #471):
   `runs/<experiment_name>/final_model.zip` plus its co-located
   `runs/<experiment_name>/vecnormalize.pkl` (§2). **When trained
   with `train.py`, the policy expects VecNormalize-normalized observations**;
   `export_onnx.py` normalizes only its dummy input for the parity check and
   does NOT bake the normalization into the graph — the game replays it
   pre-inference via the `obs_norm_stats_path` sidecar (step 4).

   ```bash
   .venv-train/bin/python export_onnx.py \
       --model runs/issue471_check/final_model.zip \
       --vecnormalize runs/issue471_check/vecnormalize.pkl \
       --out models/policy.onnx
   # current checkpoint: TrainingBot obs size 2 (OBSERVATION_SPEC.md),
   # action heads MultiDiscrete([3, 8, 6, 4]) (ACTION_SPEC.md)
   ```
2. **Convert** with pnnx (from the convert venv). `inputshape` must match the
   bot's observation size:

   ```bash
   .venv-convert/bin/pnnx models/policy.onnx inputshape=[1,OBS_SIZE]
   # → models/policy.ncnn.param + models/policy.ncnn.bin
   ```

3. **Verify parity** (strongly recommended — a bad conversion fails *silently*:
   the bot just plays subtly wrong). With the train venv:

   ```bash
   .venv-train/bin/python - <<'EOF'
   import ncnn, numpy as np, onnxruntime as ort
   OBS_SIZE = 2  # TrainingBot.get_obs() width — set to your policy's obs size
   sess = ort.InferenceSession("models/policy.onnx")
   net = ncnn.Net()
   net.load_param("models/policy.ncnn.param")
   net.load_model("models/policy.ncnn.bin")
   for _ in range(50):
        obs = np.random.rand(1, OBS_SIZE).astype(np.float32)
        ref = sess.run(None, {sess.get_inputs()[0].name: obs})[0]
        ex = net.create_extractor()
        ex.input("in0", ncnn.Mat(obs))
        _, out = ex.extract("out0")
        got = np.array(out).reshape(-1)
        assert ref.argmax() == got.argmax(), "argmax mismatch"
   print("parity OK")
   EOF
   ```

   (The upstream [godot-native-rl](https://github.com/minigraphx/godot-native-rl)
   repo ships `scripts/export_to_ncnn.py` + `scripts/verify_ncnn_parity.py`, which
   wrap steps 1–3 into one command with auto-derived shapes if you check it out.)

## 4. Deploy: controller properties for inference

Copy `policy.ncnn.param` + `policy.ncnn.bin` into `res://models/`.
On the bot node (a script extending `NcnnAIController2D`, e.g. `TrainingBot.gd` /
`BotController.gd`), set in the Inspector:

| Property | Value |
|---|---|
| `control_mode` | `NCNN_INFERENCE` (enum value 3 on the controller; or leave `INHERIT_FROM_SYNC` and set `control_mode = 2`, NCNN_INFERENCE, on the `NcnnSync` node) |
| `model_param_path` | `res://models/policy.ncnn.param` |
| `model_bin_path` | `res://models/policy.ncnn.bin` |
| `input_blob_name` / `output_blob_name` | `in0` / `out0` (defaults; godot-rl/pnnx exports) |

Optional sidecars (same folder, JSON): `obs_norm_stats_path` (VecNormalize),
`action_dist_stats_path` (continuous DiagGaussian std), `recurrent_stats_path`
(LSTM hidden-state carry). `deterministic_inference = true` (default) takes the
argmax action; set `inference_seed >= 0` for reproducible eval runs.

**VecNormalize statistics are REQUIRED for inference (issue #468).** `train.py`
normalizes observations and rewards with SB3's VecNormalize, so the ncnn model
expects *normalized* inputs. If the game feeds raw `get_obs()` values to a
policy trained this way, the policy receives out-of-distribution inputs and
behaves unpredictably. Convert the saved `vecnormalize.pkl` into the JSON
sidecar the controller replays pre-inference (the exact transform —
`(obs - mean) / sqrt(var + epsilon)`, clamped to `clip_obs` — is mirrored by
[`addons/godot_native_rl/controllers/obs_normalize.gd`):

```bash
.venv-train/bin/python - <<'EOF'
import json, pickle
with open("runs/issue471_check/vecnormalize.pkl", "rb") as f:
    norm = pickle.load(f)  # VecNormalize.save() pickles the wrapper itself
rms = norm.obs_rms
# Dict observation space (godot-rl: {"obs": flat_vector}) -> per-key stats;
# the in-game controller consumes the flattened "obs" vector.
if isinstance(rms, dict):
    rms = rms["obs"]
sidecar = {
    "obs_size": int(rms.mean.size),
    "mean": rms.mean.tolist(),
    "var": rms.var.tolist(),
    "epsilon": float(norm.epsilon),
    "clip_obs": float(norm.clip_obs),  # exactly what training clipped to
}
with open("models/policy.norm.json", "w") as f:
    json.dump(sidecar, f)
EOF
```

Then set `obs_norm_stats_path = res://models/policy.norm.json` on the controller
node alongside `model_param_path`/`model_bin_path`. Skipping this sidecar on a
VecNormalize-trained policy silently degrades the bot (no load error — just
out-of-distribution inputs).

The plugin must be **enabled** (Project → Project Settings → Plugins → *Godot
Native RL*): it auto-packs `*.ncnn.param` / `*.ncnn.bin` into every export —
without it, exported builds crash with `cannot read model files`.

## 5. Platform-specific build notes

- **Linux** — works as committed; nothing extra to do.
- **Windows / Android** — drop the matching `bin/libncnn_runner.{windows,android}.*`
  binaries in from the upstream `godot-native-rl-addon-v0.4.0.zip` release
  (verify SHA256 against the release checksums). Android ships arm64 + x86_64.
- **Web (WASM)** — needs the dedicated **wasm32 nothreads/dlink** build (CPU/SIMD
  only). Web export preset: **Extension Support: ON**, **Thread Support: OFF** —
  the bundled WASM is single-threaded, so no COOP/COEP headers are needed
  (runs on itch.io / GitHub Pages).
- **macOS** — Gatekeeper quarantines downloaded dylibs; after adding a macOS
  preset: `xattr -dr com.apple.quarantine addons/godot_native_rl/bin`.

## 6. Verification checklist

1. `godot --headless --path . --import` → exit 0 (see `TOOLCHAIN-TEST.md`).
2. `rl_connectivity_test.py --steps 96` passes (training bridge healthy).
3. Run the game: bot loads the model without `cannot read model files` /
   `Failed to load ncnn model` errors and acts on every step.
