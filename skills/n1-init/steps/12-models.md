<!-- Purpose: Configure explicit Codex overrides while preserving shared host settings. -->

## Agent Model Configuration

Every Codex persona inherits the current session model by default. **Do NOT ask** about model customization unless the user explicitly requested it. An empty resolved model means omit the spawn model argument; never pass an empty string as a model name.

If customization was requested, accept model identifiers supported by the installed Codex runtime and store only explicit overrides at `models.<persona>.codex`. Shared plain-string Claude values and other host keys are preserved and ignored by Codex.

```bash
source ~/.n1-codex/preamble.sh
CFG="$N1_HOME/config.json"
# For an explicitly requested <persona>=<model>; retain the legacy Claude string.
jq --arg p "<persona>" --arg m "<model>" '
  .models[$p] |= (if type == "string" then {"claude-code": .} else (. // {}) end)
  | .models[$p].codex = $m
' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
```

On reconfiguration, preserve the entire `models` object. Do not collapse host-keyed objects, prune Claude defaults, or discard unknown host keys. To restore inheritance for a persona, remove only its `codex` key after the user requests that change. Regenerate the project-scoped profiles with `python3 "$N1_ROOT/scripts/install-agents.py" "$PROJECT_ROOT"` and tell the user to restart Codex.
