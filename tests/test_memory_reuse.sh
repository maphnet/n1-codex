#!/usr/bin/env bash
# tests/test_memory_reuse.sh — ticket-ID reuse guard (NP-235)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert_eq() { if [ "$2" = "$3" ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; echo "--- expected"; echo "$2"; echo "--- actual"; echo "$3"; FAIL=$((FAIL+1)); fi; }
source "$REPO_ROOT/lib/memory.sh"
source "$REPO_ROOT/lib/frontmatter.sh"

# TQ-1: fail loudly if the functions under test are missing, rather than
# silently passing every "" assertion below.
type n1_memory_reuse_check >/dev/null 2>&1 || { echo "FAIL: n1_memory_reuse_check is not defined"; exit 1; }
type n1_archive_stale_branch >/dev/null 2>&1 || { echo "FAIL: n1_archive_stale_branch is not defined"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M="$T/memory"; mkdir -p "$M"

# Excerpt of the real NP-235 ticket.md written by product-analyst.
TICKET='## Task: NP-235
**Title:** Archive ticket memory when ticket ID is reused with a different description

### Core Ask
If N1 moves to a different tracker, a new ticket may reuse a ticket ID already used by a previously completed ticket, but with an unrelated/different description. N1 should detect this mismatch and archive the stale memory instead of treating it as the same ticket'"'"'s continuation.'

# mk <id> <step> — memory dir with overview (given step) + the NP-235 ticket.md
mk() {
    local d="$M/$1"; mkdir -p "$d"
    printf -- '---\nstep: %s\n---\n\n# %s · Archive ticket memory when ticket ID is reused\n' "$2" "$1" > "$d/overview.md"
    printf '%s\n' "$TICKET" > "$d/ticket.md"
}

# 1. Real NP-235 pair: raw tracker summary (typos, not rewritten) vs its own ticket.md → related (8/9)
mk NP-235 done
assert_eq "raw NP-235 summary is related to its own ticket.md" "" \
    "$(n1_memory_reuse_check "$M/NP-235" "archive tickt memory if the same ticket bu with new ticket description")"
assert_eq "related memory left in place" "yes" "$([ -f "$M/NP-235/ticket.md" ] && echo yes || echo no)"

# 2. Boundary: exactly 0.6 containment (3/5) → related
assert_eq "containment 0.6 is related" "" "$(n1_memory_reuse_check "$M/NP-235" "archive memory ticket zebra yak")"

# 3. Unrelated title sharing generic words (3/8 = 0.375) → archived to <ID>-old, contents preserved
assert_eq "unrelated done memory archived to -old" "$M/NP-235-old" \
    "$(n1_memory_reuse_check "$M/NP-235" "Compact ticket memory files after the review step")"
assert_eq "original key freed" "no" "$([ -e "$M/NP-235" ] && echo yes || echo no)"
assert_eq "archived ticket.md content intact" "$TICKET" "$(cat "$M/NP-235-old/ticket.md")"

# 4. Collision: -old taken → -old-2, existing -old untouched
mk NP-300 done
mkdir -p "$M/NP-300-old"; echo keep > "$M/NP-300-old/marker"
assert_eq "second reuse archives to -old-2" "$M/NP-300-old-2" \
    "$(n1_memory_reuse_check "$M/NP-300" "Add CSV export for user reports")"
assert_eq "existing -old never overwritten" "keep" "$(cat "$M/NP-300-old/marker")"

# 5. step gate: in-progress memory with an unrelated title is never archived
mk NP-301 implementation
assert_eq "non-done memory not archived" "" "$(n1_memory_reuse_check "$M/NP-301" "Add CSV export for user reports")"
assert_eq "non-done memory left in place" "yes" "$([ -d "$M/NP-301" ] && echo yes || echo no)"

# 6. Fail open: fresh title with no words of length >= 3
mk NP-302 done
assert_eq "empty fresh word set is related" "" "$(n1_memory_reuse_check "$M/NP-302" "a b")"
assert_eq "empty fresh title is related" "" "$(n1_memory_reuse_check "$M/NP-302" "")"

# 7. Legacy dir without ticket.md → overview H1 fallback
mkdir -p "$M/OLD-1"
printf -- '---\nstep: done\n---\n\n# OLD-1 · Export invoices to CSV\n' > "$M/OLD-1/overview.md"
assert_eq "legacy H1 same title related" "" "$(n1_memory_reuse_check "$M/OLD-1" "Export invoices to CSV")"
assert_eq "legacy H1 different title archived" "$M/OLD-1-old" \
    "$(n1_memory_reuse_check "$M/OLD-1" "Archive stale ticket memory")"

# 8. No overview.md → nothing to check
mkdir -p "$M/NP-303"
assert_eq "missing overview is skipped" "" "$(n1_memory_reuse_check "$M/NP-303" "Add CSV export")"

# 9. Cap: -old .. -old-50 all taken → nothing printed, memory untouched, exit 0
mk CAP-1 done
mkdir -p "$M/CAP-1-old"; for i in $(seq 2 50); do mkdir -p "$M/CAP-1-old-$i"; done
set +e
OUT=$(n1_memory_reuse_check "$M/CAP-1" "Add CSV export for user reports" 2>/dev/null); RC=$?
set -e
assert_eq "cap exhausted exits 0 and prints nothing" "0:" "$RC:$OUT"
assert_eq "cap exhausted leaves memory untouched" "yes" "$([ -f "$M/CAP-1/ticket.md" ] && echo yes || echo no)"

# 10. Trailing slash on memory_dir arg: dir is stripped so target is "<id>-old", not "<id>/-old"
mk NP-304 done
assert_eq "trailing-slash arg archives to sibling -old, not nested" "$M/NP-304-old" \
    "$(n1_memory_reuse_check "$M/NP-304/" "Compact ticket memory files after the review step")"
assert_eq "no nested -old dir created under the stripped path" "no" \
    "$([ -e "$M/NP-304/-old" ] && echo yes || echo no)"

# 11. CRLF overview.md ("step: done\r") still parses as done via n1_read_frontmatter's \r strip
mkdir -p "$M/NP-305"
printf -- '---\r\nstep: done\r\n---\r\n\r\n# NP-305 . Export invoices to CSV\r\n' > "$M/NP-305/overview.md"
assert_eq "CRLF step:done archives on unrelated title" "$M/NP-305-old" \
    "$(n1_memory_reuse_check "$M/NP-305" "Compact ticket memory files after the review step")"

# 12. Fresh title with quotes/$(...)/backticks is treated as inert data, never executed
mk NP-306 done
MARKER="$T/pwned"
assert_eq "shell-metacharacter title archives (unrelated words) without executing" "$M/NP-306-old" \
    "$(n1_memory_reuse_check "$M/NP-306" 'archive tickt memory bu $(touch '"$MARKER"') `touch '"$MARKER"'` "quoted"')"
assert_eq "no side-effect file created" "no" "$([ -e "$MARKER" ] && echo yes || echo no)"

# 13. CR-2: n1_write_frontmatter tolerates a CRLF overview (delimiters have \r) and the
# written key round-trips through n1_read_frontmatter (which already strips \r).
printf -- '---\r\nstep: implementation\r\n---\r\n\r\n# CRLF title\r\n' > "$T/crlf.md"
n1_write_frontmatter "$T/crlf.md" step done >/dev/null
assert_eq "CRLF write_frontmatter updates key" "done" "$(n1_read_frontmatter "$T/crlf.md" step)"

# --- CR-1: n1_archive_stale_branch ---
GIT_REPO="$T/repo"; mkdir -p "$GIT_REPO"
git -c user.name=t -c user.email=t@t.t init -q "$GIT_REPO"
(cd "$GIT_REPO" && git -c user.name=t -c user.email=t@t.t commit -q --allow-empty -m init)
git -C "$GIT_REPO" branch -M main >/dev/null 2>&1 || true

# 14. Plain branch, no worktree → renamed to <b>-old
git -C "$GIT_REPO" branch np-235 main
OUT=$(cd "$GIT_REPO" && n1_archive_stale_branch np-235 -old)
assert_eq "plain branch renamed" "np-235-old" "$OUT"
assert_eq "old branch name gone" "no" "$(git -C "$GIT_REPO" branch --list np-235 | grep -q . && echo yes || echo no)"
assert_eq "new branch name exists" "yes" "$(git -C "$GIT_REPO" branch --list np-235-old | grep -q . && echo yes || echo no)"

# 15. Branch with a worktree checked out → worktree moved + branch renamed
git -C "$GIT_REPO" branch np-236 main
WT="$T/wt-np-236"
git -C "$GIT_REPO" worktree add -q "$WT" np-236
OUT=$(cd "$GIT_REPO" && n1_archive_stale_branch np-236 -old)
assert_eq "branch+worktree renamed" "np-236-old" "$OUT"
assert_eq "worktree moved" "yes" "$([ -d "${WT}-old" ] && echo yes || echo no)"
assert_eq "old worktree path gone" "no" "$([ -d "$WT" ] && echo yes || echo no)"

# 16. Target branch name already taken → returns 1, leaves original branch intact
git -C "$GIT_REPO" branch np-237 main
git -C "$GIT_REPO" branch np-237-old main
set +e
OUT=$(cd "$GIT_REPO" && n1_archive_stale_branch np-237 -old 2>/dev/null); RC=$?
set -e
assert_eq "existing target branch fails" "1:" "$RC:$OUT"
assert_eq "original branch untouched" "yes" "$(git -C "$GIT_REPO" branch --list np-237 | grep -q . && echo yes || echo no)"

# 17. No branch, no worktree → no-op, returns 0, prints nothing
OUT=$(cd "$GIT_REPO" && n1_archive_stale_branch np-999-does-not-exist -old)
assert_eq "no-op prints nothing" "" "$OUT"

echo; echo "Passed: $PASS  Failed: $FAIL"; [ "$FAIL" -eq 0 ]
