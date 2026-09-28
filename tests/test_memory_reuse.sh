#!/usr/bin/env bash
# tests/test_memory_reuse.sh — ticket-ID reuse guard (NP-235)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert_eq() { if [ "$2" = "$3" ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; echo "--- expected"; echo "$2"; echo "--- actual"; echo "$3"; FAIL=$((FAIL+1)); fi; }
source "$REPO_ROOT/lib/memory.sh"
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

echo; echo "Passed: $PASS  Failed: $FAIL"; [ "$FAIL" -eq 0 ]
