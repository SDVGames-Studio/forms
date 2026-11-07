# Forms

2D turn-based artillery game — teams of figures (triangles, squares, circles…).
Main reference: Worms: Armageddon.

## Running

- Engine: **Godot 4.7** (`config/features` in `project.godot`; GL Compatibility renderer).
- Open the project in the Godot editor and press Play, or run `godot --path .`
  (main scene: `Main.tscn`).
- Headless verification for this repo uses local Godot 4.7.2
  (`godot --headless --import`) — see `TOOLCHAIN-TEST.md`.

## Godot Native RL (ncnn) readiness — confirmed 2026-11-06

The full train → export → convert → deploy pipeline, with pinned tool versions,
lives in [`DEPLOYMENT.md`](DEPLOYMENT.md).

- **Engine requirement met.** The Godot Native RL GDExtension requires Godot
  **4.5+** (`compatibility_minimum = "4.5"` in
  `addons/godot_native_rl/ncnn_runner.gdextension`); this project runs
  **4.7** with the plugin enabled in Project Settings → Plugins.
- **No .NET or Python runtime is needed for inference.** ncnn inference is a
  statically-linked C++ GDExtension; training happens externally with
  `godot_rl_agents` (see `addons/godot_native_rl/README.md`).

## Target platforms

Export presets configured in `export_presets.cfg`: **Linux, Windows Desktop,
Web, Android** (`com.sdvgames.forms`). macOS has no preset today.

Committed GDExtension binaries: **Linux x86_64 only**
(`addons/godot_native_rl/bin/`, debug + release, self-contained,
glibc ≤ 2.38). The `.gdextension` manifest keeps entries for every platform;
the other binaries (~150 MB) were trimmed from the repo.

### Platform-specific steps

- **Linux** — works as committed; nothing extra to do.
- **Windows / Android** — before exporting, drop the matching
  `bin/libncnn_runner.{windows,android}.*` binaries in from the upstream
  `godot-native-rl-addon-v0.4.0.zip` release (verify SHA256 against the
  release checksums). Android ships arm64 and x86_64 variants.
- **Web** — needs the dedicated **wasm32 nothreads/dlink** build of the
  GDExtension (CPU/SIMD only, no in-browser GPU). In the Web export preset set
  **Extension Support: ON** and **Thread Support: OFF** — the bundled WASM is
  single-threaded, so the game needs no COOP/COEP headers (runs on itch.io /
  GitHub Pages unchanged).
- **macOS** (only if a preset is added later) — Gatekeeper quarantines
  downloaded `.dylib` files; clear it with
  `xattr -dr com.apple.quarantine addons/godot_native_rl/bin`
  or build from source.

Upstream project: <https://github.com/minigraphx/godot-native-rl> — addon docs:
`addons/godot_native_rl/README.md`.
