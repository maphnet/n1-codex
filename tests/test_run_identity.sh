#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export N1_HOME="$T/project" N1_STATE_DIR="$T/state"
source "$ROOT/lib/telemetry.sh"

# n1_host is a constant and n1_worktree_root falls back to the default even
# with no host or plugin-root evidence in the env (NP-155/NP-228 regression).
RES=$(env -u N1_HOST -u CLAUDE_PLUGIN_ROOT bash -c "source '$ROOT/lib/host.sh'; n1_host; echo; n1_worktree_root")
test "$(printf '%s' "$RES" | sed -n '1p')" = "claude-code"
test "$(printf '%s' "$RES" | sed -n '2p')" = ".claude/worktrees"
echo 'PASS: constant host and default worktree root with no env evidence'

export N1_SESSION_ID=thread-a
ID=NP-A
n1_run_begin "$ID"
A="$N1_RUN_ID"
export N1_SESSION_ID=thread-b
ID=NP-B
n1_run_begin "$ID"
B="$N1_RUN_ID"
export N1_SESSION_ID=thread-a
unset N1_RUN_ID
n1_read_lock "$N1_HOME/memory"
test "$N1_LOCK_RUN_ID" = "$A"
export N1_SESSION_ID=thread-missing
if n1_read_lock "$N1_HOME/memory"; then echo 'foreign lock selected' >&2; exit 1; fi
export N1_SESSION_ID=thread-a
# Another session starting in the same ticket cannot steal this session's lock.
export N1_SESSION_ID=thread-c
n1_run_begin NP-A
export N1_SESSION_ID=thread-a
unset N1_RUN_ID
n1_read_lock "$N1_HOME/memory"
test "$N1_LOCK_RUN_ID" = "$A"
python3 - "$N1_HOME/memory/NP-A/telemetry/raw/steps/$A.jsonl" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1]).readline())
assert row['host'] == 'claude-code' and row['session_id'] == 'thread-a'
assert row['run_id'] and row['started_at']
PY
echo 'PASS: concurrent run/session isolation'
# Same-session overlapping runs require an explicit run, not latest-mtime.
n1_run_begin NP-A
SECOND="$N1_RUN_ID"
unset N1_RUN_ID
if n1_read_lock "$N1_HOME/memory"; then echo 'ambiguous same-session run selected' >&2; exit 1; fi
export N1_RUN_ID="$SECOND"
n1_read_lock "$N1_HOME/memory"
test "$N1_LOCK_RUN_ID" = "$SECOND"
echo 'PASS: ambiguous same-session run rejected'
