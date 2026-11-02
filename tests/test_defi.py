import os
import subprocess
import tempfile
import unittest

WRAPPER = os.path.join(os.path.dirname(__file__), "..", "bin", "omacchiato-defi")


def fake_defi(path, answer):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("#!/bin/sh\necho %s \"$@\"\n" % answer)
    os.chmod(path, 0o755)


@unittest.skipIf(os.path.isdir("/Applications/Defi.app"), "a real Defi is in /Applications")
class DefiWrapper(unittest.TestCase):
    def run_wrapper(self, home, path):
        env = {"HOME": home, "PATH": path}
        return subprocess.run(["/bin/bash", WRAPPER, "status"], env=env, capture_output=True, text=True)

    def test_finds_the_app_in_the_home_applications_folder(self):
        with tempfile.TemporaryDirectory() as home:
            fake_defi(os.path.join(home, "Applications/Defi.app/Contents/MacOS/defi"), "home")
            self.assertEqual(self.run_wrapper(home, "/usr/bin:/bin").stdout, "home status\n")

    def test_falls_back_to_path(self):
        with tempfile.TemporaryDirectory() as home:
            fake_defi(os.path.join(home, "bin/defi"), "path")
            r = self.run_wrapper(home, os.path.join(home, "bin") + ":/usr/bin:/bin")
            self.assertEqual(r.stdout, "path status\n")

    def test_exits_127_without_defi(self):
        with tempfile.TemporaryDirectory() as home:
            r = self.run_wrapper(home, "/usr/bin:/bin")
            self.assertEqual(r.returncode, 127)
            self.assertIn("not installed", r.stderr)


if __name__ == "__main__":
    unittest.main()
