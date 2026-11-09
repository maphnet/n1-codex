#!/usr/bin/env bash
# Read-only reconciliation for the human-controlled integration-to-default PR.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/lib/config.sh"
source "$ROOT/lib/frontmatter.sh"
source "$ROOT/lib/queue.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
repo=$t/repo
git init -q -b main "$repo"
git -C "$repo" -c user.name=test -c user.email=test@example.test commit -qm base --allow-empty
git -C "$repo" remote add origin https://example.test/owner/repo.git
sha=$(git -C "$repo" rev-parse HEAD)
mkdir "$t/bin"
cat > "$t/bin/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1" = pr ] && [ "$2" = list ]; then cat "$GH_JSON"; exit 0; fi
if [ "$1" = pr ] && [ "$2" = view ]; then cat "$GH_JSON"; exit 0; fi
printf 'unexpected gh mutation: %s\n' "$*" >&2; exit 9
GH
chmod +x "$t/bin/gh"
export PATH="$t/bin:$PATH" GH_JSON="$t/pr.json"
printf '[]\n' > "$GH_JSON"
result=$(n1_queue_final_pr_gate "$repo" integration/NC-2 main "$sha")
[[ "$result" == $'pending\tcreate\towner/repo\tintegration/NC-2\tmain\t'*"$sha" ]]
printf '[{"url":"https://github.com/owner/repo/pull/4","headRefName":"integration/NC-2","baseRefName":"main","headRefOid":"%s","baseRefOid":"base","isCrossRepository":false,"state":"OPEN"}]\n' "$sha" > "$GH_JSON"
result=$(n1_queue_final_pr_gate "$repo" integration/NC-2 main "$sha")
[[ "$result" == $'verified\thttps://github.com/owner/repo/pull/4\t'*$'\tintegration/NC-2\tmain' ]]
if n1_queue_final_pr_gate "$repo" integration/NC-2 main "$(printf '1%.0s' {1..40})" >/dev/null 2>&1; then
    echo 'stale head was accepted' >&2; exit 1
fi
printf 'ok: final PR reconciliation\n'
