#!/usr/bin/env bash
# The two plugin manifests must be valid JSON and carry one identical version.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0
for f in plugin.json .codex-plugin/plugin.json .agents/plugins/marketplace.json; do
    [ -f "$f" ] || { echo "FAIL: missing $f"; FAIL=1; continue; }
    jq -e . "$f" >/dev/null 2>&1 || { echo "FAIL: invalid JSON $f"; FAIL=1; }
done
V1=$(jq -r .version plugin.json)
V2=$(jq -r '.version' .codex-plugin/plugin.json)
if [ "$V1" = "$V2" ] && [ -n "$V1" ]; then
    echo "PASS: all manifests at $V1"
else
    echo "FAIL: versions differ: claude=$V1 claude-mkt=$V2"; FAIL=1
fi
exit $FAIL
