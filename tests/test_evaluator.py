"""Publication guard behavior against real Git and acceptance-criteria inputs."""
import json
import os
from pathlib import Path
import subprocess
import re
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/evaluator.py"


class EvaluatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.memory = Path(self.temp.name) / "memory"
        self.repo.mkdir()
        self.memory.mkdir()
        self.git("init", "-q")
        (self.repo / "app.txt").write_text("original\n")
        self.git("add", ".")
        # Commit identity is command scoped; never override repository identity.
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "commit", "-qm", "base")
        self.base = self.git("rev-parse", "HEAD").strip()
        (self.memory / "ticket.md").write_text(
            "# Ticket\n## Acceptance Criteria\n- Export CSV\n- Preserve labels\n")
        (self.memory / "qa.md").write_text("CSV check passed\n")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True)

    def run_guard(self, command, *args):
        self.assertTrue(SCRIPT.exists(), "evaluator publication guard is missing")
        return subprocess.run(["python3", str(SCRIPT), command,
                               "--workspace", str(self.repo), "--memory", str(self.memory),
                               "--base", self.base, *args], text=True, capture_output=True)

    def snapshot(self):
        result = self.run_guard("snapshot")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def artifact(self, statuses=("PASS", "PASS")):
        snapshot = self.snapshot()
        items = [dict(item, verdict=status, evidence="qa.md: CSV check passed",
                      reason="No observable behavior" if status == "SKIP" else "Mismatch")
                 for item, status in zip(snapshot["criteria"], statuses)]
        verdict = "FAIL" if "FAIL" in statuses else "PASS" if "PASS" in statuses else "SKIP"
        data = {"schema_version": 1, "fingerprint": snapshot["fingerprint"],
                "verdict": verdict, "items": items}
        self.write_artifact(data)
        return data

    def write_artifact(self, data):
        (self.memory / "evaluator.md").write_text(
            "# Evaluator\n```json\n" + json.dumps(data) + "\n```\n")

    def test_complete_pass_allows_publication(self):
        self.artifact()
        self.assertEqual(self.run_guard("check").returncode, 0)

    def test_failed_item_blocks_even_if_overall_claims_pass(self):
        data = self.artifact(("FAIL", "PASS"))
        self.assertEqual(self.run_guard("check").returncode, 1)
        data["verdict"] = "PASS"
        self.write_artifact(data)
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_all_unverifiable_skips_with_reasons(self):
        data = self.artifact(("SKIP", "SKIP"))
        self.assertEqual(self.run_guard("check").returncode, 0)
        data["items"][0]["reason"] = ""
        self.write_artifact(data)
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_missing_item_and_missing_evidence_block(self):
        data = self.artifact()
        data["items"].pop()
        self.write_artifact(data)
        self.assertNotEqual(self.run_guard("check").returncode, 0)
        data = self.artifact()
        data["items"][0]["evidence"] = ""
        self.write_artifact(data)
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_criterion_cannot_be_substituted(self):
        data = self.artifact()
        data["items"][0]["criterion"] = "Easier requirement"
        self.write_artifact(data)
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_changed_source_invalidates_verdict(self):
        self.artifact()
        (self.repo / "app.txt").write_text("changed\n")
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_untracked_source_invalidates_verdict(self):
        self.artifact()
        (self.repo / "new.txt").write_text("new\n")
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_changed_criteria_and_qa_invalidate_verdict(self):
        for name in ("ticket.md", "qa.md", "brainstorm.md", "local-testing.md"):
            with self.subTest(name=name):
                self.artifact()
                (self.memory / name).write_text("Changed input\n")
                self.assertNotEqual(self.run_guard("check").returncode, 0)
                if name == "ticket.md":
                    (self.memory / name).write_text(
                        "## Acceptance Criteria\n- Export CSV\n- Preserve labels\n")

    def test_evaluator_and_overview_do_not_invalidate_their_own_snapshot(self):
        self.artifact()
        (self.memory / "overview.md").write_text("step: evaluator\n")
        self.assertEqual(self.run_guard("check").returncode, 0)

    def test_memory_inside_repository_is_excluded_from_source_snapshot(self):
        self.memory = self.repo / "state"
        self.memory.mkdir()
        (self.memory / "ticket.md").write_text("## Acceptance Criteria\n- Export CSV\n- Preserve labels\n")
        self.artifact()
        (self.memory / "evaluator-input.json").write_text("temporary snapshot\n")
        (self.memory / "overview.md").write_text("step: evaluator\n")
        self.assertEqual(self.run_guard("check").returncode, 0)

    def test_missing_malformed_and_empty_criteria_block(self):
        self.assertNotEqual(self.run_guard("check").returncode, 0)
        (self.memory / "evaluator.md").write_text("Verdict: PASS\n")
        self.assertNotEqual(self.run_guard("check").returncode, 0)
        (self.memory / "ticket.md").write_text("# No AC\n")
        self.assertNotEqual(self.run_guard("snapshot").returncode, 0)

    def test_refinement_adds_to_original_criteria(self):
        (self.memory / "brainstorm.md").write_text(
            "## Acceptance Criteria\n- Include headers\n")
        self.assertEqual([x["criterion"] for x in self.snapshot()["criteria"]],
                         ["Export CSV", "Preserve labels", "Include headers"])

    def test_nested_heading_criterion_cannot_disappear_from_verdict(self):
        (self.memory / "ticket.md").write_text(
            "## Acceptance Criteria\n- Export CSV\n### Reject unauthorized exports\n"
            "## Notes\nNot a criterion\n")
        snapshot = self.snapshot()
        self.assertEqual([x["criterion"] for x in snapshot["criteria"]],
                         ["Export CSV", "Reject unauthorized exports"])
        data = self.artifact()
        data["items"].pop()
        self.write_artifact(data)
        self.assertNotEqual(self.run_guard("check").returncode, 0)

    def test_waiver_is_explicit_reasoned_and_input_bound(self):
        data = self.artifact(("FAIL", "PASS"))
        args = ("--waiver-fingerprint", data["fingerprint"], "--waiver-reason", "User accepts delay")
        result = self.run_guard("check", *args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)["waived"])
        self.assertNotEqual(self.run_guard("check", "--waiver-fingerprint",
                                          data["fingerprint"], "--waiver-reason", "").returncode, 0)
        (self.repo / "app.txt").write_text("new source\n")
        self.assertNotEqual(self.run_guard("check", *args).returncode, 0)


