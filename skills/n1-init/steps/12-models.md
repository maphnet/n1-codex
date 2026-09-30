<!-- Purpose: Configure per-agent model overrides (only when user explicitly requests customization). -->

## Agent Model Configuration

Use default models from agent frontmatter. **Do NOT ask** about model customization unless the user explicitly requested it when invoking n1-init.

If the user requested customization, derive the defaults table by reading the `model:` field from each agent's frontmatter in `<N1_ROOT>/agents/*.md`, display it, and accept per-agent overrides (valid values: opus, sonnet, haiku) — only store overrides that differ from the frontmatter default.

To read an agent's default model from frontmatter:
```bash
source ~/.n1/preamble.sh
def=$(awk 'NR==1&&/^---$/{x=1;next} x&&/^---$/{exit} x&&/^model:/{sub(/^model:[ \t]*/,"");gsub(/\r/,"");print;exit}' "$N1_ROOT/agents/<name>.md")
```

Store overrides as plain strings:

```bash
source ~/.n1/preamble.sh
CFG="$N1_HOME/config.json"
# for each "<persona>=<model>" the user entered:
jq --arg p "<persona>" --arg m "<model>" '.models[$p] = $m' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
```

### On reconfiguration (n1-init re-run):

**`--related` flag:** When invoked as `n1-init --related`, skip all other configuration steps and run only the Related Projects Configuration section below. Read the existing config to preserve all other settings.

Ensure `repoPath` is present and current:
```bash
source ~/.n1/preamble.sh
CFG="$N1_HOME/config.json"
COMMON=$(git rev-parse --git-common-dir); case "$COMMON" in .git) REPO_PATH=$(git rev-parse --show-toplevel) ;; *) REPO_PATH=$(dirname "$COMMON") ;; esac
CUR=$(jq -r '.repoPath // empty' "$CFG")
if [ "$CUR" != "$REPO_PATH" ]; then
  jq --arg p "$REPO_PATH" '.repoPath = $p' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
  echo "repoPath set to $REPO_PATH"
fi
```

Prune every `models.<agent>` entry whose value equals the agent's frontmatter default, then print what was pruned. This is idempotent — running it multiple times has no additional effect. Legacy host-keyed objects (`{"claude-code":"opus"}`) are first collapsed to their `claude-code` string (read the same way `_n1_model_override` in `lib/config.sh` reads them); any entry still not a plain string after that is dropped.

```bash
source ~/.n1/preamble.sh
CFG="$N1_HOME/config.json"
jq '.models |= with_entries(.value |= (if type=="object" then (.["claude-code"] // empty) else . end)) | .models |= with_entries(select(.value|type=="string"))' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
for f in "$N1_ROOT"/agents/*.md; do a=$(basename "$f" .md)
  def=$(awk 'NR==1&&/^---$/{x=1;next} x&&/^---$/{exit} x&&/^model:/{sub(/^model:[ \t]*/,"");gsub(/\r/,"");print;exit}' "$f")
  cur=$(jq -r ".models[\"$a\"] // empty" "$CFG")
  if [ -n "$cur" ] && [ "$cur" = "$def" ]; then
    jq "del(.models[\"$a\"])" "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
    echo "pruned models.$a=$cur (equals frontmatter default)"
  fi
done
```
