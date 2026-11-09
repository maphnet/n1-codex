import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/n1-reviewed-head.py'
HEAD = 'a' * 40


class ReviewedHeadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        (self.root / 'bin').mkdir()
        gh = self.root / 'bin/gh'
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['N1_HOME'])
args = sys.argv[1:]
with (root / 'calls').open('a') as out: out.write(json.dumps(args)+'\\n')
if args[:2] == ['pr', 'merge']:
    if (root/'reject').exists(): sys.exit(1)
    (root/'called-merge').touch()
    sys.exit(0)
if args[0] != 'api': sys.exit(1)
if args[1] == 'graphql': name = 'review'
elif '/check-runs?' in args[1]: name = 'checks'
elif '/status?' in args[1]: name = 'status'
else: name = 'merged' if (root/'called-merge').exists() else 'pr'
print((root/name).read_text())
''')
        gh.chmod(0o755)
        git = self.root / 'bin/git'
        git.write_text('#!/bin/sh\ncase "$1" in status) exit 0;; rev-parse) printf "%s\\n" "' + HEAD + '";; esac\n')
        git.chmod(0o755)
        self.env = dict(os.environ, N1_HOME=str(self.root), PATH=str(self.root / 'bin') + ':' + os.environ['PATH'])
        self.env.pop('N1_QUEUE_RUN_ID', None)
        self.write('config.json', {'autonomy': {'fullAuto': True}, 'finishWork': {'mergeOnFinish': True}})
        self.write('pr', {'number': 4, 'state': 'open', 'base': {'repo': {'full_name': 'o/r'}, 'ref': 'main'}, 'head': {'repo': {'full_name': 'o/r'}, 'ref': 'feature', 'sha': HEAD}})
        self.write('merged', {'merged': True, 'merge_commit_sha': 'b' * 40})
        self.write('checks', {'total_count': 0, 'check_runs': []})
        self.write('status', {'statuses': []})
        self.write('review', {'data': {'repository': {'pullRequest': {'reviewThreads': {'pageInfo': {'hasNextPage': False}, 'nodes': []}, 'latestOpinionatedReviews': {'pageInfo': {'hasNextPage': False}, 'nodes': []}}}}})
        self.evidence = {'repository': 'o/r', 'branch': 'feature', 'base': 'main', 'head': HEAD, 'run_id': 'run', 'verdict': 'pass', 'pr': 4}
        self.write('memory/T/reviewed-head.json', self.evidence)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def run_guard(self, action='merge', *args):
        if not args:
            args = ('4', 'squash', 'passed') if action in ('merge', 'interactive-merge') else ('4',)
        return subprocess.run(['python3', str(SCRIPT), action, 'T', 'o/r', 'feature', 'run', *args], env=self.env, capture_output=True, text=True)

    def test_success_and_exact_head(self):
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(x) for x in (self.root/'calls').read_text().splitlines()]
        merge = next(x for x in calls if x[:2] == ['pr', 'merge'])
        self.assertIn('--match-head-commit', merge)
        self.assertEqual(merge[merge.index('--match-head-commit') + 1], HEAD)
        self.assertNotIn('--auto', merge)

    def test_bad_evidence(self):
        for key, value in [('repository', 'x/y'), ('branch', 'other'), ('run_id', 'old'), ('pr', 5), ('head', 'c' * 40)]:
            with self.subTest(key=key):
                self.write('memory/T/reviewed-head.json', dict(self.evidence, **{key: value}))
                self.assertNotEqual(self.run_guard().returncode, 0)
        (self.root/'memory/T/reviewed-head.json').write_text('{')
        self.assertNotEqual(self.run_guard().returncode, 0)
        (self.root/'memory/T/reviewed-head.json').unlink()
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_checks_reviews_and_merge_fail_closed(self):
        for name, value in [('checks', {'total_count': 1, 'check_runs': [{'status': 'in_progress', 'conclusion': None}]}), ('checks', {'total_count': 1, 'check_runs': [{'status': 'completed', 'conclusion': 'failure'}]}), ('review', {'errors': ['failure']}), ('review', {'data': {'repository': {'pullRequest': {'reviewThreads': {'pageInfo': {'hasNextPage': False}, 'nodes': [{'isResolved': False}]}, 'latestOpinionatedReviews': {'pageInfo': {'hasNextPage': False}, 'nodes': []}}}}})]:
            with self.subTest(value=value):
                old = (self.root/name).read_text()
                self.write(name, value)
                self.assertNotEqual(self.run_guard().returncode, 0)
                (self.root/name).write_text(old)
        (self.root/'reject').touch()
        self.assertNotEqual(self.run_guard().returncode, 0)
        (self.root/'reject').unlink()
        self.write('merged', {'merged': False})
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_attach_and_queue_denial(self):
        self.write('memory/T/reviewed-head.json', {k: v for k, v in self.evidence.items() if k != 'pr'})
        self.assertEqual(self.run_guard('attach').returncode, 0)
        self.env['N1_QUEUE_RUN_ID'] = 'queue'
        self.assertNotEqual(self.run_guard().returncode, 0)
        del self.env['N1_QUEUE_RUN_ID']
        self.write('queue/Q/state.json', {'version': 1, 'queue_id': 'Q', 'repo': '/repo', 'base_ref': 'main', 'default_ref': 'main', 'origin_repo': 'github.com/o/r', 'integration_ref': 'feature', 'integration_sha': HEAD})
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_record_needs_full_passing_gates_and_current_head(self):
        path = self.root/'memory/T/reviewed-head.json'
        for args in [(HEAD, 'main', 'NARROW', 'pass', 'pass'), (HEAD, 'main', 'FULL', 'fail', 'pass'), (HEAD, 'main', 'FULL', 'pass', 'fail'), ('c'*40, 'main', 'FULL', 'pass', 'pass')]:
            path.unlink(missing_ok=True)
            self.assertNotEqual(self.run_guard('record', *args).returncode, 0)
            self.assertFalse(path.exists())
        self.assertEqual(self.run_guard('record', HEAD, 'main', 'FULL', 'pass', 'pass').returncode, 0)
        self.assertEqual(json.loads(path.read_text())['head'], HEAD)

    def test_attach_requires_current_remote_and_api_errors_stop(self):
        self.write('pr', {'number': 4, 'state': 'open', 'base': {'repo': {'full_name': 'o/r'}}, 'head': {'repo': {'full_name': 'o/r'}, 'ref': 'feature', 'sha': 'c'*40}})
        self.assertNotEqual(self.run_guard('attach').returncode, 0)
        (self.root/'pr').unlink()
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_interactive_approval_allows_merge_without_unattended_grants(self):
        self.write('config.json', {'autonomy': {'fullAuto': False}, 'finishWork': {'mergeOnFinish': False}})
        self.env['N1_INTERACTIVE_APPROVED'] = 'yes'
        result = self.run_guard('interactive-merge')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_retarget_headless_and_incomplete_queue_stop(self):
        pr = json.loads((self.root/'pr').read_text())
        pr['base']['ref'] = 'other'
        self.write('pr', pr)
        self.assertNotEqual(self.run_guard('attach').returncode, 0)
        self.assertNotEqual(self.run_guard().returncode, 0)
        pr['base']['ref'] = 'main'
        self.write('pr', pr)
        self.env.update(N1_INTERACTIVE_APPROVED='yes', N1_HEADLESS='1')
        self.assertNotEqual(self.run_guard('interactive-merge').returncode, 0)
        self.env.pop('N1_HEADLESS')
        self.write('queue/Q/state.json', {'origin_repo': 'github.com/o/r'})
        self.assertNotEqual(self.run_guard().returncode, 0)
        queue = {'version': 1, 'queue_id': 'Q', 'repo': '/repo', 'base_ref': 'main', 'default_ref': 'main', 'origin_repo': 'github.com/o/r', 'integration_sha': None}
        for invalid in ('', 42, [], {}):
            self.write('queue/Q/state.json', dict(queue, integration_ref=invalid))
            self.assertNotEqual(self.run_guard().returncode, 0)
        self.write('queue/Q/state.json', dict(queue, integration_ref=None))
        self.assertEqual(self.run_guard().returncode, 0)

    def test_standalone_review_evidence_then_push_and_attach_without_memory(self):
        workflow = (SCRIPT.parent.parent / 'skills/n1-ci/steps/02-fix.md').read_text()
        block = workflow.split('Only after all required lanes pass')[1].split('```bash\n')[1].split('```')[0]
        self.env.update(N1_ROOT=str(SCRIPT.parent.parent), EVIDENCE_ID='CI-4-run', REVIEW_REPO='o/r',
                        REVIEW_BRANCH='feature', REVIEW_HEAD=HEAD, REVIEW_BASE='main',
                        PR_NUMBER='4', SECURITY_VERDICT='pass', N1_RUN_ID='run')
        result = subprocess.run(['bash', '-c', block], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        evidence = json.loads((self.root/'memory/CI-4-run/reviewed-head.json').read_text())
        self.assertEqual((evidence['head'], evidence['base'], evidence['pr']), (HEAD, 'main', 4))
        self.assertFalse((self.root/'memory/CI-4-run/implementation.md').exists())

    def test_merged_report_reads_finish_url_after_pending_cleanup(self):
        workflow = (SCRIPT.parent.parent / 'skills/n1-start/procedures/finalize.md').read_text()
        block = workflow.split('For a confirmed merge')[1].split('```bash\n')[1].split('```')[0]
        path = self.root/'memory/T/overview.md'
        path.write_text('## Finish\n- **Merged:** abc\npr_url: https://example.test/pr/4\n')
        self.env['ID'] = 'T'
        result = subprocess.run(['bash', '-c', block + '\nprintf "%s" "$PR_URL"'], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.stdout, 'https://example.test/pr/4')


if __name__ == '__main__':
    unittest.main()
