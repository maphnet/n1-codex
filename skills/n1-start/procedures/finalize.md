# Procedure: Finalize Memory

## Finalize Memory (Step 12)

Update overview.md with only completed steps checked; preserve uncompleted checkboxes and `## Pending` for an open PR, including skipped, failed, or escalated finish. Set `step: done` and remove Pending only after a confirmed merge; otherwise retain the last completed step and resume evidence. Add `docs_updated` if appropriate. Persist frontmatter `ci_state`, `finish_state`, `finish_reason`, and `final_outcome`, and a truthful final status line.

Determine `final_outcome` from evidence: `merged` only after confirmed merge, `pr_skipped` when PR creation was intentionally skipped, `failed` or `escalated` when the run failed or requires intervention, otherwise `pr_created` for an open PR, including an intentionally skipped finish. An asynchronous or still-open merge is never `merged`.

**Telemetry (if enabled):**
```bash
source ~/.n1-codex/preamble.sh
source "$N1_ROOT/lib/telemetry.sh"
RESOLVED_TYPE=$(n1_read_frontmatter "$N1_HOME/memory/$ID/overview.md" "type" 2>/dev/null || true)
TELEMETRY_DIR=$(n1_telemetry_dir "$ID")
n1_close_run_telemetry "$TELEMETRY_DIR" "$N1_RUN_ID" "$N1_VERSION" "$ID" "$FINAL_OUTCOME" "$CI_STATE" "$FINISH_STATE" "$FINISH_REASON" "$ESTIMATED_TIER" "$RESOLVED_TYPE" || { echo "Telemetry close or verification failed; retain active run for retry" >&2; return; }
n1_remove_run_lock "$TELEMETRY_DIR" "$N1_RUN_ID"
```
Set these variables from the persisted fields before closing. `$ESTIMATED_TIER` is the estimation tier or empty. Serialize finalization for the run; do not append a second close on retry, even if the first close is already merged.

The helper recognizes an existing envelope_close in raw events and a completed record in the merged schema separately. It verifies the run identity and all completion fields before removing the lock or clearing active state; conflicting merged evidence stops for investigation.

After the close is persisted and merged (or telemetry is disabled), clear active-run:
```bash
source ~/.n1-codex/preamble.sh
n1_active_run_clear
```

**Emit Gate 3** (`procedures/output-gates.md § Gate 3`). Sources:
1. `$N1_HOME/memory/$ID/implementation.md` — `## Implementation Summary`
2. `$N1_HOME/memory/$ID/qa.md` — verdict + Evidence (verbatim)
3. `$N1_HOME/memory/$ID/local-testing.md` — report (verbatim, or SKIPPED line)
4. `$N1_HOME/memory/$ID/overview.md` — `## Pending` for PR URL; frontmatter `ticket_url` for tracker link

Copy test commands and result lines verbatim. Every skipped step gets `SKIPPED — <reason>`. `Ticket:` omitted when `ticket_url` is empty. PR URL is Gate 3's final field (or `PR: SKIPPED` if skipped). Investigation tickets: use investigation-mode variant.
