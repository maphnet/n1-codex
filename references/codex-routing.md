# Codex runtime routing

N1 Codex shares project configuration and memory at `~/.n1/<project>/` with N1
for Claude. Its bootstrap lives separately at `~/.n1-codex/preamble.sh`.
Source that bootstrap before helper snippets. Keep the current working directory
inside the intended project or worktree. Session identity comes from Codex.
The parent and writer workers need write access to the resolved `N1_HOME` and
worktree. In workspace-write mode, launch with `--add-dir <N1_HOME>` and any
separate worktree root. If the sandbox blocks required memory writes, stop with
the missing-root diagnostic; never change memory location or bypass permissions.

## Dispatch a persona

Read `<N1_ROOT>/agents/<persona>.md` and pass its instruction body, the task,
absolute workspace path, required memory paths, and expected return format.
Use native subagent tools with fresh context (`fork_turns="none"` when exposed).
Wait for actual completion before consuming results. Parallelize independent work;
never assign overlapping write ownership. Fix cycles receive fresh workers.

If the spawn tool exposes `agent_type`, use the installed `n1-<persona>` profile.
`python3 <N1_ROOT>/scripts/install-agents.py <project-root>` installs profiles;
start a new Codex session afterward. Review profiles have a read-only sandbox.
If custom profiles are unavailable, review work must run through `codex exec
--sandbox read-only` with the persona and task prompt; prompt wording alone is
not a substitute for filesystem restrictions. Do not claim tool-level parity
with Claude allowlists: Codex uses native sandbox and approval controls.

`n1_resolve_agent` returns model and effort separated by a tab. Empty fields mean
inherit configured Codex defaults: omit them from the spawn call. Ignore Claude
model names. Use explicit Codex overrides only when configured. Reserve Astra
for architecture adjudication, one final whole-branch review, or escalation after
two failed fix rounds. Normal implementation, QA, and focused reviews inherit defaults.

## Other operations

- Invoke a skill: read `<N1_ROOT>/skills/<name>/SKILL.md` and follow it inline.
  Prefer the installed `n1-codex` plugin when another plugin exposes the same name.
- Ask the user: use the exposed question tool when available and appropriate;
  otherwise ask in ordinary text. Required approval waits for an actual answer.
- Deferred MCP tools: use the exposed discovery mechanism and configured tracker
  server. Do not invent Claude tool names or switch providers silently.
- Headless queue/background lifecycle is unavailable in this milestone. Report
  this limitation before starting a queue; do not launch Claude as a fallback.
- Existing project deny rules must be ported and tested for Codex before relying
  on them. Do not edit `.claude/settings*.json` or replace Claude hook scripts.
- Usage accounting is not yet ported. Retain step outcomes/timing; do not interpret
  missing Codex token data as zero usage.
