# Step 2: Merge State Machine

Queue children and final integration-to-default queue PRs are human-owned: never merge them here, even with interactive approval. Check persisted queue state and identity; if ownership is uncertain, stop. Preserve the coordinator's separate integration-only grant.

Read the current PR state. If already `MERGED`, capture its merge SHA and go to Step 3; if `CLOSED`, stop with `failed`. If `OPEN`, follow `<N1_ROOT>/references/deployment-actions.md` § Parse with `PRS=<n>` and `OUT=$N1_HOME/scratch/deploy-actions-<n>.tsv` before any merge:

- `fetch-failed:#<n>`: stop; the actions are unknown.
- `unticked:0`: continue.
- `mode:runbook` with unticked rows: follow § Runbook with `ID=<ID>` and empty `SHA`, then stop without merging.
- `mode:walk` with before rows: follow § Walk with `PHASE=before`. If `WALK=aborted`, report "Merge blocked: before-deploy actions are not complete" and stop.
- After rows wait for Step 4.

For an ordinary unattended run, require `n1_merge_allowed`, CI state `passed`, `no-checks`, or `disabled`, and current run-bound evidence. Invoke exactly once:

```bash
source ~/.n1-codex/preamble.sh
python3 "$N1_ROOT/scripts/n1-reviewed-head.py" merge "$ID" "$REVIEW_REPO" "$CURRENT_BRANCH" "$N1_RUN_ID" "$PR_NUMBER" "$MERGE_METHOD" "$CI_STATE"
```

The helper verifies the current PR identity and head, current checks and review threads, repeats those checks immediately before the single `gh pr merge --match-head-commit` call, and returns `merged <sha>` only after GitHub confirms the merge. A failed command, API failure, drift, unresolved feedback, pending checks, pagination uncertainty, or still-open/enqueued PR stops with `escalated`; preserve pending evidence. Never use `--auto`, retry without head protection, or bypass protection. Continue to deploy and close only after `merged <sha>`.

When unattended authority is absent and `N1_HEADLESS=1`, return `escalated` without prompting or invoking interactive merge. Otherwise present the current PR, CI and review-thread results and prompt exactly: `Proceed with merge? (yes / no — fix first)`. On `no`, or any answer other than exact `yes`, return `open` and preserve the ticket and evidence. On exact `yes`, record `interactive approval: yes` in `overview.md`, set `N1_INTERACTIVE_APPROVED=yes`, and invoke the same helper with `interactive-merge`:

```bash
source ~/.n1-codex/preamble.sh
read -r APPROVAL
[ "$APPROVAL" = yes ] || { echo 'Merge not approved; PR remains open.'; exit 0; }
N1_INTERACTIVE_APPROVED=yes python3 "$N1_ROOT/scripts/n1-reviewed-head.py" interactive-merge "$ID" "$REVIEW_REPO" "$CURRENT_BRANCH" "$N1_RUN_ID" "$PR_NUMBER" "$MERGE_METHOD" "$CI_STATE"
```

The helper repeats all identity, head, checks and unresolved-review guards and confirms `MERGED`; a failure returns `escalated`. Queue ownership still cannot be overridden.

## Step 2b: Local Merge (no-PR path, `prMode == "skip"` only)

An unattended or headless run stops here with `skipped`: there is no equivalent remote head protection. Only a separate explicit interactive approval permits the local path. Queue children and final queue PRs always stop.

1. **Worktree context:** if the current toplevel (`git rev-parse --show-toplevel`) contains `/$(n1_worktree_root)/`, resolve the main checkout (`MAIN_CHECKOUT=$(dirname "$(git rev-parse --git-common-dir)")`) and run the default-branch git commands below from `$MAIN_CHECKOUT` — the default branch is checked out there, and `git checkout <defaultBranch>` inside the worktree fails with "already checked out". The clean-tree precondition then applies to the main checkout. Plain checkout: run everything from the current directory.
2. **Preconditions:** `git status --porcelain` must be empty (dirty tree → "Commit or stash changes first." **STOP.**); the feature branch and `git.defaultBranch` must both exist locally.
3. **Test-suite precondition** (run in the feature-branch directory — the worktree, or the plain checkout on `<branch>`): discover the full-suite test command the same way the qa-engineer does (project root: `package.json` `scripts.test`, `pytest.ini`, `pyproject.toml`, `setup.cfg`, `phpunit.xml`, `go.mod` → `go test ./...`, Makefile `test` target — first match wins).
   - **No test configuration found:** note "no test suite detected — skipping test precondition" in the report and proceed.
   - **Test configuration found:**
     ```bash
     <discovered-test-command> 2>&1; SUITE_EXIT=$?
     ```
     Non-zero `SUITE_EXIT` → report the failure output and "Refusing to merge: test suite is failing (exit code <SUITE_EXIT>). Fix failing tests and re-run `n1-codex:n1-finish`." **STOP.**
4. **Merge** by `mergeMethod`:
   - `squash`: on `<defaultBranch>` (`git checkout <defaultBranch>`; in `$MAIN_CHECKOUT` when in a worktree): `git merge --squash <branch> && git commit -m "<ID>: <ticket title>"`
   - `merge`: on `<defaultBranch>`: `git merge --no-ff <branch> -m "Merge branch '<branch>'"`
   - `rebase`: in the feature-branch directory: `git rebase <defaultBranch>`; then on `<defaultBranch>`: `git merge --ff-only <branch>`
5. **Merge conflict** → `git merge --abort` (or `git rebase --abort` in the feature-branch directory), report the conflicting files, and in a plain checkout switch back to the feature branch. **STOP.**
6. Capture the merge SHA: `git rev-parse HEAD` on `<defaultBranch>`. **No push.** Report: "Merged `<branch>` into `<defaultBranch>` locally. Push manually when ready: `git push origin <defaultBranch>`."
7. Skip Step 3 (`03-deploy.md`) — nothing is on the remote. Deploy status `skipped (local merge)`, smoke `n/a`. Go to Step 4; the tracker comment is the local-merge variant.
