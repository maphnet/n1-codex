#!/usr/bin/env bash
# tests/test_local_testing_config.sh
# NP-222: local-testing mode resolution precedence and worktree.copyFiles copy rules.
# Run: bash tests/test_local_testing_config.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 -- expected '$2', got '$3'"; FAIL=$((FAIL + 1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"; else fail "$label" "$expected" "$actual"; fi
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export N1_HOME="$T/home"
mkdir -p "$N1_HOME"
cfg() { printf '%s\n' "$1" > "$N1_HOME/config.json"; }

# ---- Mode resolution ----
REPO="$T/repo"; mkdir -p "$REPO"
mode() { n1_resolve_local_testing_mode "$REPO"; }

cfg '{}'
assert_eq "M1: empty config, no compose -> test" "test" "$(mode)"
touch "$REPO/compose.yml"
assert_eq "M2: compose present, autoLive absent -> test (default false)" "test" "$(mode)"
cfg '{"localTesting":{"autoLive":false}}'
assert_eq "M3: explicit autoLive false + compose -> test" "test" "$(mode)"
cfg '{"localTesting":{"autoLive":true}}'
assert_eq "M4: autoLive true + compose.yml -> live" "live" "$(mode)"
cfg '{"localTesting":{"autoLive":true,"mode":"test"}}'
assert_eq "M5: explicit mode wins over autoLive" "test" "$(mode)"
cfg '{"localTesting":{"mode":"smoke"}}'
assert_eq "M6: explicit smoke passes through" "smoke" "$(mode)"
rm "$REPO/compose.yml"
cfg '{"localTesting":{"autoLive":true}}'
assert_eq "M7: autoLive true, no compose -> test" "test" "$(mode)"
touch "$REPO/docker-compose.yaml"
assert_eq "M8: autoLive true + docker-compose.yaml -> live" "live" "$(mode)"
rm "$REPO/docker-compose.yaml"
cfg '{"localTesting":{"startCommand":"npm run dev"}}'
assert_eq "M9: startCommand still infers live (unchanged)" "live" "$(mode)"

# ---- worktree.copyFiles ----
SRC="$T/a/src"; WT="$T/b/wt"
mkdir -p "$SRC/nested" "$WT"
git -C "$WT" init -q
printf '.env\n.env.local\n' > "$WT/.gitignore"
echo secret > "$SRC/.env"
echo local > "$SRC/nested/.env.local"
echo plain > "$SRC/notignored.txt"
echo out > "$T/a/escape"
echo abs > "$T/a/abs.env"
cfg "{\"worktree\":{\"copyFiles\":[\".env\",\"nested/.env.local\",\"missing.env\",\"notignored.txt\",\"../escape\",\"$T/a/abs.env\"]}}"

assert_eq "C1: copies only present, ignored, safe entries" "2" "$(n1_copy_worktree_files "$SRC" "$WT" 2>/dev/null)"
assert_eq "C2: .env content copied" "secret" "$(cat "$WT/.env")"
assert_eq "C3: nested entry copied" "local" "$(cat "$WT/nested/.env.local")"
assert_eq "C4: non-ignored file skipped" "no" "$([ -e "$WT/notignored.txt" ] && echo yes || echo no)"
assert_eq "C5: '..' and absolute entries rejected explicitly" "2" "$(n1_copy_worktree_files "$SRC" "$WT" 2>&1 >/dev/null | grep -c 'rejected')"
assert_eq "C6: nothing written outside the worktree" "no" "$([ -e "$T/b/escape" ] || [ -e "$WT$T" ] && echo yes || echo no)"
echo changed > "$SRC/.env"
assert_eq "C7: re-run copies nothing (missing-only)" "0" "$(n1_copy_worktree_files "$SRC" "$WT" 2>/dev/null)"
assert_eq "C8: existing destination not overwritten" "secret" "$(cat "$WT/.env")"
assert_eq "C9: copied files invisible to git (never committed)" "?? .gitignore" "$(git -C "$WT" status --porcelain)"
cfg '{}'
assert_eq "C10: no copyFiles key -> 0" "0" "$(n1_copy_worktree_files "$SRC" "$WT")"

echo; echo "Passed: $PASS  Failed: $FAIL"; [ "$FAIL" -eq 0 ]
