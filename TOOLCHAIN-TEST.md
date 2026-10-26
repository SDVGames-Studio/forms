# Forms — verification toolchain

Verified facts for the Forms repo toolchain (as tested **2026-10-26**).

## Engine

- **Godot 4.7.2.stable** (`4.7.2.stable.official.ed1daf0bf`) at
  `/usr/local/bin/godot` — this local headless binary is the verification
  toolchain for this repo.

## Verified headless runs (2026-10-26)

- `godot --headless --path . --import` → **exit 0** (~8.3 s)
- Headless smoke run (`--headless` with `--quit-after`) → **exit 0** (~0.77 s)
- Editor plugin **godot-mcp v1.12.17** verified loading in a local project
  (local TCP bridge only; no network dependency).

## What this PR fixes

- Removes the 3 broken `[autoload]` entries pointing at
  `res://addons/godot_mcp/*.gd` (MCPScreenshot, MCPInputService,
  MCPGameInspector) from `project.godot`, so headless imports now run with
  **zero autoload errors** (before: 9 error lines, "File not found" for all
  three scripts).
- Adds `/addons/godot-mcp/` and `*.uid` to `.gitignore` — the local
  godot-mcp addon and Godot-generated `.uid` files stay uncommitted.

## History

- The old MCP HTTP server at `192.168.1.7:3000` is **retired**; the local
  headless `godot` binary is the one and only verification toolchain.
