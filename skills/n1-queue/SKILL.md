---
name: n1-queue
description: "Use when the user names an ordered list of tracker tickets for a supervised queue, or requests status, stop, or resume of a persisted queue."
argument-hint: "<ticket-id>... | --status <queue-id> | --stop <queue-id> | --resume <queue-id>"
---

# N1 Queue

Process exactly the explicit ordered ticket list with at most one unsettled Codex worker. Each ticket runs N1 through PR and CI. Neither worker nor coordinator may merge; no Stop hook is assumed.

Integration mode is opt-in. Intake may use `init ... --grant <json-file>` only
when the grant contains the canonical checkout/origin, verified `default_ref`,
an explicit non-default `integration_ref`, and `approval.scope` set to
`integration-only`. The queue persists that identity and exact target tip; later
configuration, ticket text, or PR metadata cannot authorize another branch.

| Interface | Action |
| --- | --- |
| `n1-queue <ticket-id>...` | Start exactly this ticket list |
| `n1-queue --status <queue-id>` | Read persisted status only |
| `n1-queue --stop <queue-id>` | Prevent launches and request guarded cancellation |
| `n1-queue --resume <queue-id>` | Reconcile original assignment before continuing |

Reject empty input, mixed modes, unknown options, duplicates and malformed IDs before state creation or service calls. All ticket/queue IDs must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Never discover additional tickets, expand stories, reorder the list or infer the latest queue.

Source `~/.n1-codex/preamble.sh`, then `"$N1_ROOT/lib/queue.sh"`. Stop if N1_HOME is unresolved. Preserve native permissions and explicit Codex model overrides; never fall back to Claude.

Lifecycle commands follow [report.md](steps/report.md) only. New queues follow [intake.md](steps/intake.md), [preview.md](steps/preview.md), then [run.md](steps/run.md). Orca wakes follow run.md for the persisted Run.

Never start a daemon, poll mailboxes, steer terminals, modify the base, merge to unblock, abandon uncertainty or infer exit from timeout. Pause with the unresolved evidence.
