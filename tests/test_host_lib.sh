#!/usr/bin/env bash
# lib/host.sh: Claude Code is the only host (N1-63).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/lib/host.sh"
PASS=0; FAIL=0
eq()    { if [ "$2" = "$3" ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1 (expected '$2', got '$3')"; FAIL=$((FAIL+1)); fi; }
has()   { case "$3" in *"$2"*) echo "PASS: $1"; PASS=$((PASS+1));; *) echo "FAIL: $1 (missing '$2' in: $3)"; FAIL=$((FAIL+1));; esac; }
lacks() { case "$3" in *"$2"*) echo "FAIL: $1 (unexpected '$2' in: $3)"; FAIL=$((FAIL+1));; *) echo "PASS: $1"; PASS=$((PASS+1));; esac; }

eq "host: constant in an empty env" claude-code "$(env -i PATH="$PATH" bash -c "source '$REPO_ROOT/lib/host.sh'; n1_host")"
eq "host: ignores stale N1_HOST/CODEX_THREAD_ID" claude-code "$(N1_HOST=codex CODEX_THREAD_ID=x n1_host)"
eq "session id: N1_SESSION_ID wins" abc "$(N1_SESSION_ID=abc CLAUDE_CODE_SESSION_ID=def n1_session_id)"
eq "session id: CLAUDE_CODE_SESSION_ID fallback" def "$(unset N1_SESSION_ID; CLAUDE_CODE_SESSION_ID=def n1_session_id)"
eq "session id: CODEX_THREAD_ID ignored" "" "$(unset N1_SESSION_ID CLAUDE_CODE_SESSION_ID; CODEX_THREAD_ID=x n1_session_id)"
eq "worktree root: default" .claude/worktrees "$(n1_worktree_root)"
eq "agent type" n1:developer "$(n1_agent_type developer)"
eq "persona name: n1: stripped" developer "$(n1_persona_name n1:developer)"
eq "persona name: n1- is not a persona" "" "$(n1_persona_name n1-developer)"
eq "plugin version: Claude Code manifest" "$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")" "$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT" n1_plugin_version)"

cmd=$(N1_SESSION_ID=parent n1_headless_cmd n1-start T-1 sonnet /tmp/out /repo high)
has   "headless: claude -p transport" "claude -p " "$cmd"
has   "headless: model" "--model sonnet" "$cmd"
has   "headless: effort" "--effort high" "$cmd"
has   "headless: repo cd" "cd /repo && " "$cmd"
has   "headless: parent linkage" "N1_PARENT_SESSION_ID=parent" "$cmd"
has   "headless: closed stdin + log" "< /dev/null > /tmp/out 2>&1" "$cmd"
lacks "headless: no N1_HOST export" "N1_HOST" "$cmd"
lacks "headless: no codex" "codex" "$cmd"

echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
