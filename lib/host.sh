#!/usr/bin/env bash
# N1 host helpers for the Codex-native fork.
# Sourced by lib/config.sh and by every hook. Pure bash; jq optional.
# Host facts and bootstrap files live in ~/.n1-codex, separate from shared projects.

n1_host_file() { printf '%s' "${N1_HOST_FILE:-${N1_STATE_DIR:-$HOME/.n1-codex}/host.json}"; }

n1_host() { printf 'codex'; }

# Hooks may explicitly export N1_SESSION_ID from their payload's session_id.
# Shell snippets otherwise use Codex's native thread identity, never Claude's.
n1_session_id() { printf '%s' "${N1_SESSION_ID:-${CODEX_THREAD_ID:-}}"; }

n1_session_file() {
    local id; id=$(n1_session_id)
    case "$id" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac
    printf '%s/sessions/%s.json' "${N1_STATE_DIR:-$HOME/.n1-codex}" "$id"
}

n1_plugin_root() {
    if [ -n "${CODEX_PLUGIN_ROOT:-}" ]; then printf '%s' "$CODEX_PLUGIN_ROOT"; return; fi
    if [ -n "${N1_PLUGIN_ROOT:-}" ]; then printf '%s' "$N1_PLUGIN_ROOT"; return; fi
    printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

n1_plugin_version() {
    local root manifest; root=$(n1_plugin_root)
    manifest="$root/.codex-plugin/plugin.json"
    [ -f "$manifest" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        jq -r '.version // empty' "$manifest" 2>/dev/null || true
    else
        grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true
    fi
}

n1_worktree_root() {
    # Relative directory under the main checkout holding N1 worktrees.
    local v=""
    if type n1_config_val >/dev/null 2>&1; then v=$(n1_config_val '.worktree.root' 2>/dev/null || true); fi
    if [ -n "$v" ]; then printf '%s' "${v%/}"; return; fi
    printf '.codex/n1-worktrees'
}

n1_headless_cmd() {
    # Usage: n1_headless_cmd <skill> <args> <model> <outfile> [repo] [effort] [brief-file]
    # A transport only: the caller supplies the already-selected workflow/brief.
    local skill="$1" args="$2" model="$3" out="$4" repo="${5:-}" effort="${6:-}" brief="${7:-}"
    local prompt="\$$skill $args"
    local cmd=(codex exec --json)
    if [ -n "$brief" ]; then
        [ -r "$brief" ] || { echo 'N1: dispatch brief is unreadable' >&2; return 1; }
        prompt+=$'\n'; prompt+="$(< "$brief")"
    fi
    [ -z "$model" ] || cmd+=(--model "$model")
    if [ -n "$effort" ]; then
        case "$effort" in none|minimal|low|medium|high|xhigh|max|ultra) ;;
            *) echo "N1: unsupported Codex reasoning effort: $effort" >&2; return 1;;
        esac
        cmd+=(-c "model_reasoning_effort=\"$effort\"")
    fi
    cmd+=(-- "$prompt")
    [ -z "$repo" ] || printf 'cd %q && ' "$repo"
    # A headless child is a new session. Retain parent linkage, never inherit its
    # run/session identity.
    printf 'env -u N1_SESSION_ID -u N1_RUN_ID -u N1_TRANSCRIPT_PATH -u CLAUDE_CODE_SESSION_ID -u CODEX_THREAD_ID N1_PARENT_SESSION_ID=%q ' "$(n1_session_id)"
    printf '%q ' "${cmd[@]}"
    # Closed stdin: a headless child must never wait on an inherited pipe (NP-224).
    printf '< /dev/null > %q 2>&1' "$out"
}

n1_bg_launch_cmd() {
    echo 'N1: Codex background sessions are unsupported in milestone 1.' >&2
    return 1
}

n1_bg_cmd() {
    echo 'N1: Codex background-session control is unsupported in milestone 1.' >&2
    return 1
}

n1_desktop_notify() {
    # Usage: n1_desktop_notify <title> <body> — first desktop notifier that actually runs wins
    # (on PATH is not enough: WSL interop can be present but disabled). Returns 1 if none works.
    local t="$1" b="$2"
    if command -v notify-send >/dev/null 2>&1 && timeout 10 notify-send "$t" "$b" >/dev/null 2>&1; then return 0; fi
    if command -v osascript >/dev/null 2>&1 && timeout 10 osascript \
        -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
        "$t" "$b" >/dev/null 2>&1; then return 0; fi
    if command -v powershell.exe >/dev/null 2>&1 && N1_NT="$t" N1_NB="$b" WSLENV="N1_NT:N1_NB${WSLENV:+:$WSLENV}" \
        timeout 10 powershell.exe -NoProfile -NonInteractive -Command '
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
            $x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
            $n = $x.GetElementsByTagName("text")
            $n.Item(0).AppendChild($x.CreateTextNode($env:N1_NT)) > $null
            $n.Item(1).AppendChild($x.CreateTextNode($env:N1_NB)) > $null
            $app = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))
        ' >/dev/null 2>&1; then return 0; fi
    return 1
}

n1_hook_field() {
    # Usage: printf '%s' "$PAYLOAD" | n1_hook_field <name> — top-level string field or empty.
    local name="$1" input; input=$(cat)
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -r --arg k "$name" '.[$k] // empty' 2>/dev/null || true
    else
        printf '%s' "$input" | grep -o "^{[^{]*\"$name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | grep -o "\"$name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"$" | sed 's/.*:[[:space:]]*"\([^"]*\)"$/\1/' || true
    fi
}

n1_agent_type() { printf 'n1-%s' "$1"; }  # Usage: n1_agent_type <persona>

n1_persona_name() {
    # Usage: n1_persona_name <agent_type> — persona name, or empty when not an N1 persona
    case "$1" in
        n1-*) printf '%s' "${1#n1-}" ;;
        *) printf '' ;;
    esac
}
