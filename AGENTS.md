# N1 Codex

Codex-native fork of `maphnet/n1-plugin`. All code and documentation are English.
The original repository and installed Claude plugin must not be modified by work here.

## Runtime

- Bash helpers, Markdown workflows, Python standard library; no new runtime dependencies.
- Project configuration and memory intentionally reuse `~/.n1/<project>/` and `N1_HOME`.
- Codex bootstrap/session files live under `~/.n1-codex/`. Never overwrite `~/.n1/preamble.sh`.
- Preserve shared config keys. Claude models remain untouched; Codex reads explicit
  `models.<persona>.codex` overrides and otherwise inherits the host default.
- Use native Codex tools and project `.codex/agents/n1-*.toml` profiles.
- Queue lifecycle, generated deny hooks, and detailed Codex usage accounting are not
  supported in milestone 1. Never silently fall back to Claude.

## Development

Use subagents selectively for independent work, with disjoint write ownership.
Use Sol for implementation and Luna for bounded checks. Reserve Astra for high-level
architecture, a final whole-branch review, or escalation after two failed fixes.
Use the writing-skills guidance when modifying workflow instructions.
Run relevant shell suites and `python3 -m unittest discover -s tests -p 'test_*.py'`.
Do not report end-to-end validation without a live Codex run.

Use global Git identity; do not add local identity overrides or attribution trailers.
Publish only to the Codex fork. Never merge into the Claude upstream automatically.
