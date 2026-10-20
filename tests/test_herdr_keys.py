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


OLD = "# omacchiato: old\n[keys]\nzoom = \"ctrl+alt+z\"\n"
NEW = "# omacchiato: new\n[keys]\nnew_tab = \"cmd+t\"\n"


class HerdrKeysUpgrade(unittest.TestCase):
    def test_add_replaces_an_unchanged_old_block(self):
        before = "[ui]\ntheme = \"dark\"\n"
        self.assertEqual(hk.add(hk.add(before, OLD), NEW, [OLD]), hk.add(before, NEW))

    def test_add_replaces_an_old_omacosy_block_with_no_markers(self):
        before = "[ui]\n\n" + OLD.replace("# omacchiato:", "# omacosy:")
        self.assertEqual(hk.add(before, NEW, [OLD]), hk.add("[ui]\n", NEW))

    def test_add_keeps_a_changed_old_block(self):
        changed = hk.add("", OLD).replace("ctrl+alt+z", "ctrl+z")
        self.assertEqual(hk.add(changed, NEW, [OLD]), changed)

    def test_remove_takes_an_old_block(self):
        self.assertEqual(hk.remove(hk.add("[ui]\n", OLD), NEW, [OLD]), "[ui]\n")

    def test_remove_takes_the_current_block_before_an_old_one(self):
        self.assertEqual(hk.remove(hk.add("[ui]\n", NEW), NEW, [OLD]), "[ui]\n")


if __name__ == "__main__":
    unittest.main()
