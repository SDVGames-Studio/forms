
from pathlib import Path

PROJECT_FILE = Path("project.godot")

MCP_AUTOLOADS = {
    "MCPScreenshot",
    "MCPInputService",
    "MCPGameInspector",
}


def main() -> None:
    lines = PROJECT_FILE.read_text(encoding="utf-8").splitlines(keepends=True)

    result = []
    section = ""

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            result.append(line)
            continue

        if section == "autoload":
            key, separator, _ = stripped.partition("=")
            if separator and key.strip() in MCP_AUTOLOADS:
                continue

        result.append(line)

    PROJECT_FILE.write_text("".join(result), encoding="utf-8")
    print("Removed Godot MCP autoloads for CI.")


if __name__ == "__main__":
    main()
