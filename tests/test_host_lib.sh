#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/host.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
check() { [ "$2" = "$3" ] || { echo "FAIL: $1 expected '$2', got '$3'" >&2; exit 1; }; }
check host codex "$(N1_HOST=claude-code n1_host)"
check internal internal "$(N1_SESSION_ID=internal CODEX_THREAD_ID=native n1_session_id)"
check native native "$(unset N1_SESSION_ID; CODEX_THREAD_ID=native n1_session_id)"
check no-claude "" "$(unset N1_SESSION_ID CODEX_THREAD_ID; CLAUDE_CODE_SESSION_ID=stale n1_session_id)"
check state "$HOME/.n1-codex/sessions/thread.json" "$(unset N1_STATE_DIR; N1_SESSION_ID=thread n1_session_file)"
if N1_SESSION_ID='../bad' n1_session_file; then exit 1; fi
check root "$ROOT" "$(unset CODEX_PLUGIN_ROOT N1_PLUGIN_ROOT; CLAUDE_PLUGIN_ROOT=/stale PLUGIN_ROOT=/stale n1_plugin_root)"
check default .codex/n1-worktrees "$(n1_worktree_root)"
n1_config_val() { printf 'custom/'; }
check configured custom "$(n1_worktree_root)"
unset -f n1_config_val
for fn in n1_bg_cmd n1_bg_launch_cmd; do
    if "$fn" agents 2>"$TMP/error"; then exit 1; fi
    [[ "$( < "$TMP/error")" = *unsupported* ]]
done
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" > "$N1_TEST_CAPTURE"' 'printf "%s\n" "${CODEX_THREAD_ID-unset}|${N1_SESSION_ID-unset}|${N1_PARENT_SESSION_ID-}" >> "$N1_TEST_CAPTURE"' > "$TMP/codex"
chmod +x "$TMP/codex"
export PATH="$TMP:$PATH"
export N1_TEST_CAPTURE="$TMP/argv"
printf 'Brief with "quotes" and $literal\n' > "$TMP/brief"
cmd=$(N1_SESSION_ID=parent CODEX_THREAD_ID=old n1_headless_cmd n1-start 'T-1; $(false)' gpt-6.1-sol "$TMP/out log" "$TMP" high "$TMP/brief")
bash -c "$cmd"
mapfile -t argv < "$TMP/argv"
check exec exec "${argv[0]}"
check json --json "${argv[1]}"
check model --model "${argv[2]}"
check model-value gpt-6.1-sol "${argv[3]}"
check config -c "${argv[4]}"
check effort 'model_reasoning_effort="high"' "${argv[5]}"
check separator -- "${argv[6]}"
check prompt '$n1-start T-1; $(false)' "${argv[7]}"
check brief 'Brief with "quotes" and $literal' "${argv[8]}"
check child-identity 'unset|unset|parent' "${argv[9]}"
[[ "$cmd" != *bypass* && "$cmd" != *permission-mode* ]]
if n1_headless_cmd n1-start T-1 '' "$TMP/log" '' 'high";x' >/dev/null 2>&1; then exit 1; fi
echo 'PASS: Codex host and transport'
