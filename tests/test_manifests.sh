#!/usr/bin/env bash
# Codex must select the legacy manifest format, which supports lifecycle hooks.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0
[ ! -e plugin.json ] || { echo "FAIL: root plugin.json disables Codex hook loading"; FAIL=1; }
for f in .codex-plugin/plugin.json .agents/plugins/marketplace.json hooks/hooks.json; do
    [ -f "$f" ] || { echo "FAIL: missing $f"; FAIL=1; continue; }
    jq -e . "$f" >/dev/null 2>&1 || { echo "FAIL: invalid JSON $f"; FAIL=1; }
done
VERSION=$(jq -r '.version // empty' .codex-plugin/plugin.json)
if [ -n "$VERSION" ] && [ "$FAIL" = 0 ]; then
    echo "PASS: Codex manifests at $VERSION"
else
    echo "FAIL: invalid Codex packaging"; FAIL=1
fi
exit $FAIL
