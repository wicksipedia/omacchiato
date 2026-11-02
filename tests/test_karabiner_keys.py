import json
import os
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "bin", "omacchiato-karabiner-keys")
WINDOW_KEYS = {"left_arrow", "right_arrow", "up_arrow", "down_arrow", "tab", "hyphen", "equal_sign", "o",
               "spacebar"} | {str(n) for n in range(1, 10)}


def rule(desc, key="x"):
    return {"description": desc, "manipulators": [{"type": "basic", "from": {"key_code": key}}]}


class KarabinerKeys(unittest.TestCase):
    def run_script(self, action, rules):
        with tempfile.TemporaryDirectory() as home:
            path = os.path.join(home, ".config/karabiner/karabiner.json")
            os.makedirs(os.path.dirname(path))
            with open(path, "w") as f:
                json.dump({"profiles": [{"selected": True, "complex_modifications": {"rules": rules}}]}, f)
            env = {"HOME": home, "PATH": "/usr/bin:/bin"}
            subprocess.run(["/bin/bash", SCRIPT, action], env=env, check=True, capture_output=True)
            with open(path) as f:
                return json.load(f)["profiles"][0]["complex_modifications"]["rules"]

    def test_install_replaces_the_omniwm_rules_and_keeps_the_users(self):
        old = [rule("Caps Lock -> Super"), rule("omacchiato-omniwm: workspace slot 1", "1"),
               rule("omacosy-omniwm: terminal")]
        rules = self.run_script("install", old)
        descs = [r["description"] for r in rules]
        self.assertEqual(descs[0], "Caps Lock -> Super")
        self.assertFalse(any("omniwm" in d for d in descs))
        self.assertIn("omacchiato-keys: herdr", descs)

    def test_install_adds_no_window_keys(self):
        rules = self.run_script("install", [])
        keys = {m["from"]["key_code"] for r in rules for m in r["manipulators"]}
        self.assertFalse(keys & WINDOW_KEYS)

    def test_a_second_install_changes_nothing(self):
        once = [r["description"] for r in self.run_script("install", [])]
        twice = [r["description"] for r in self.run_script("install", [rule(d) for d in once])]
        self.assertEqual(twice, once)

    def test_remove_takes_every_owned_rule(self):
        rules = self.run_script("remove", [rule("mine"), rule("omacchiato-keys: herdr"),
                                           rule("omacchiato-omniwm: overview")])
        self.assertEqual([r["description"] for r in rules], ["mine"])


if __name__ == "__main__":
    unittest.main()
