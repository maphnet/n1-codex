#!/usr/bin/env bash
# Explicit queue intake and preview preserve ordering and blocker reasons.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0

check() { # <label> <extended-regex> <file>
    if grep -qE "$2" "$3" 2>/dev/null; then echo "PASS: $1"; else echo "FAIL: $1"; FAIL=1; fi
}

check "intake.md preserves explicit tickets and lookup failures" \
    'Preserve every ticket, order, known blockers and lookup failure' \
    skills/n1-queue/steps/intake.md
check "intake.md keeps blocked rows for later recheck" \
    'Preserve blocked rows and recheck them later' \
    skills/n1-queue/steps/intake.md
check "preview.md reports explicit tickets and eligibility reasons" \
    'every explicit ticket in input order, with blocker proof and eligibility reasons' \
    skills/n1-queue/steps/preview.md

exit $FAIL
