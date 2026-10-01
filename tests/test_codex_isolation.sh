#!/usr/bin/env bash
# Shared projects; isolated host bootstrap and session facts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.n1/project/memory/T-1" "$TMP/project"
printf '%s\n' '{"models":{"developer":"sonnet"},"worktree":{"root":"shared-worktrees"}}' > "$HOME/.n1/project/config.json"
printf '%s\n' 'Shared ticket memory' > "$HOME/.n1/project/memory/T-1/overview.md"
printf '%s\n' 'Claude bootstrap sentinel' > "$HOME/.n1/preamble.sh"
before=$(sha256sum "$HOME/.n1/project/config.json" "$HOME/.n1/preamble.sh" "$HOME/.n1/project/memory/T-1/overview.md")
git -C "$TMP/project" init -q
git -C "$TMP/project" remote add origin https://example.test/project.git
cd "$TMP/project"
unset N1_HOME N1_STATE_DIR N1_HOST_FILE N1_PLUGIN_ROOT CODEX_PLUGIN_ROOT
export CLAUDE_PLUGIN_ROOT=/stale PLUGIN_ROOT=/stale N1_ROOT=/stale CODEX_THREAD_ID=thread
source "$ROOT/lib/preamble.sh"
[ "$N1_ROOT" = "$ROOT" ]
[ "$N1_HOME" = "$HOME/.n1/project" ]
[ "$(n1_config_file)" = "$HOME/.n1/project/config.json" ]
[ "$(n1_worktree_root)" = shared-worktrees ]
[ "$(n1_session_file)" = "$HOME/.n1-codex/sessions/thread.json" ]
[ "$(n1_host_file)" = "$HOME/.n1-codex/host.json" ]
[ -z "$(n1_resolve_model developer)" ]
[ "$(sha256sum "$HOME/.n1/project/config.json" "$HOME/.n1/preamble.sh" "$HOME/.n1/project/memory/T-1/overview.md")" = "$before" ]
export N1_HOME="$TMP/custom-project"
[ "$(n1_home)" = "$TMP/custom-project" ]
export N1_STATE_DIR="$TMP/custom-state"
[ "$(n1_session_file)" = "$TMP/custom-state/sessions/thread.json" ]
echo 'PASS: shared N1 config and memory; isolated Codex state'
