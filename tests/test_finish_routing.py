import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text()


class FinishRouting(unittest.TestCase):
    def test_init_and_architecture_do_not_describe_legacy_authority(self):
        init = read('skills/n1-init/steps/09-finish-release.md').split('## Delivery (SSH deploy)')[0]
        architecture = read('references/architecture.md')
        self.assertNotIn('"enabled": true', init)
        self.assertNotIn('gh pr merge --auto', init)
        self.assertNotIn('gh pr merge --auto', architecture)
        self.assertNotIn('n1-ci chaining', architecture)

    def test_start_owns_routing(self):
        pr = read('skills/n1-start/steps/pr.md')
        ci = read('skills/n1-start/steps/ci.md')
        finish = read('skills/n1-start/steps/finish.md')
        self.assertNotIn('stop after n1:n1-pr', pr)
        self.assertIn('continue to CI', pr)
        for state in ('passed', 'no-checks', 'disabled', 'failed', 'escalated'):
            self.assertIn(state, ci)
        self.assertIn('successful', ci)
        self.assertIn('API failure', ci)
        self.assertIn('passed|no-checks|disabled', finish)
        self.assertIn('open created PR', finish)
        self.assertIn('never automatically local merge', finish)

    def test_monitor_returns_without_chaining(self):
        monitor = read('skills/n1-ci/steps/01-monitor.md')
        self.assertNotIn('Finish chaining', monitor)
        self.assertIn('never invokes n1:n1-finish', monitor)
        self.assertIn('successful', monitor)
        self.assertIn('API failure', monitor)
        self.assertIn('ci_state: disabled', monitor)

    def test_finalization_preserves_truth_and_closes_once(self):
        final = read('skills/n1-start/procedures/finalize.md')
        self.assertNotIn('all checkboxes checked', final)
        for field in ('ci_state', 'finish_state', 'finish_reason', 'final_outcome'):
            self.assertIn(field, final)
        for phrase in ('uncompleted checkboxes', '## Pending', 'confirmed', 'existing envelope_close', 'pr_created', 'merged'):
            self.assertIn(phrase, final)
        cleanup = read('skills/n1-finish/steps/06-cleanup.md')
        self.assertIn('n1-start owns finalization', cleanup)


if __name__ == '__main__':
    unittest.main()
