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

**Trainer side.** The stock godot-rl flow: `StableBaselinesGodotEnv` →
`VecMonitor` → SB3 `PPO` ("MultiInputPolicy"). The repo already contains the
validated end-to-end connectivity harness — run it first on any new machine:

```bash
.venv-train/bin/python rl_connectivity_test.py --godot /usr/local/bin/godot --steps 96
```

Success = godot-rl's "connection established", PPO step logs, zero socket errors,
and NcnnSync staying in TRAINING mode (validated in issue #356 / PR #371).
For real training, write the same setup into a `train_forms.py` with the
checkpointing of your choice (see godot-rl's `examples/stable_baselines3_example.py`).

## 3. Export to ONNX, convert to ncnn via pnnx

1. **Export the trained policy to ONNX** (standard `torch.onnx.export` of the SB3
   policy network — `model.policy`, `torch.onnx.export(policy, dummy_obs,
   "policy.onnx")`; an LSTM-free MLP policy exports cleanly).
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
