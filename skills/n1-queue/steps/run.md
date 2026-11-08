# Run

Load installed `orca skills get orchestration` and its coordinator-loop/recovery references once; inspect current command help. Use that executable consistently. Preserve full native JSON: queue identity projections below are not invented native receipt fields.

## Durable launch

Read `n1_queue_state status <queue-id>`. Paused/stopped queues follow report.md. Otherwise refresh proofs per intake.md and call `select <queue-id>`. In integration mode, selection fetches and pins the persisted `integration_ref`; a changed tip invalidates blocker proofs until refreshed. No selection means report reasons and yield. Selection already persists a reservation.

Before each external mutation call `intent <queue-id> <revision> <json-file>` with operation, ticket and unique request_id. After the external action call `receipt <queue-id> <revision> <json-file>` before another mutation. Failed intent persistence prohibits the action. Persist failed/ambiguous receipts with verified false and pause. Timeout never authorizes another start, Run, Task or workspace.

1. Without a Run, persist run-create intent; execute `orca orchestration run-create --objective <objective> --json`; persist receipt and independently established run_id.
2. Without this ticket's Task, persist task-create intent; execute `orca orchestration task-create --run <original-run-id> --spec-file <brief-file> --json`; persist receipt and task_id.
3. Verify placement. Adopt an existing workspace only from an explicit unique persisted identity or verified ticket reference. Independently inspect exact repository, ticket reference, actual branch and absence of conflicting assignment. Never guess from a folder or branch name. Ambiguity pauses. New placement requires an exact verified repo selector; actual branch comes from its receipt.
4. Persist worker-start intent with queue/ticket/Run/Task, request_id, canonical repo, base, placement and expected_branch when known. Existing placement: `{"mode":"existing","binding":{"identity":"<verified>","repo":"<canonical>","ticket":"<ticket>","branch":"<actual>","conflicting_assignment":false,"verified":true}}` with matching expected_branch. New placement: `{"mode":"new-top-level","repo_selector":"id:<verified-id>"}` or verified path selector.
5. Execute `orca orchestration worker-start --run <run-id> --task <task-id> --agent codex --json` with either `--worktree identity:<verified>` or `--worktree new-top-level --repo <exact-selector> --base-branch <base>`. Existing placement receives no creation flags. Configured root conflict pauses. Pass model only if explicitly configured for Codex and effort only with that model; preserve native permissions. Existing `n1_orca_worker_start_cmd` renders these flag rules.
6. Verify returned assignment/workspace before acceptance. Persist full receipt plus dispatch_id, workspace, actual branch, repo, ticket and any terminal identities. Receipt projection: `{"request_id":"<same>","receipt":{...},"verified":true,"identity":{...}}`. Mismatch/ambiguity requires verified false and pause, preserving intent.
7. Where the installed runtime supports `orca reference add`, attach issue and later PR references with `orca reference add <urls> --worktree identity:<workspace> --json`: first persist reference-add intent with ticket/request_id/urls, then full receipt. If the runtime definitively reports this optional command unsupported, record that response as a verified receipt of no mutation; the intent retains the URLs in queue evidence. Continue without allocating another workspace. Other ambiguous attachment failures pause until reconciled. `orca worktree show` and `orca worktree set --help` describe available workspace metadata; use only supported options and never treat metadata as proof of assignment identity.

## Required worker brief

Write a self-contained file naming ticket, queue, canonical repository, approved base and exact base tip, scope and acceptance evidence. For an integration queue the approved base is the persisted `integration_ref` at its pinned `integration_sha`; the child PR must target that branch exactly. Require the worker to:
- Invoke N1 start for this ticket through PR and CI; never merge, modify the base or process another ticket.
- Preserve others' work and native permissions; raise questions/access blockers through Orca. No Stop hook is assumed.
- Persist actual outcome and PR URL/repository/branch/current head, workflow completion, applicable CI commit, expected provider check identities and every check's conclusion/source.
- Call installed Orca worker_done with actual succeeded/failed/blocked outcome and evidence. Never turn failure into success; a PR URL or generic done marker is insufficient.

## Wake and evidence

After launch follow receipt next and yield when instructed. On wake the coordinator itself runs the supplied Orca check once, then persists its full receipt, recovery/next instructions and normalized messages with `wake <queue-id> <revision> <json-file>`. Scripts never execute check or consume mailbox messages. A question/escalation/permission need pauses; resolve it explicitly before resume.

Interrupted Run/Task creation or launch requires inspecting the existing intent, available receipts and exact identities. Adopt only a uniquely established assignment. Follow only receipt-provided recovery/retry instructions. If identity is not uniquely provable, stay paused; never rerun a start because of silence, timeout, fence or an issued close. Never abandon or allocate replacement identities automatically.

Require successful settled worker_done for this exact dispatch from the actual wake, recorded workflow completion and independent provider/Git verification of PR repo, branch and current head. The PR repository and provider host must match the queue repository's origin remote. Derive a known nonempty expected check set from provider requirements. Every expected check must be present, every reported check successful, and all tied to the head or applicable test-merge commit verified for that head. Stale, pending, missing, inaccessible, failed or unknown/empty checks pause.

Persist `evidence <queue-id> <revision> <json-file>`:
```json
{"dispatch_id":"<same>","worker_done":{"outcome":"succeeded","settled":true},"workflow_complete":true,"pr":{"url":"https://...","repo":"owner/repo","branch":"actual","head":"<sha>"},"verified_pr":{"repo":"owner/repo","branch":"actual","head":"<sha>"},"ci":{"commit":"<sha>","expected":["build"],"checks":[{"identity":"build","commit":"<sha>","conclusion":"success"}]}}
```
For test-merge CI add independently verified test_merge_commit/test_merge_head to verified_pr. Preserve provider source responses too. Normalize actual worker_done wake messages with type, dispatch_id, actual outcome and settled only when proven.

The helper validates supplied projections, not external provider truth. Never manufacture verified flags. Only durable accepted completion clears the assignment and allows fresh proof/selection. A successful PR does not prove a blocker merged into base. A failed/blocked worker or missing proof pauses; never merge to unblock or mark success manually.
