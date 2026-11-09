# Status, stop and resume

Require one explicit validated queue ID. Source the Codex preamble and queue helper. Never initialize a missing queue or infer the latest. All writes use revision-checked bounded helpers with file-written JSON; preserve state/evidence on errors.

## Status

`n1_queue_state status <queue-id>` is read-only. Report Run, ticket/queue statuses, exact active identities, blockers, last receipt and missing evidence. Do not query trackers, fetch Git, consume mail, release tags, stop workers, change state or launch anything.

## Stop

First persist `stop <queue-id> <revision> <json-file>` with `{"reason":"explicit user stop"}`. Durable stop intent prevents selection and external launch mutations even if cancellation fails.

Only state.stop.dispatch_id, independently verified as this queue's exact assignment, may receive `orca orchestration worker-stop --dispatch <dispatch-id> --json`. Unknown starts without a proven dispatch require reconciliation of the existing intent/receipt first; never guess or start again.

Record stop-result with matching dispatch_id, full receipt, verified and settled projections. Only a confirmed actual stopped result permits verified true/settled true. A fence, processAction saying a close was issued, stop_unknown, timeout or unverifiable liveness does not prove exit: record false, inspect worker-show per receipt recovery, and remain paused. Never blindly repeat stop, abandon, close terminals, remove workspaces or claim cancellation without proof. Without an active assignment, stop simply records stopped and prevents launches; do not call Orca.

## Resume

Read state and installed recovery guidance. Rebind an existing Run with `orca orchestration run-use --id <original-run-id> --json`; retain full receipt and verify the original identity. Never create another Run.

Reconcile active/uncertain assignment using persisted intent, receipts and exact dispatch/workspace/repo/ticket/branch. Unresolved mutations must be uniquely identified and recorded through receipt before resume. Obtain independent liveness/identity proof for existing workers; missing proof stays paused. Resolve questions/escalations/permission needs explicitly first.

Call `resume <queue-id> <revision> <json-file>` with reason and, for an existing Run, original run_id, full receipt and verified true. An existing worker additionally requires assignment with matching dispatch_id, workspace, canonical repo, branch and ticket, backed by native inspection: set active true for a live worker, or active false and settled true for a settled worker whose worker_done was already recorded in a wake. Resume the settled assignment to collect evidence, never to redispatch. Unknown start retains its intent and stays paused. A proven stopped ticket stays stopped and is never redispatched; remaining pending tickets may proceed. Only a selection reservation with no external mutation may be released safely.

Resume invalidates pending/blocked tracker proofs. Refresh tracker/base and provider evidence before selection/completion per intake.md/run.md. Never infer exit from elapsed time, abandon uncertainty, bypass evidence or redispatch. Continue the original Run according to receipt next/yield instructions.

## Report

Report each actual outcome, PR/head/check evidence, blockers and exact next action. Distinguish fixture tests from live end-to-end validation.

An integration queue reports each verified child merge separately, including the authorized integration ref, merge commit and refreshed tip. After every integration-tip change, reconcile one queue-level PR from that integration ref to the persisted default ref. Reuse it only when repository, head, base and current integration tip match; otherwise record a pending final-PR action for the coordinator. Leave this PR open for human review. A missing or uncertain create/update receipt pauses the queue action and never authorizes a default-branch merge, push, tag, release or deployment.

Workers never merge. The coordinator may merge only a verified child PR into the persisted integration ref; it never merges, pushes, tags, releases, deploys, or closes the final integration-to-default PR.
