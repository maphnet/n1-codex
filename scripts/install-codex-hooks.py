#!/usr/bin/env python3
"""Install stable user hooks so plugin upgrades do not invalidate hook trust."""

import json
import os
from pathlib import Path


DISPATCH = r'''#!/usr/bin/env bash
set -euo pipefail
event=${1:?missing hook event}
root=${CODEX_PLUGIN_ROOT:-${N1_PLUGIN_ROOT:-}}
if [ -z "$root" ] || [ ! -f "$root/hooks/$event.sh" ]; then
    cache="$HOME/.codex/plugins/cache/n1-codex/n1-codex"
    root=$(find "$cache" -mindepth 3 -maxdepth 3 -type f -path '*/hooks/*.sh' \
        -printf '%h/..\n' 2>/dev/null | sort -V | tail -1)
fi
[ -n "$root" ] && [ -f "$root/hooks/$event.sh" ] || exit 0
exec bash "$root/hooks/$event.sh"
'''


def hook(event: str) -> dict:
    return {"hooks": [{"type": "command", "command": f'bash "$HOME/.n1-codex/hooks/dispatch.sh" {event}'}]}


def main() -> None:
    home = Path(os.environ.get("HOME", "~")).expanduser()
    state = home / ".n1-codex"
    dispatch = state / "hooks" / "dispatch.sh"
    dispatch.parent.mkdir(parents=True, exist_ok=True)
    dispatch.write_text(DISPATCH)
    dispatch.chmod(0o755)

    config_path = home / ".codex" / "hooks.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        config = json.loads(config_path.read_text()) if config_path.exists() else {}
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"cannot read {config_path}: {exc}")
    if not isinstance(config, dict):
        raise SystemExit(f"invalid hooks configuration in {config_path}")
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise SystemExit(f"invalid hooks configuration in {config_path}")
    for event in ("SessionStart", "PreToolUse"):
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise SystemExit(f"invalid {event} hook groups in {config_path}")
        command = hook(event)["hooks"][0]["command"]
        if not any(
            any(item.get("type") == "command" and item.get("command") == command for item in group.get("hooks", []))
            for group in groups
            if isinstance(group, dict)
        ):
            groups.append(hook(event))
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"installed stable Codex hooks in {config_path}")


if __name__ == "__main__":
    main()
