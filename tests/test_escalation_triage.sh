#!/usr/bin/env bash
# N1-64: n1_escalation_critical — hard blocks first, rules only add critical cases, fail safe.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
assert_eq() {
    if [ "$2" = "$3" ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1 (expected=[$2] actual=[$3])"; FAIL=$((FAIL+1)); fi
}
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
: "${N1_HOME:=}"; export N1_HOME
source "$REPO_ROOT/lib/config.sh"
source "$REPO_ROOT/lib/rules.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/rules" "$T/norules"
q() { # <file> <category> <question>
    jq -n --arg c "$2" --arg q "$3" '{ticket:"T-1",step:"plan",category:$c,question:$q,options:["A","B"],recommended:"",rationale:""}' > "$1"
}
cls() { n1_escalation_critical "$1" "$2" || true; }

q "$T/sec.json" security "Pick the token storage"
assert_eq "hard block: security category" "critical: security" "$(cls "$T/sec.json" "$T/norules")"
q "$T/rel.json" release "Tag it?"
assert_eq "hard block: release gate" "critical: release" "$(cls "$T/rel.json" "$T/norules")"
q "$T/other.json" prod-deploy "Deploy now?"
assert_eq "other stop-list category is critical" "critical: prod-deploy" "$(cls "$T/other.json" "$T/norules")"
q "$T/plain.json" none "Import via importlib or a hand-off file?"
assert_eq "no category match, no rules -> non-critical" "non-critical" "$(cls "$T/plain.json" "$T/norules")"
n1_escalation_critical "$T/plain.json" "$T/norules" >/dev/null && rc=0 || rc=$?
assert_eq "non-critical exit code" "1" "$rc"
q "$T/kw.json" none "Should the public API return 404 here?"
assert_eq "hard-block keyword in text (misclassified child)" "critical: hard-block keyword" "$(cls "$T/kw.json" "$T/norules")"
# N1-64 SEC-7: the keyword backstop also scans recommended/step, and public-api with no separator.
jq -n '{ticket:"T-1",step:"plan",category:"none",question:"Import via A or B?",options:["A","B"],recommended:"B: touches the publicapi surface",rationale:""}' > "$T/rec.json"
assert_eq "hard-block keyword in recommended field" "critical: hard-block keyword" "$(cls "$T/rec.json" "$T/norules")"
jq -n '{ticket:"T-1",step:"architecture",category:"none",question:"Import via A or B?",options:["A","B"],recommended:"",rationale:""}' > "$T/step.json"
assert_eq "hard-block keyword in step field" "critical: hard-block keyword" "$(cls "$T/step.json" "$T/norules")"

printf -- '---\ndescription: Fleet safety\ntopic: escalation\napplies_to: queue\nenforcement: gate\nescalation_critical: gateway restart, auth.json\n---\nGateway restarts and auth files always need a human.\n' > "$T/rules/fleet.rule.md"
q "$T/gw.json" none "Is a Gateway Restart acceptable after the import?"
assert_eq "rule predicate adds critical (case-insensitive)" "critical: rule fleet" "$(cls "$T/gw.json" "$T/rules")"
assert_eq "rule not matching stays non-critical" "non-critical" "$(cls "$T/plain.json" "$T/rules")"
printf -- '---\ndescription: Try to relax\ntopic: escalation\napplies_to: queue\nenforcement: gate\nescalation_critical:\n---\nx\n' > "$T/rules/empty.rule.md"
assert_eq "rules cannot remove a hard block" "critical: security" "$(cls "$T/sec.json" "$T/rules")"
# N1-64 SEC-4: an escalation_critical: key present but parsing empty fails safe to critical
# (empty.rule.md sorts before fleet.rule.md, so it is hit first regardless of pattern match).
assert_eq "empty escalation_critical value fails safe to critical" \
    "critical: rule empty (empty escalation_critical)" "$(cls "$T/plain.json" "$T/rules")"

mkdir -p "$T/rulesq"
printf -- "---\ndescription: Fleet safety quoted\ntopic: escalation\napplies_to: queue\nenforcement: gate\nescalation_critical: 'gateway restart, auth.json'\n---\nx\n" > "$T/rulesq/fleetq.rule.md"
assert_eq "N1-64 SEC-4: single-quoted escalation_critical value parses" \
    "critical: rule fleetq" "$(cls "$T/gw.json" "$T/rulesq")"

assert_eq "missing question file -> critical" "critical: unreadable question" "$(cls "$T/none.json" "$T/norules")"
printf 'not json' > "$T/bad.json"
assert_eq "malformed question -> critical" "critical: unreadable question" "$(cls "$T/bad.json" "$T/norules")"
jq -n '{question:"x"}' > "$T/nocat.json"
assert_eq "no category (older child) -> critical" "critical: no category" "$(cls "$T/nocat.json" "$T/norules")"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
