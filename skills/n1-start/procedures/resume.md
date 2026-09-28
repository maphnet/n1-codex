# Procedure: Resume

## Post-Compaction Recovery

After compaction, session-start hook injects ORCHESTRATOR STATE into `additionalContext`.

**Must:**
1. Read ORCHESTRATOR STATE — authoritative over compacted summary.
2. Use those values (tracker type, MCP prefix, worktree, step routing, loop counters), not the compacted summary.
3. If `Task context:` non-empty: print **Gate 1** (resume variant, `procedures/output-gates.md § Gate 1`).
4. If missing: re-resolve N1_HOME:
   ```bash
   source ~/.n1/preamble.sh
   cat "$N1_HOME/config.json"
   ```

## Memory Check

Check if `$N1_HOME/memory/<input>/overview.md` exists.

**Exists:** read step from frontmatter.
```bash
source ~/.n1/preamble.sh
TYPE=$(n1_read_type "$N1_HOME/memory/$ID/overview.md")
```
**ID reuse check** — only if `<input>` is a tracker ticket ID, `step` is `done`, and `tracker.operations.readTicket` is set: fetch the ticket via `mcp__<tracker.mcp>__<readTicket>` (any error → skip this check entirely, continue resuming as today) and write its title to `$N1_HOME/memory/.fresh-title-$ID.txt` with the file-write mechanism (never through a shell string — a ticket title is untrusted tracker text, and interpolating it into a shell string executed here is command injection, NP-203 SEC-1). The scratch file is a sibling of `$N1_HOME/memory/$ID/`, not inside it, so an unrelated-title archive can't sweep it into `<ID>-old`. Then:
```bash
source ~/.n1/preamble.sh
source "$N1_ROOT/lib/memory.sh"
ARCHIVED=$(n1_memory_reuse_check "$N1_HOME/memory/$ID" "$(cat "$N1_HOME/memory/.fresh-title-$ID.txt")")
rm -f "$N1_HOME/memory/.fresh-title-$ID.txt"
```
Non-empty `ARCHIVED`: tell the user the reused ID's old memory moved to `$ARCHIVED`, then continue as **Not exists**.

Step `escalated` + non-headless: print `## Escalations`, move to `inProgress` (if `tracker.statuses.blocked` set), reset step per `procedures/autonomy-headless.md`.

```bash
source ~/.n1/preamble.sh
n1_busy_guard "$N1_HOME/memory/$ID/overview.md" "$ID"
```
Exit 3 (headless): STOP.

`TYPE=="investigation"`: skip workspace isolation; else run it. Read loop counters:
```bash
source ~/.n1/preamble.sh
n1_read_frontmatter "$N1_HOME/memory/$ID/overview.md" "qa_fix_cycle"
```
(Repeat for `tq_fix_cycle`, `review_fix_cycle`, `clean_passes`, `local_test_fix_cycle`, `ci_fix_cycle`.) Print Gate 1 (resume variant). Read `## Context`:
```bash
CONTEXT_SECTION=$(sed -n '/^## Context$/,/^## /{/^## Context$/d;/^## /d;p}' "$N1_HOME/memory/$ID/overview.md")
```
If empty: skip Gate 1. Else populate template from frontmatter and print.

**Not exists:** fresh start. Create `$N1_HOME/memory/<ID>/`.

## Loop-Counter Durability

Loop counters live in overview frontmatter (same keys as above). Increment in file as loop turns; read back on resume.

Overview is source of truth. Step writes output FIRST, then updates `step:`/checkbox LAST. Artifact writes are idempotent.

**Dependency integrity guard:**
```bash
source ~/.n1/preamble.sh
n1_verify_dependencies "$N1_HOME/memory/$ID" ticket.md analysis.md
```
Missing/empty → STOP and report.
