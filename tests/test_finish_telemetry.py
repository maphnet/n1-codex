import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FinishTelemetry(unittest.TestCase):
    def test_merge_and_retry_with_only_merged_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, N1_ROOT=str(ROOT))
            command = 'source "$N1_ROOT/lib/telemetry.sh"; n1_close_run_telemetry "$1" run v1 T1 pr_created passed skipped "disabled grant" simple story'
            def close():
                return subprocess.run(['bash', '-c', command, 'test', tmp], env=env, capture_output=True, text=True)
            first = close()
            self.assertEqual(first.returncode, 0, first.stderr)
            merged = Path(tmp) / 'runs/run.jsonl'
            row = json.loads(merged.read_text())
            for key, value in dict(run_id='run', final_outcome='pr_created', ci_state='passed', finish_state='skipped', finish_reason='disabled grant').items():
                self.assertEqual(row[key], value)
            self.assertTrue(row['completed_at'])
            before = merged.read_bytes()
            (Path(tmp) / 'raw/steps/run.jsonl').unlink()
            second = close()
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(merged.read_bytes(), before)
            self.assertFalse((Path(tmp) / 'raw/steps/run.jsonl').exists())
            row['ci_state'] = 'failed'
            merged.write_text(json.dumps(row) + '\n')
            conflicting = merged.read_bytes()
            self.assertNotEqual(close().returncode, 0)
            self.assertEqual(merged.read_bytes(), conflicting)
            self.assertFalse((Path(tmp) / 'raw/steps/run.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