class EvaluatorRoutingTests(unittest.TestCase):
    def route(self, config, pending=False, headless=False):
        root = SCRIPT.parents[1]
        document = (root / "skills/n1-start/procedures/evaluator.md").read_text()
        snippet = re.findall(r"```bash\n(.*?)```", document, re.S)[0]
        snippet = snippet.replace("source ~/.n1-codex/preamble.sh", "")
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            (state / "config.json").write_text(json.dumps(config))
            memory = state / "memory/T-1"
            memory.mkdir(parents=True)
            (memory / "overview.md").write_text(
                "---\nevaluator_pending: " + str(pending).lower() + "\n---\n")
            env = dict(os.environ, N1_HOME=temporary, ID="T-1", N1_HEADLESS="1" if headless else "")
            env.pop("N1_AUTONOMY_PRESET", None)
            script = 'source "$1/lib/config.sh"\nsource "$1/lib/frontmatter.sh"\n' + snippet
            script += '\nprintf "%s" "${EVALUATOR_RUN:-unset}"\n'
            return subprocess.check_output(["bash", "-c", script, "gate", str(root)], env=env, text=True)

    def test_pending_headless_failure_keeps_gate_on_during_interactive_resume(self):
        config = {"autonomy": {"mode": "interactive"}, "localTesting": {"evaluatorGate": True}}
        self.assertEqual(self.route(config, headless=True), "true")
        self.assertEqual(self.route(config, pending=True), "true")
        self.assertEqual(self.route(config), "false")

    def test_gate_defaults_off_and_is_independent_of_live_testing(self):
        self.assertEqual(self.route({}), "false")
        self.assertEqual(self.route({"localTesting": {"enabled": False, "evaluatorGate": True}}), "true")


if __name__ == "__main__":
    unittest.main()
