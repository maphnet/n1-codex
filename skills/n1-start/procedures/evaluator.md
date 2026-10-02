# Procedure: Acceptance-Criteria Evaluator

Run before PR preparation, again after documentation edits, and immediately before
each push/PR creation (including after rebase). Standalone `n1-pr` uses the same
procedure. This gate is independent of `localTesting.enabled` and testing mode.

## Resolve gate

```bash
source ~/.n1-codex/preamble.sh
EVALUATOR_ENABLED=$(n1_config_val '.localTesting.evaluatorGate')
EVALUATOR_ENABLED=${EVALUATOR_ENABLED:-false}
EVALUATOR_AUTONOMY=$(n1_config_val '.autonomy.mode')
EVALUATOR_AUTONOMY=${EVALUATOR_AUTONOMY:-hands-off}
[ "${N1_AUTONOMY_PRESET:-}" = autonomous ] && EVALUATOR_AUTONOMY=hands-off
EVALUATOR_PENDING=$(n1_read_frontmatter "$N1_HOME/memory/$ID/overview.md" evaluator_pending)
EVALUATOR_RUN=false
if [ "$EVALUATOR_ENABLED" = true ] && { [ "$EVALUATOR_AUTONOMY" = hands-off ] || [ "${N1_HEADLESS:-}" = 1 ] || [ "$EVALUATOR_PENDING" = true ]; }; then
    EVALUATOR_RUN=true
fi
```

Only `true`/`false` are valid flag values; otherwise block for configuration repair.
`false`: skip. `true`: follow EVALUATOR_RUN. Pending failures remain gated on
interactive resume; only interactive runs without a pending evaluator skip.
Record the gate decision and skip reason in overview; an old evaluator result must
not appear as the current result when the gate skips. Do not alter project config
to bypass a failed gate. Missing ticket ID, memory, AC or branch-point blocks an
enabled gate; obtain the ticket/AC rather than inferring success.

## Evaluate current inputs

Before evaluating or blocking, persist `evaluator_pending: true` in overview. Clear
it only after validated PASS/SKIP or a current explicit waiver. An unresolved
evaluator escalation is pending even if an older overview lacks this key; validate
it before applying the interactive skip. Never clear pending merely by resuming.

Set `MEM=$N1_HOME/memory/$ID`, `WORKTREE_PATH` to the Git toplevel, and `BASE_REF`
from `MEM/branch-point`. Standalone without that file: compute the configured
default branch's merge-base with HEAD and persist it to branch-point. Capture inputs:

```bash
source ~/.n1-codex/preamble.sh
MEM="$N1_HOME/memory/$ID"
WORKTREE_PATH=$(git rev-parse --show-toplevel)
BASE_REF=$(cat "$MEM/branch-point")
python3 "$N1_ROOT/scripts/evaluator.py" snapshot --workspace "$WORKTREE_PATH" --memory "$MEM" --base "$BASE_REF" > "$MEM/evaluator-input.json"
```

Nonzero: block. The snapshot supplies exact IDs/text for original ticket and
additional brainstorm criteria, plus a fingerprint of source and verification
inputs. Lists, prose and nested headings within the AC section are criteria; section
labels can SKIP with reasons. Never substitute/drop original AC. Read the diff against `BASE_REF`,
including staged, unstaged and untracked changes; ignored runtime state is excluded.
Read existing QA/local-testing evidence; no live test evidence is implied by a skip.

On resume or repeated entry, validate existing `evaluator.md` first using the check
below. Reuse only a current, complete PASS/SKIP or explicitly waived FAIL. Missing,
malformed or stale output requires a fresh evaluator; persistent errors block.

Resolve `n1_resolve_agent solution-architect evaluator`, preserve the tab-separated
model/effort pair, omit empty overrides. Dispatch solution-architect in **evaluator
mode** with ticket.md, brainstorm.md if present, evaluator-input.json, current diff,
qa.md/local-testing.md if present, absolute workspace, and output `MEM/evaluator.md`.
Write ownership is only evaluator.md; no source edits. Wait for actual completion.

```bash
source ~/.n1-codex/preamble.sh
MEM="$N1_HOME/memory/$ID"
WORKTREE_PATH=$(git rev-parse --show-toplevel)
BASE_REF=$(cat "$MEM/branch-point")
python3 "$N1_ROOT/scripts/evaluator.py" check --workspace "$WORKTREE_PATH" --memory "$MEM" --base "$BASE_REF"
```

Exit 0 allows progression. Exit 1 is FAIL; exit 2 is missing/malformed/stale inputs.
Do not trust a returned PASS without checking the persisted artifact. Record verdict,
fingerprint and counts in overview **after** validation; `step: evaluator` marks
completion. Telemetry step 18 (`evaluator`) records pass/fail/skip, not token usage.
Changed source, AC, QA or local-testing inputs invalidate both verdict and waiver.
If documentation/rebase changes invalidate it, reevaluate and regenerate only PR
content (tech-writer Phase 2, no source edits) before publication.

## Block and resolve

FAIL: show failed items and evidence/reasons. Block push and PR creation. Ask for
fix/retry (Recommended), stop, or an explicit waiver with a reason. A generic request
to continue, hands-off auto-accept, and time pressure never authorize a waiver.
Malformed/stale results cannot be waived; repair/retry the evaluator first.

User waiver: retain FAIL in evaluator.md. Record the user's reason and current
fingerprint as `evaluator_waiver_reason`/`evaluator_waiver_fingerprint` in overview,
plus a `[asked]` Decision Ledger row. Check again with `--waiver-fingerprint` and
`--waiver-reason` using these exact values as quoted arguments; exit 0 is required.
Never generate waiver values autonomously. PR content includes failed items and reason.

**Headless:** no automatic waiver and no question/continuation. Execute the
escalate-and-exit path in `autonomy-headless.md § Headless Guard` (mandatory blocked
tracker move where configured, durable escalation, `step: escalated`, failed
telemetry, clear active-run, end run), regardless of qualityEscalations/stop-list.
Interactive resume from escalation starts here, retains findings and requires a
current validation before reaching PR. Fixes return through relevant QA/review.

All non-verifiable items: evaluator records SKIP per item with specific reasons;
overall SKIP is graceful, persisted and included in PR. Docs/config changes are
verifiable when observable or checkable; filename classification cannot skip them.
