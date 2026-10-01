# N1 Codex

Codex-native fork of [N1 for Claude Code](https://github.com/maphnet/n1-plugin).
The workflow and per-ticket memory are retained; execution uses Codex skills,
native agents, and hooks. This fork does not update or install the Claude plugin.

**Milestone 1 is a draft:** automated helper and packaging checks are available;
live pipeline validation is still required before production use. Unattended queue
execution, generated deny hooks, and detailed Codex token accounting are deferred.

## Requirements and installation

Codex CLI 0.155.1 or later, Bash, Git, `gh`, `jq`, and Python 3.11+.
Tracker MCP connections are optional and use the existing N1 project configuration.

After the Codex branch is published:

```bash
codex plugin marketplace add maphnet/n1-codex --ref feat/codex-native
codex plugin add n1-codex@n1-codex
```

Start a new session. Review and trust the plugin's hooks with `/hooks`; installation
alone does not trust hooks. Invoke the `n1-init` skill from **n1-codex**, especially
if the older `n1` plugin is also installed. Initialization installs project-local
`.codex/agents/n1-*.toml` profiles; restart Codex to load them.

For local development, register the checkout as a local marketplace instead:

```bash
codex plugin marketplace add /absolute/path/to/n1-codex
codex plugin add n1-codex@n1-codex
```

Installed plugins are cached copies. Refresh/reinstall after changes, then start a
new session. This repository's plugin identifier is `n1-codex`, distinct from `n1`.

For workspace-write sessions, authorize the shared project state directory as an
additional writable root when launching Codex, using the actual project slug:

```bash
codex --sandbox workspace-write --add-dir "$HOME/.n1/<project>"
```

An explicit `N1_HOME` requires that directory instead. Any separately located
worktree must also be writable. Writer personas inherit the session permissions;
reviewer profiles remain read-only. Without access to shared memory, pause setup
and explain the missing writable root instead of relocating memory or bypassing
the sandbox. This permission path still needs live validation.

## Shared project state

Both forks intentionally use the same `N1_HOME`, `~/.n1/<project>/config.json`, and
`~/.n1/<project>/memory/`. Existing legacy resolution remains supported. There is
no automatic copying or migration. Do not run both hosts against the same active
ticket concurrently: ticket files remain shared.

Only Codex runtime bootstrap is separate: `~/.n1-codex/preamble.sh` and its session
files. Claude's `~/.n1/preamble.sh`, installed cache, and `.claude/settings*.json`
are not modified. Existing explicit worktree settings remain respected.

Codex inherits its configured model/effort by default. It ignores Claude model
names without rewriting them. Optional explicit per-persona settings coexist:

```json
{
  "models": {
    "developer": {
      "claude-code": "sonnet",
      "codex": {"model": "gpt-6.1-sol", "effort": "medium"}
    }
  }
}
```

Use a model available to your account. Normal work does not automatically escalate
to Astra. See [Codex routing](references/codex-routing.md) for delegation and
read-only reviewer behavior.

## Scope

- Interactive initialization, planning, implementation, QA, review, and resume
  retain the N1 workflow and memory layout.
- PR/CI/finish skills retain their explicit workflow gates. The duplicate
  post-PR Codex review subprocess is disabled in this Codex fork.
- Queue entry points stop before side effects; there is no Claude fallback.
- Existing rule instructions remain readable. Claude-generated deny hooks are
  not changed or represented as enforced by Codex.
- Step outcomes and timing remain useful. Missing Codex token accounting is
  reported as unknown; no token/cost parity is claimed.

## Verification

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
bash tests/test_host_lib.sh
bash tests/test_model_resolver.sh
bash tests/test_codex_isolation.sh
bash tests/test_codex_workflows.sh
bash tests/test_hooks.sh
bash tests/test_preamble.sh
bash tests/test_manifests.sh
```

The remaining shared helper tests live in `tests/`. Historical design documents
describe upstream behavior and are not the Codex runtime contract.

Port upstream fixes selectively. Do not automatically merge this branch into the
Claude repository or synchronize shared configuration schemas between forks.
