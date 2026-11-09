# Intake

Use only the explicit validated sequence. Establish the canonical repository via `git rev-parse --show-toplevel`, configured target base and tracker readTicket/getIssueLinks operations via `n1_config_val`. Ambiguous repository/base/placement or unavailable tracker access must be reported before launch.

Read every named ticket and inbound blockers. Preserve every ticket, order, known blockers and lookup failure. Missing links operations or ambiguous/inaccessible evidence means unknown blockers for that ticket, never an empty verified list.

Choose and report a fresh safe queue ID. Initialize once:
`n1_queue_state init <queue-id> <canonical-repo> <base-ref> <ticket-id>...`.
For an integration queue, the coordinator must also pass `--grant <json-file>`.
The grant records the canonical repository and origin, the independently verified
default branch, one explicit non-default `integration_ref`, and an approval with
`scope: integration-only`. The target is fetched and its exact tip is persisted
as `integration_sha`. If the approved target does not exist, intake persists a
create-only setup intent pinned to the verified default tip; the coordinator
must perform only a create-only push with an empty expected old value (for
example, `git push --force-with-lease=refs/heads/<target>: origin <default-sha>:refs/heads/<target>`),
re-fetch the exact branch, and reconcile a receipt proving that exact branch was
created before selection. Any existing target or ambiguous result retains the
intent and pauses the queue.
A missing or ambiguous grant pauses intake. A configuration hint or branch naming
convention never grants permission.
Never reset or overwrite a queue. State lives at `$N1_HOME/queue/<queue-id>/state.json`; access it through bounded helpers, never direct edits.

Before every selection, including after resume, refresh every pending/blocked ticket's tracker proof. Fetch the target base without checkout or base mutation, pin its SHA, independently establish each blocker's verified merged commit, and verify ancestry with `git merge-base --is-ancestor <merged-sha> <base-sha>`. A completed PR or done tracker status alone is insufficient. Write JSON using file tools, never shell interpolation of tracker text, then persist:
`n1_queue_state transition <queue-id> <expected-revision> <json-file>`.

```json
{"ticket":"NC-101","reason":"tracker and Git verification","blocker_snapshot":{"base_sha":"<current-base-sha>","lookup":"verified","blockers":[{"ticket":"NC-100","merged_sha":"<merged-sha>","verified":true}]}}
```

Use lookup unknown for missing evidence and retain known blockers. Revision conflicts require rereading/recomputing, never blind replay.

`select <queue-id>` independently fetches/revalidates the base, checks ancestors, and atomically reserves the first eligible ticket. A blocked first ticket does not stall independent later tickets. Preserve blocked rows and recheck them later; never merge to unblock. A base race rejects reservation and requires refreshed proofs. Any active, paused or uncertain assignment prevents selection.
