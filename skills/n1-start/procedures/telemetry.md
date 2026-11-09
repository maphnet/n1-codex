# Procedure: Telemetry

Read `n1_config_val '.telemetry.enabled'` (default `false`).

**If `true`:**
```bash
source ~/.n1-codex/preamble.sh
n1_run_begin "$ID"
n1_active_run_write "$ID" "${N1_RUN_ID:-none}" "${WORKTREE_PATH:-null}" "${BRANCH:-}"
```

**If `false`:** create the run identity without telemetry IO:
```bash
source ~/.n1-codex/preamble.sh
source "$N1_ROOT/lib/telemetry.sh"
n1_run_identity
n1_active_run_write "$ID" "$N1_RUN_ID" "${WORKTREE_PATH:-null}" "${BRANCH:-}"
```
Skip all telemetry IO when disabled.

Carry `N1_SESSION_ID`, `N1_RUN_ID`, and, when disabled, `N1_TELEMETRY_DISABLED=1` into every helper shell. Never infer identity from shared discovery. The enabled run's opening envelope is authoritative.

**Step markers:** Start (before spawning agents): `source "$N1_ROOT/lib/telemetry.sh"; n1_emit_step_event "$N1_RUN_ID" "$N1_VERSION" "$ID" "<step_name>" <N> "$(n1_telemetry_dir "$ID")" started_at=now`. End (after updating overview.md): `n1_emit_step_event "$N1_RUN_ID" "$N1_VERSION" "$ID" "<step_name>" <N> "$(n1_telemetry_dir "$ID")" completed_at=now outcome=<pass|fail|skip> loop_iteration=<N|null> metadata='<JSON>'`. Skipped steps: `outcome=skip`.

| step_number | step_name | metadata fields |
|-------------|-----------|-----------------|
| 1 | `ticket` | `{}` |
| 2 | `analysis` | `{}` — when `relatedProjects.enabled`, analysis.md owns end event with cross_repo fields |
| 3 | `brainstorm` | `{"planning_need":"plan\|direct"}` |
| 4 | `plan` | `{}` |
| 5 | `plan-review` | `{"verdict":"CLEAN\|FIXED"}` |
| 6 | `estimation` | `{"tier":"XS\|S\|M\|L\|XL"}` |
| 7 | `implementation` | `{"execution_path":"direct\|sdd"}` (+ cross_repo_runtime fields from cross-repo.md §5b) |
| 8 | `qa` | `{"loop_iteration":<N>}` |
| 9 | `review` | `{"findings_total":<N>,"findings_critical":<N>}` (+ cross_repo_xrepo_findings from cross-repo.md §7b) |
| 10 | `fix` | `{"loop_iteration":<N>}` |
| 11 | `local-testing` | `{"action_type":"live\|test_only\|skipped\|smoke_deferred","infra_started":<bool>,"app_started":<bool>,"services":[...],"scenario_types":[...],"qa_overlap_pct":<int\|null>}` |
| 12 | `pr` | `{}` |
| 13 | `ci` | `{}` |
| 14 | `finish` | `{}` |
| 17 | `smoke` | `{"action_type":"smoke_executed","endpoint_status":<string\|null>,"tests_total":<int>,"tests_passed":<int>}` |
| 18 | `evaluator` | `{"verdict":"PASS\|FAIL\|SKIP\|BLOCKED","waived":<bool>}` |
