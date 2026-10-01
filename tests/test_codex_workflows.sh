#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0

check() { grep -RqlE "$2" "$ROOT/$1" && echo "PASS: $3" || { echo "FAIL: $3"; FAIL=1; }; }
absent() { ! grep -RqlE "$2" "$ROOT/$1" && echo "PASS: $3" || { echo "FAIL: $3"; FAIL=1; }; }

check skills 'source ~/\.n1-codex/preamble\.sh' 'skills use isolated Codex preamble'
absent skills 'source ~/\.n1/preamble\.sh' 'skills do not use Claude state preamble'
absent skills 'model: (sonnet|opus|haiku)' 'skills do not select Claude models'
absent agents 'model: (sonnet|opus|haiku)' 'personas do not select Claude models'
absent skills 'CLAUDE\.md' 'skills use AGENTS.md'
absent agents 'CLAUDE\.md' 'personas use AGENTS.md'
check skills/n1-init 'AGENTS\.md' 'init creates or enriches AGENTS.md'
check skills/n1-init '~/.n1/|\$N1_HOME' 'init uses shared project state'
absent skills/n1-init 'cp -r|rm -rf|Migration Flow|with_entries.*claude-code' 'init never migrates state or collapses host model overrides'
check skills/n1-init 'install-agents\.py' 'init installs project-scoped Codex profiles'
check skills/n1-queue 'unsupported.*Codex|Codex.*unsupported' 'queue clearly refuses Codex execution'
check skills/n1-pr/steps/03-codex-review.md 'Skip this step entirely' 'extra Codex review is disabled'
absent skills/n1-pr/steps/03-codex-review.md 'codex exec' 'post-PR path never launches duplicate Codex review'

python3 - "$ROOT" <<'PY' || FAIL=1
import pathlib, re, subprocess, sys
root = pathlib.Path(sys.argv[1])
count = 0
for path in (root / 'skills').rglob('*.md'):
    content = path.read_text()
    snippets = [(match.group(0), *match.groups()) for match in re.finditer(r"^IFS=\$'\\t' read -r (\w+) (\w+) < <\(n1_resolve_agent [^\n]*\)$", content, re.M)]
    snippets += [(match.group(0), *match.groups()) for match in re.finditer(r"^AGENT_CONFIG=\$\(n1_resolve_agent [^\n]*\)\n(\w+)=\$\{AGENT_CONFIG%%\$'\\t'\*\}\n(\w+)=\$\{AGENT_CONFIG#\*\$'\\t'\}", content, re.M)]
    for snippet, model, effort in snippets:
        for pair, want in [('\thigh', '|high'), ('gpt-6.1-sol\thigh', 'gpt-6.1-sol|high'), ('\t', '|')]:
            script = 'n1_resolve_agent() { printf "%s" "$PAIR"; };\n' + snippet + f'\nprintf "%s|%s" "${model}" "${effort}"'
            result = subprocess.run(['bash', '-c', script], env={'PAIR': pair, 'PATH': '/usr/bin:/bin'}, capture_output=True, text=True)
            if result.returncode or result.stdout != want:
                raise SystemExit(f'FAIL: {path.relative_to(root)} corrupts inherited model/effort: {result.stdout!r}')
        count += 1
assert count, 'no workflow model/effort splits checked'
print(f'PASS: {count} workflow model/effort splits preserve inheritance')

# Run the init merge instructions against shared host settings, not a copied implementation.
import json, tempfile
document = (root / 'skills/n1-init/steps/13-write-config.md').read_text()
merge = next(body for body in re.findall(r'```bash\n(.*?)```', document, re.S) if "jq -s '.[0] * .[1]'" in body)
merge = '\n'.join(line for line in merge.splitlines() if not line.startswith('source '))
with tempfile.TemporaryDirectory() as temporary:
    state = pathlib.Path(temporary)
    original = {'models': {'developer': 'sonnet', 'security-reviewer': {'claude-code': 'opus', 'codex': 'gpt-6.1-sol'}}, 'git': {'defaultBranch': 'main', 'prMode': 'draft'}, 'customHost': {'preserve': True}}
    (state / 'config.json').write_text(json.dumps(original))
    changes = state / 'changes.json'
    changes.write_text('{"git":{"prMode":"ready"}}')
    subprocess.run(['bash', '-e', '-c', merge], env={'N1_HOME': temporary, 'CHANGES': str(changes), 'PATH': '/usr/bin:/bin'}, check=True)
    actual = json.loads((state / 'config.json').read_text())
    expected = dict(original, git={'defaultBranch': 'main', 'prMode': 'ready'})
    assert actual == expected, actual
print('PASS: init recursive merge preserves shared host and unknown config keys')
PY

exit "$FAIL"
