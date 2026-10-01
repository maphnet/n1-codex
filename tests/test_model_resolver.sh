#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/config.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export N1_HOME="$TMP"
check() { [ "$2" = "$3" ] || { echo "FAIL: $1 expected '$2', got '$3'" >&2; exit 1; }; }
fixture() { printf '%s\n' "$1" > "$TMP/config.json"; }
fixture '{"models":{}}'
check inherit "" "$(n1_resolve_model developer implementation)"
check columns $'\t' "$(n1_resolve_agent developer)"
fixture '{"models":{"developer":"sonnet","code-reviewer":"opus"}}'
check claude "" "$(n1_resolve_model developer)"
check claude-review "" "$(n1_resolve_model code-reviewer)"
fixture '{"models":{"developer":{"claude-code":"opus","codex":{"model":"gpt-6.1-sol","effort":"high"}}}}'
before=$(sha256sum "$TMP/config.json")
check explicit gpt-6.1-sol "$(n1_resolve_model developer)"
check pair $'gpt-6.1-sol\thigh' "$(n1_resolve_agent developer implementation)"
check unchanged "$before" "$(sha256sum "$TMP/config.json")"
fixture '{"models":{"developer":"gpt-6-sol"}}'
check string gpt-6-sol "$(n1_model_for developer)"
fixture '{"models":{"developer":{"codex":"gpt-6.1-sol"}}}'
check host-string gpt-6.1-sol "$(n1_model_for developer)"
fixture '{"models":{"developer":{"codex":{"model":"sonnet","effort":"bogus"}}}}'
check invalid $'\t' "$(n1_resolve_agent developer)"
fixture '{"models":{"developer":{"codex":{"model":false,"effort":["high"]}}}}'
check types $'\t' "$(n1_resolve_agent developer)"
fixture '{"models":{"developer":{"codex":{"effort":"high"}}}}'
check effort-only $'\thigh' "$(n1_resolve_agent developer)"
function command() { if [ "${1:-}" = -v ] && [ "${2:-}" = jq ]; then return 1; fi; builtin command "$@"; }
check no-jq $'\t' "$(n1_resolve_agent developer)"
unset -f command
echo 'PASS: Codex model resolution'
