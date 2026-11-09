**CI state.** For `prMode: skip`, no PR exists: set `ci_state: disabled` with reason `PR skipped` and continue to the finish decision.

Read `ciChecks.enabled` (default `true`) and record the ci-gate decision as declared in `pipeline.json`. If explicitly false, persist `ci_state: disabled` and continue to the finish decision. Otherwise invoke n1:n1-ci with the created PR number and persist its returned state and reason.

The only returned states are `passed`, `no-checks`, `disabled`, `failed`, and `escalated`. A successful empty CI query after the registration window gives `no-checks`; an API failure, timeout, pending, inaccessible, or unknown result gives `escalated`. A remaining failing check gives `failed`, including when the user skips a red check. Only mark `[x] CI` for completed `passed` or `no-checks` monitoring. Always continue to the finish decision, which blocks failed and escalated states.

These ordinary PR states do not weaken the queue coordinator's separate requirement for nonempty head-bound CI checks.

If a CI fix changes the commit, rerun the full native review core on the final clean committed head before pushing the fix, then reattach the PR only after verifying remote identity and head. If this cannot be done, return `escalated`; old review evidence cannot authorize a merge.
