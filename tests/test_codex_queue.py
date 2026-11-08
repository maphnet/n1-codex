"""Bounded queue operations preserve identity and reserve only verified work."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'scripts/n1-queue-run.sh'


class Queue(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {**os.environ, 'N1_HOME': str(self.root / 'home')}
        self.repo = self.root / 'repo'
        self.git('init', '-q', '-b', 'main', str(self.repo), cwd=self.root)
        self.git('-c', 'user.name=Queue Test', '-c', 'user.email=test@example.test',
                 'commit', '-q', '--allow-empty', '-m', 'base')
        self.sha = self.git('rev-parse', 'HEAD')
        self.git('clone', '-q', '--bare', str(self.repo), str(self.root / 'remote'))
        self.git('remote', 'add', 'origin', str(self.root / 'remote'))

    def git(self, *args, cwd=None):
        return subprocess.check_output(['git', *args], cwd=cwd or self.repo,
                                       text=True, stderr=subprocess.PIPE).strip()

    def call(self, *args, ok=True):
        result = subprocess.run(['bash', str(RUNNER), *map(str, args)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def init(self, *tickets):
        return self.call('init', 'queue-1', self.repo, 'main', *tickets)

    def transition(self, revision, payload, ok=True):
        path = self.root / ('change-' + str(revision) + '.json')
        path.write_text(json.dumps(payload))
        return self.call('transition', 'queue-1', revision, path, ok=ok)

    def proof(self, ticket, blockers=None, lookup='verified'):
        return {'ticket': ticket, 'reason': 'tracker snapshot', 'blocker_snapshot': {
            'base_sha': self.sha, 'lookup': lookup, 'blockers': blockers or []}}

    def test_invalid_ids_and_duplicates_create_no_state(self):
        for queue, tickets in [('bad/id', ['NC-1']), ('valid', []),
                               ('valid', ['NC-1', 'NC-1']), ('valid', ['../bad'])]:
            self.call('init', queue, self.repo, 'main', *tickets, ok=False)
        self.assertFalse((self.root / 'home/queue/valid/state.json').exists())

    def test_init_never_selects_and_status_is_read_only(self):
        state = self.init('NC-2', 'NC-1')
        self.assertEqual([t['ticket'] for t in state['tickets']], ['NC-2', 'NC-1'])
        path = self.root / 'home/queue/queue-1/state.json'
        before = path.read_bytes()
        self.assertEqual(self.call('status', 'queue-1'), state)
        self.assertEqual(path.read_bytes(), before)
        result = self.call('select', 'queue-1')
        self.assertIsNone(result['selected'])
        self.assertTrue(result['reasons'])

    def test_ordered_selection_and_no_second_reservation(self):
        self.init('NC-2', 'NC-1')
        self.transition(0, self.proof('NC-2'))
        self.transition(1, self.proof('NC-1'))
        result = self.call('select', 'queue-1')
        self.assertEqual(result['selected'], 'NC-2')
        self.assertEqual(result['state']['tickets'][0]['status'], 'launching')
        self.assertIsNone(self.call('select', 'queue-1')['selected'])

    def test_unknown_blocker_blocks_only_its_ticket(self):
        self.init('NC-1', 'NC-2')
        self.transition(0, self.proof('NC-1', [{'ticket': 'EXT-1'}]))
        self.transition(1, self.proof('NC-2'))
        result = self.call('select', 'queue-1')
        self.assertEqual(result['selected'], 'NC-2')
        self.assertEqual(result['state']['tickets'][0]['status'], 'blocked')
        self.assertEqual(result['state']['tickets'][0]['blocker_snapshot']['blockers'],
                         [{'ticket': 'EXT-1'}])

    def test_merged_commit_must_be_in_current_base(self):
        self.init('NC-1')
        self.git('-c', 'user.name=Queue Test', '-c', 'user.email=test@example.test',
                 'commit', '-q', '--allow-empty', '-m', 'not yet pushed')
        unmerged = self.git('rev-parse', 'HEAD')
        self.transition(0, self.proof('NC-1', [{'ticket': 'EXT-1',
                        'merged_sha': unmerged, 'verified': True}]))
        self.assertIsNone(self.call('select', 'queue-1')['selected'])
        state = self.call('status', 'queue-1')
        self.transition(state['revision'], self.proof('NC-1', [{'ticket': 'EXT-1',
                        'merged_sha': self.sha, 'verified': True}]))
        self.assertEqual(self.call('select', 'queue-1')['selected'], 'NC-1')

    def test_changed_base_requires_refreshed_tracker_proof(self):
        self.init('NC-1')
        self.transition(0, self.proof('NC-1'))
        self.git('-c', 'user.name=Queue Test', '-c', 'user.email=test@example.test',
                 'commit', '-q', '--allow-empty', '-m', 'new base')
        self.git('push', '-q', 'origin', 'main')
        self.assertIsNone(self.call('select', 'queue-1')['selected'])

    def test_base_race_does_not_persist_a_reservation(self):
        self.init('NC-1')
        self.transition(0, self.proof('NC-1'))
        wrapper = self.root / 'bin'
        wrapper.mkdir()
        real_git = subprocess.check_output(['which', 'git'], text=True).strip()
        fake_git = wrapper / 'git'
        fake_git.write_text('#!/bin/sh\n'
                            'case "$*" in *ls-remote*) printf "%040d\\trefs/heads/main\\n" 0; exit 0;; esac\n'
                            'exec ' + real_git + ' "$@"\n')
        fake_git.chmod(0o755)
        self.env['PATH'] = str(wrapper) + os.pathsep + os.environ['PATH']
        self.call('select', 'queue-1', ok=False)
        state = self.call('status', 'queue-1')
        self.assertEqual(state['revision'], 1)
        self.assertIsNone(state['intent'])
        self.assertEqual(state['tickets'][0]['status'], 'pending')

    def test_failed_tracker_refresh_preserves_known_blockers(self):
        self.init('NC-1')
        blockers = [{'ticket': 'EXT-1', 'verified': True, 'merged_sha': self.sha}]
        self.transition(0, self.proof('NC-1', blockers))
        self.transition(1, self.proof('NC-1', lookup='unknown'))
        result = self.call('select', 'queue-1')
        self.assertIsNone(result['selected'])
        self.assertEqual(result['state']['tickets'][0]['blocker_snapshot']['blockers'], blockers)

    def test_concurrent_selectors_reserve_only_one_ticket(self):
        self.init('NC-1', 'NC-2')
        self.transition(0, self.proof('NC-1'))
        self.transition(1, self.proof('NC-2'))
        def select(_):
            result = subprocess.run(['bash', str(RUNNER), 'select', 'queue-1'],
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return json.loads(result.stdout)['selected']
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(select, range(2)))
        self.assertCountEqual(results, ['NC-1', None])

    def test_revision_conflict_and_identity_replacement_rejected(self):
        self.init('NC-1')
        self.transition(0, self.proof('NC-1'))
        self.transition(0, self.proof('NC-1'), ok=False)
        self.transition(1, {'repo': '/other', 'reason': 'replace'}, ok=False)
        self.transition(1, {'ticket': 'NC-1', 'evidence': [], 'reason': 'erase'}, ok=False)
        self.transition(1, {'ticket': 'NC-1', 'status': 'succeeded',
                            'reason': 'unsupported shortcut'}, ok=False)
        self.assertEqual(self.call('status', 'queue-1')['revision'], 1)

    def test_concurrent_writers_commit_exactly_once(self):
        self.init('NC-1')
        path = self.root / 'change.json'
        path.write_text(json.dumps(self.proof('NC-1')))
        def writer(_):
            return subprocess.run(['bash', str(RUNNER), 'transition', 'queue-1', '0',
                                   str(path)], env=self.env, capture_output=True).returncode
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(writer, range(2))), [0, 2])
        state = self.call('status', 'queue-1')
        self.assertEqual(state['revision'], 1)
        self.assertEqual(len(state['events']), 2)

    def test_corrupt_or_unknown_state_never_reset(self):
        self.init('NC-1')
        path = self.root / 'home/queue/queue-1/state.json'
        for content in ['broken', '{"version":999}']:
            path.write_text(content)
            self.call('status', 'queue-1', ok=False)
            self.call('init', 'queue-1', self.repo, 'main', 'NC-1', ok=False)
            self.assertEqual(path.read_text(), content)
