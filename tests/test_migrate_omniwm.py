import json
import os
import subprocess
import tempfile
import unittest

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SCRIPT = os.path.join(REPO, "migrate-omniwm.sh")


def stub(bindir, name, body):
    path = os.path.join(bindir, name)
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + body + "\n")
    os.chmod(path, 0o755)


class MigrateOmniWM(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        self.bindir = os.path.join(self.tmp.name, "stubs")
        self.local_bin = os.path.join(self.home, ".local/bin")
        os.makedirs(self.local_bin)
        os.makedirs(self.bindir)
        # no OmniWM runs, and no real login item is read or deleted
        stub(self.bindir, "pgrep", "exit 1")
        stub(self.bindir, "pkill", "exit 1")
        stub(self.bindir, "osascript", 'echo "$@" >> "%s/osascript.log"' % self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self):
        env = {"HOME": self.home, "PATH": self.bindir + ":/usr/bin:/bin"}
        return subprocess.run(["/bin/bash", SCRIPT], env=env, capture_output=True, text=True, check=True)

    def test_removes_the_omniwm_binaries_and_links(self):
        for name in ("omacchiato-overview", "omacchiato-omni"):
            open(os.path.join(self.local_bin, name), "w").close()
        for name in ("omacchiato-ws", "omacchiato-omniwmctl"):
            os.symlink("/clone/bin/" + name, os.path.join(self.local_bin, name))
        out = self.run_script().stdout
        self.assertEqual(os.listdir(self.local_bin), [])
        self.assertIn("Moved from OmniWM to Defi", out)

    def test_keeps_a_link_of_the_users_with_the_same_name(self):
        os.symlink("/somewhere/else", os.path.join(self.local_bin, "omacchiato-ws"))
        self.run_script()
        self.assertTrue(os.path.islink(os.path.join(self.local_bin, "omacchiato-ws")))

    def test_replaces_the_omniwm_rules_in_a_kept_karabiner_config(self):
        path = os.path.join(self.home, ".config/karabiner/karabiner.json")
        os.makedirs(os.path.dirname(path))
        rules = [{"description": d, "manipulators": []}
                 for d in ("mine", "omacchiato-omniwm: workspace slot 1")]
        with open(path, "w") as f:
            json.dump({"profiles": [{"selected": True, "complex_modifications": {"rules": rules}}]}, f)
        self.run_script()
        with open(path) as f:
            descs = [r["description"] for r in json.load(f)["profiles"][0]["complex_modifications"]["rules"]]
        self.assertEqual(descs[0], "mine")
        self.assertFalse(any("omniwm" in d for d in descs))
        self.assertIn("omacchiato-keys: herdr", descs)

    def test_a_second_run_does_nothing(self):
        open(os.path.join(self.local_bin, "omacchiato-omni"), "w").close()
        self.run_script()
        self.assertEqual(self.run_script().stdout, "")


if __name__ == "__main__":
    unittest.main()
