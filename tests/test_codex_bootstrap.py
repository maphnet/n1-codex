"""Codex startup must leave Claude's bootstrap intact and install confined personas."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Bootstrap(unittest.TestCase):
    def test_claude_model_never_rewrites_codex_spawn(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Path(temp) / 'config.json'
            config.write_text(json.dumps({'models': {'developer': 'claude-sonnet-4-6'}}))
            result = subprocess.run(['python3', str(ROOT / 'hooks/enforce-agent-policy.py'),
                                     str(config), str(ROOT)], text=True, capture_output=True,
                                    input=json.dumps({'tool_name': 'spawn_agent',
                                        'tool_input': {'agent_type': 'n1-developer'}}))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')

    def test_session_and_personas(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            (home / '.n1').mkdir()
            sentinel = home / '.n1/preamble.sh'
            sentinel.write_text('CLAUDE SENTINEL')
            env = {**os.environ, 'HOME': temp, 'N1_HOME': str(home / 'project'),
                   'CODEX_THREAD_ID': 'codex-test'}
            env.pop('N1_STATE_DIR', None)
            result = subprocess.run(['bash', str(ROOT / 'hooks/session-start.sh')],
                                    input=json.dumps({'source': 'startup', 'session_id': 'codex-test', 'cwd': temp}),
                                    text=True, capture_output=True, env=env, cwd=temp)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sentinel.read_text(), 'CLAUDE SENTINEL')
            context = json.loads(result.stdout)['hookSpecificOutput']['additionalContext']
            self.assertIn('Codex', context)
            self.assertNotIn('AskUserQuestion', context)
            self.assertTrue((home / '.n1-codex/sessions/codex-test.preamble.sh').is_file())
            install = subprocess.run(['python3', str(ROOT / 'scripts/install-agents.py'), temp],
                                     capture_output=True, text=True, env=env)
            self.assertEqual(install.returncode, 0, install.stderr)
            reviewer = tomllib.loads((home / '.codex/agents/n1-code-reviewer.toml').read_text())
            self.assertEqual(reviewer['sandbox_mode'], 'read-only')
            self.assertNotIn('model', reviewer)
            self.assertIn('developer_instructions', reviewer)
            self.assertFalse((home / '.codex/agents/n1-research-standards.toml').exists())
            protected = home / '.codex/agents/n1-code-reviewer.toml'
            protected.write_text('user-owned profile')
            retry = subprocess.run(['python3', str(ROOT / 'scripts/install-agents.py'), temp],
                                   capture_output=True, text=True, env=env)
            self.assertNotEqual(retry.returncode, 0)
            self.assertEqual(protected.read_text(), 'user-owned profile')

    def test_unsupported_operations_leave_shared_files_untouched(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / 'rules-deny.sh'
            target.write_text('CLAUDE HOOK')
            result = subprocess.run(['bash', '-c',
                'source "$1/lib/rules.sh"; n1_generate_deny_hook "$2" "$3"',
                '_', str(ROOT), temp, str(target)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(target.read_text(), 'CLAUDE HOOK')
            queue = subprocess.run(['bash', str(ROOT / 'scripts/n1-queue-run.sh'), str(target)],
                                   capture_output=True, text=True)
            self.assertEqual(queue.returncode, 2)
            self.assertEqual(target.read_text(), 'CLAUDE HOOK')


if __name__ == '__main__':
    unittest.main()
