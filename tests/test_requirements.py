import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "bin" / "omacchiato-requirements"


class Requirements(unittest.TestCase):
    def run_with(self, conf, version="1.2.3"):
        with tempfile.TemporaryDirectory() as d:
            tool = Path(d, "omacchiato-test-tool")
            tool.write_text("#!/bin/sh\necho 'omacchiato-test-tool %s'\n" % version)
            tool.chmod(0o755)
            Path(d, "requirements.conf").write_text(conf)
            env = dict(os.environ, PATH=d + os.pathsep + os.environ["PATH"])
            r = subprocess.run([str(SCRIPT), str(Path(d, "requirements.conf"))],
                               env=env, capture_output=True, text=True)
            return r.returncode, r.stdout

    def test_a_tool_that_is_new_enough_passes(self):
        code, out = self.run_with("omacchiato-test-tool  1.2.0  formula:tool\n")
        self.assertEqual(code, 0)
        self.assertIn("omacchiato-test-tool 1.2.3: ok (needs 1.2.0)", out)

    def test_a_tool_that_is_too_old_fails(self):
        code, out = self.run_with("omacchiato-test-tool  1.10.0  formula:tool\n")
        self.assertEqual(code, 1)
        self.assertIn("brew upgrade tool)", out)
        self.assertNotIn("--cask", out)

    def test_a_missing_tool_is_skipped(self):
        code, out = self.run_with("omacchiato-no-such-tool  1.0  formula:tool\n")
        self.assertEqual((code, out), (0, ""))

    def test_a_missing_app_still_fails(self):
        code, out = self.run_with("OmacchiatoNoSuchApp  1.0  nosuchcask\n")
        self.assertEqual(code, 1)
        self.assertIn("brew install --cask nosuchcask", out)


if __name__ == "__main__":
    unittest.main()
