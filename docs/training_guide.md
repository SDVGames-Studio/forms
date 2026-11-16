# 🧠 Godot RL Training & Deployment Guide (ncnn Pipeline)

This document covers the entire lifecycle: from compiling the C++ inference extension to training a PPO agent, and finally exporting the trained brain back into the game for native inference.

## 🛠️ Prerequisites
Ensure the following tools are installed on your system:
*   **Godot 4.5+** (Standard version, not .NET/Mono).
*   **Python 3.10+** (with `venv`).
*   **C++ Toolchain** (`build-essential` on Linux).
*   **SCons** (`sudo apt install scons` or via pip).
*   **CMake** (`sudo apt install cmake`).

---

## Phase 1: Build the Native Extension (One-time setup)
Because you are using ncnn, you must compile the GDExtension from source. Keep this build **outside** your game project.

```bash
# 1. Clone the extension repository
git clone https://github.com/minigraphx/godot-native-rl.git
cd godot-native-rl

# 2. Clone dependencies into the correct folders
git clone -b 4.5 https://github.com/godotengine/godot-cpp.git
mkdir -p thirdparty
git clone https://github.com/Tencent/ncnn.git thirdparty/ncnn

# 3. Build godot-cpp bindings
cd godot-cpp
scons platform=linux target=template_debug -j$(nproc)
scons platform=linux target=template_release -j$(nproc)
cd ..

# 4. Build ncnn as a static library (OpenMP disabled for self-contained binaries)
cmake -S thirdparty/ncnn -B thirdparty/ncnn/build \
  -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_EXAMPLES=OFF \
  -DNCNN_BUILD_BENCHMARK=OFF -DBUILD_SHARED_LIBS=OFF -DNCNN_OPENMP=OFF
cmake --build thirdparty/ncnn/build --config Release -j$(nproc)
cmake --install thirdparty/ncnn/build --prefix thirdparty/ncnn/build/install

# 5. Build the GDExtension
scons platform=linux target=template_debug ncnn_openmp=no -j$(nproc)
scons platform=linux target=template_release ncnn_openmp=no -j$(nproc)
```

**Copy to your game project:**
```bash
cp -r ./addons/godot_native_rl \
      ../forms/addons/
```

---

## Phase 2: Python Environment Setup
All Python-related code lives in the `ml_pipeline/` folder. 
The folder contains a `.gdignore` file so Godot ignores it.

From the root of the Godot-project:
```bash
cd ./ml_pipeline

# 1. Create and activate virtual environment
python3 -m venv .venv-train
source .venv-train/bin/activate

# 2. Install ALL dependencies (training + export + conversion)
pip install -r requirements.txt
```

---

## Phase 3: Export the Training Binary
1. In Godot, go to **Project → Export**.
2. Select the **Training (Linux)** preset.
3. Set the **Export Path** to: `res://builds/training/forms_training.x86_64`.
4. ⚠️ **Crucial:** Go to the **Resources** tab. In "Filters to exclude files/folders", add `tests/*` and `ml_pipeline/*` to prevent Godot from trying to compile them.
5. Click **Export Project**.
6. In your terminal, make the binary executable:
   ```bash
   chmod +x ../builds/training/forms_training.x86_64
   ```

---

## Phase 4: Run Training
Ensure you are inside `ml_pipeline/` with `.venv-train` activated.

```bash
python train.py \
  --env_path=../builds/training/forms_training.x86_64 \
  --n_parallel=4 \
  --speedup=20 \
  --timesteps=1000000 \
  --experiment_dir=runs/tdm_v1
```

**Monitoring:** 
You can monitor progress using TensorBoard in a separate terminal:
```bash
tensorboard --logdir runs/tdm_v1
```

### ⚠️ Critical Training Pitfalls
*   **`ep_len_mean: 1`**: If this metric drops to 1 and stays there, your environment is broken and the agent is not learning. 
    *   Check your `reset()` function in `TrainingBot.gd` to ensure `needs_reset = false` is set. 
    *   Ensure `game_over()` isn't being called immediately on the first frame after a reset.
*   **Leaked Instances on Exit**: `ObjectDB instances leaked` errors at the end of training are harmless socket-close artifacts.

---

## Phase 5: Deployment (Exporting to ncnn)
Once `ep_rew_mean` (average reward) stabilizes and the bot plays well, extract the brain. 
Because your setup uses `MultiInputPolicy` and `VecNormalize`, the export process requires handling dictionary observations and normalization stats.

### 1. Export to ONNX
Ensure you are inside `ml_pipeline/` with `.venv-train` activated, and run the export script already present in the repository:

```bash
python export_onnx.py
```
*(This generates `policy.onnx` based on `runs/tdm_v1/final_model.zip`).*

### 2. Export VecNormalize Statistics
Run the existing script to generate the normalization sidecar (e.g., `vecnormalize_stats.json`). 
You will need this in Godot to process the raw observations before feeding them to ncnn.

```bash
python export_vecnormalize_stats.py
```

### 3. Convert ONNX to ncnn
Convert the ONNX model to the `.param` and `.bin` files required by the GDExtension using `pnnx`. 

```bash
pnnx ./models/policy.onnx
```
*(Note: Because your model uses dictionary observations, you may need to specify input shapes if `pnnx` fails to infer them automatically, e.g., `pnnx policy.onnx inputshape=[1,OBS_SIZE_1],[1,OBS_SIZE_2]`).*
This generates `policy.ncnn.param` and `policy.ncnn.bin`.

### 4. Integrate into Godot
1. Copy `policy.ncnn.param`, `policy.ncnn.bin`, and `vecnormalize_stats.json` into `res://models/`.
2. Open your Bot scene.
3. Select the `NcnnAIController2D` node.
4. Set `control_mode` to `NCNN_INFERENCE`.
5. Set `model_param_path` to `res://models/policy.ncnn.param`.
6. Set `model_bin_path` to `res://models/policy.ncnn.bin`.
7. Set `obs_norm_stats_path` to `res://models/vecnormalize_stats.json` (or ensure your GDScript applies the normalization logic before the ncnn forward pass).

Now, when you run the game normally in Godot, the bot will think for itself using the compiled ncnn model—no Python required.
