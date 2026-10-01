#!/usr/bin/env bash
# Codex preamble source chain and isolated generated bootstrap.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.n1/shared/memory/T-1" "$TMP/bin"
export N1_HOME="$HOME/.n1/shared"
printf '%s\n' '{}' > "$N1_HOME/config.json"
printf '%s\n' 'Claude bootstrap sentinel' > "$HOME/.n1/preamble.sh"
unset N1_SESSION_ID CODEX_THREAD_ID N1_STATE_DIR N1_HOST_FILE CODEX_PLUGIN_ROOT N1_PLUGIN_ROOT
check() { [ "$2" = "$3" ] || { echo "FAIL: $1 expected '$2', got '$3'" >&2; exit 1; }; }
# Direct sourcing uses this fork, never stale Claude environment or global facts.
export CLAUDE_PLUGIN_ROOT=/stale PLUGIN_ROOT=/stale N1_ROOT=/stale
source "$ROOT/lib/preamble.sh"
check source-root "$ROOT" "$N1_ROOT"
check shared-home "$HOME/.n1/shared" "$N1_HOME"
type n1_step_begin >/dev/null
type n1_verify_dependencies >/dev/null
check persona n1-code-reviewer "$(n1_agent_type code-reviewer)"
check persona-roundtrip code-reviewer "$(n1_persona_name "$(n1_agent_type code-reviewer)")"
check foreign-persona "" "$(n1_persona_name n1:code-reviewer)"
for effort in max ultra; do
    printf '{"models":{"developer":{"codex":{"effort":"%s"}}}}\n' "$effort" > "$N1_HOME/config.json"
    check "effort-$effort" "$(printf '\t%s' "$effort")" "$(n1_resolve_agent developer)"
    cmd=$(n1_headless_cmd n1-start T-1 '' "$TMP/log" '' "$effort")
    [[ "$cmd" = *model_reasoning_effort*"$effort"* ]]
done
printf '%s\n' '{}' > "$N1_HOME/config.json"
# Native env wins, an explicit alternate root is supported without Claude fallback.
ALT="$TMP/alternate root"; mkdir -p "$ALT/lib"
printf '%s\n' 'N1_ALT_LOADED=1' > "$ALT/lib/preamble.sh"
check native-plugin "$ALT" "$(CODEX_PLUGIN_ROOT="$ALT" n1_plugin_root)"
check explicit-plugin "$ALT" "$(unset CODEX_PLUGIN_ROOT; N1_PLUGIN_ROOT="$ALT" n1_plugin_root)"
# Clean-shell bootstrap needs no Python and never overwrites Claude's shim.
for c in bash cat mkdir mv rm dirname basename grep sed git jq head tr awk date find; do
    p=$(command -v "$c") && ln -s "$p" "$TMP/bin/$c"
done
printf '%s\n' '{"session_id":"s-clean","source":"startup"}' | env -i HOME="$HOME" PATH="$TMP/bin" N1_HOME="$N1_HOME" CODEX_PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/session-start.sh" >/dev/null
resolved=$(env -i HOME="$HOME" PATH="$TMP/bin" N1_HOME="$N1_HOME" CODEX_THREAD_ID=s-clean bash -c 'source ~/.n1-codex/preamble.sh && type n1_step_begin >/dev/null && printf "%s|%s" "$N1_ROOT" "$N1_HOME"')
check clean-shell "$ROOT|$N1_HOME" "$resolved"
check claude-shim 'Claude bootstrap sentinel' "$(< "$HOME/.n1/preamble.sh")"
check codex-facts codex "$(jq -r .host "$HOME/.n1-codex/sessions/s-clean.json")"
echo 'PASS: Codex preamble, persona identity, extended effort, clean-shell bootstrap'
