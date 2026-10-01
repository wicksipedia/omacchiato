import unittest

from loader import load

hk = load("omacchiato-herdr-keys")

KEYS = "# omacchiato\n[keys]\nzoom = \"ctrl+alt+z\"\n"


class HerdrKeys(unittest.TestCase):
    def test_add_then_remove_gives_back_the_config(self):
        before = "[ui]\ntheme = \"dark\"\n"
        added = hk.add(before, KEYS)
        self.assertIn(hk.START + KEYS + hk.END, added)
        self.assertEqual(hk.remove(added, KEYS), before)

    def test_add_leaves_a_config_with_keys_alone(self):
        before = "[keys]\nzoom = \"z\"\n"
        self.assertEqual(hk.add(before, KEYS), before)

    def test_remove_takes_an_older_block_with_no_markers(self):
        self.assertEqual(hk.remove("[ui]\n\n" + KEYS, KEYS), "[ui]\n")

    def test_remove_takes_a_migrated_omacosy_block(self):
        keys = "# omacchiato: note\n[keys]\n"
        self.assertEqual(hk.remove("[ui]\n\n# omacosy: note\n[keys]\n", keys), "[ui]\n")

    def test_remove_keeps_an_older_block_with_a_line_added(self):
        self.assertIsNone(hk.remove(KEYS + "cwd = \"/tmp\"\n", KEYS))
        self.assertIsNone(hk.remove(hk.add("", KEYS) + "cwd = \"/tmp\"\n", KEYS))
        self.assertEqual(hk.remove(KEYS + "\n[ui]\nx = 1\n", KEYS), "\n[ui]\nx = 1\n")

    def test_remove_keeps_a_changed_block(self):
        changed = hk.add("", KEYS).replace("ctrl+alt+z", "ctrl+z")
        self.assertIsNone(hk.remove(changed, KEYS))

    def test_remove_finds_nothing_in_the_users_own_keys(self):
        self.assertIsNone(hk.remove("[keys]\nzoom = \"z\"\n", KEYS))


if __name__ == "__main__":
    unittest.main()
