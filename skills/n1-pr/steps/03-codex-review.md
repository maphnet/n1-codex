<!-- Purpose: Avoid a duplicate review in the native Codex workflow. -->

Skip this step entirely in N1 Codex. The pipeline's native code and security reviewers remain the review gate. Do not launch a second Codex process, post duplicate review comments, or start a post-PR remediation loop.

The native full review core records the exact clean committed head and required lane results before push. Documentation, rebase, or CI fix commits invalidate that evidence; rerun that same core on the final committed head before push or stop. PR association requires matching remote identity and head.
