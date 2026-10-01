<!-- Purpose: Reuse shared N1 project state and install project-scoped Codex personas. -->

## Prerequisites

Create a minimal `AGENTS.md` containing `# <project-name>` in the project root if it is missing. Existing project instructions remain authoritative.

Resolve the shared state and install the native Codex persona profiles:

```bash
source ~/.n1-codex/preamble.sh
PROJECT_ROOT=$(git rev-parse --show-toplevel)
python3 "$N1_ROOT/scripts/install-agents.py" "$PROJECT_ROOT"
```

Report the generated `.codex/agents/n1-*.toml` profiles and tell the user to restart Codex to load them. Do this even when shared N1 configuration already exists. Do not edit global Codex configuration or any Claude settings.

## Existing Configuration

Use the same `N1_HOME` as the original N1 plugin: explicit `N1_HOME` when provided, otherwise the existing `~/.n1/<project>/` resolution. `~/.n1-codex/preamble.sh` is a host bootstrap shim, not a state directory. Never copy, move, migrate, prune, or rewrite existing project state merely to enable Codex.

If `$N1_HOME/config.json` exists, read the necessary keys with `n1_*_val` helpers. Preserve all existing configuration, memory, telemetry, and host-specific overrides.

- First, when invoked with `--related`, run only the Related Projects Configuration step against the existing config, preserving all other settings; skip the completeness checks below.
- If the invocation includes `reconfigure`, continue through the setup sections using their reconfiguration flows. Change only explicitly selected settings; merge them into the existing config.
- Otherwise, check missing top-level sections against the Expected Config Keys in the dispatcher. If none are missing, report the configured state path, tracker, PR mode, autonomy, cleanup, telemetry, local testing, and restart instruction, then **STOP** without questions or config writes.
- If sections are missing, offer `1 — Add missing sections / 2 — Full reconfigure / 3 — Skip`. Add only missing sections for option 1, in dispatcher order. Preserve every existing key and value. If `rules` is missing, analyze the repository first. Option 2 follows explicit reconfiguration; option 3 stops after installing profiles.

If no external config exists but legacy `.n1/n1.config.json` exists, report that legacy project-local state needs to be configured with the original N1 plugin, then **STOP**. Codex does not migrate it.

If no configuration exists, continue with fresh setup, using the shared `N1_HOME` path. No existing state is copied to a new location.

## Targeted Upgrade

Process missing keys in dispatcher order: tracker, git, ticketTagging, observability, estimation, localTesting, finishWork, release, telemetry, analysisCache, rules, worktree, autonomy, models. Use each section's fresh-setup flow. Missing `models` is `{}`; Codex personas inherit the session model by default.

Merge only the added sections into the existing config, then show the summary and restart instruction.
