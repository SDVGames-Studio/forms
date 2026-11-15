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

## Phase 1: Build the Native Extension
Because you are using ncnn, you must compile the GDExtension from source. Keep this build **outside** your game project.

```bash
# 1. Clone the extension repository
cd /run/media/gleb/storage/repos/
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
cp -r /run/media/gleb/storage/repos/godot-native-rl/addons/godot_native_rl \
      /run/media/gleb/storage/repos/forms/addons/
```

---

## Phase 2: Godot Project Setup
1. Open the `forms` project in Godot.
2. Go to **Project → Project Settings → Plugins** and enable **Godot Native RL**.
3. Verify your `training_scene.tscn`:
   *   Root node should be `NcnnSync` (control mode set to `TRAINING`).
   *   Multiple instances of your environment should be placed far apart (e.g., 3000 units) to prevent physics overlap.
   *   Your bot script (e.g., `TrainingBot.gd`) must extend `NcnnAIController2D`.

---

## Phase 3: Python Training Environment
Set up a dedicated Python environment to avoid dependency conflicts.

```bash
cd /run/media/gleb/storage/repos/forms

# 1. Create and activate virtual environment
python3 -m venv venv_sb3
source venv_sb3/bin/activate

# 2. Install godot-rl and Stable-Baselines3 (Quotes are required for zsh)
pip install 'godot-rl[sb3]'

# 3. Download the standard training script
curl -o stable_baselines3_example.py https://raw.githubusercontent.com/edbeeching/godot_rl_agents/main/examples/stable_baselines3_example.py
```

---

## Phase 4: Export the Training Binary
Python cannot easily run the Godot editor; it needs a standalone executable.

1. In Godot, go to **Project → Export**.
2. Select the **Training (Linux)** preset.
3. Set the **Export Path** to: `res://builds/training/forms.x86_64`.
4. ⚠️ **Crucial:** Go to the **Resources** tab. In "Filters to exclude files/folders", add `tests/*` to prevent Godot from trying to compile test scripts (which causes Parse Errors).
5. Click **Export Project**.
6. In your terminal, make the binary executable:
   ```bash
   chmod +x builds/training/forms.x86_64
   ```

---

## Phase 5: Run Training
Ensure you are in the project root, with your virtual environment activated.

```bash
python stable_baselines3_example.py \
  --env_path=builds/training/forms.x86_64 \
  --n_parallel=4 \
  --speedup=20 \
  --timesteps=1000000 \
  --experiment_name=forms_v1
```

*   `--n_parallel=4`: Runs 4 instances of the game simultaneously to collect data faster.
*   `--speedup=20`: Runs the game physics 20x faster than real-time.
*   `--timesteps`: Total steps to train (1,000,000 is a good starting point).
*   `--experiment_name`: Saves logs and models to `./logs/sb3/forms_v1`.

**Monitoring:** 
You can monitor progress using TensorBoard in a separate terminal:
```bash
tensorboard --logdir ./logs/sb3
```

### ⚠️ Common Training Pitfalls
*   **`ep_len_mean: 1`**: The episode is ending after 1 step. Check your `reset()` function in `TrainingBot.gd`. Ensure `needs_reset` is set to `false` at the start, and that `game_over()` is not being called immediately.
*   **Leaked Instances on Exit**: Errors like `ObjectDB instances leaked` at the very end of training are **harmless** socket-close artifacts. Ignore them.
*   **Slow Training**: If FPS is low, reduce `--n_parallel` (your CPU may be bottlenecked) or increase `--speedup`.

---

## Phase 6: Deployment (Exporting to ncnn)
Once `ep_rew_mean` (average reward) stabilizes and the bot plays well, you are ready to extract the brain.

### 1. Convert SB3 to ONNX
The trained model is saved as a `.zip` file in `./logs/sb3/forms_v1/`. You must convert it to ONNX first.

```python
# create a file named export_onnx.py
import torch
import torch.nn as nn
from stable_baselines3 import PPO

# Load your trained model
model = PPO.load("./logs/sb3/forms_v1/final_model.zip")

# Wrapper to only output actions (no value function)
class OnnxablePolicy(nn.Module):
    def __init__(self, policy):
        super().__init__()
        self.policy = policy
    def forward(self, observation):
        return self.policy(observation, deterministic=True)[0]

# Export
dummy_input = torch.randn(1, model.observation_space.shape[0])
torch.onnx.export(
    OnnxablePolicy(model.policy), 
    dummy_input, 
    "policy.onnx", 
    opset_version=17,
    input_names=['input'],
    output_names=['action']
)
```

Run it: `python export_onnx.py`

### 2. Convert ONNX to ncnn
Install `pnnx` and run the conversion:
```bash
pip install pnnx
pnnx policy.onnx
```
This generates two files: `policy.ncnn.param` and `policy.ncnn.bin`.

### 3. Integrate into Godot
1. Copy `policy.ncnn.param` and `policy.ncnn.bin` into your Godot project at `res://models/`.
2. Open your Bot scene.
3. Select the `NcnnAIController2D` node.
4. Set `control_mode` to `NCNN_INFERENCE`.
5. Set `model_param_path` to `res://models/policy.ncnn.param`.
6. Set `model_bin_path` to `res://models/policy.ncnn.bin`.
7. **Important:** If you used `VecNormalize` during training, ensure your observation normalization logic is applied in GDScript before passing the input to the ncnn runner.

Now, when you run the game normally in Godot (or export it for players), the bot will think for itself using the compiled ncnn model—no Python or external servers required.
