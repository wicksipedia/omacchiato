import unittest

from loader import load

updates = load("omacchiato-updates")


class Pill(unittest.TestCase):
    def test_up_to_date_hides_the_pill(self):
        self.assertEqual(updates.pill([]), {"icon": "", "label": ""})

    def test_new_commits_show_their_count_and_an_update_row(self):
        out = updates.pill(["Fix a", "Add b"])
        self.assertEqual(out["label"], "2")
        self.assertEqual([r.get("text") for r in out["rows"][1:3]], ["Fix a", "Add b"])
        self.assertIn("/bin/omacchiato-update", out["rows"][-1]["terminal"])

    def test_a_long_list_is_cut(self):
        out = updates.pill(["c%d" % i for i in range(15)])
        self.assertEqual(out["label"], "15")
        self.assertIn({"text": "And 5 more", "dim": True}, out["rows"])



class NewestRelease(unittest.TestCase):
    def test_takes_the_first_date_tag_of_the_sorted_list(self):
        tags = "v2026.10.01\nv2026.09.28.1\nv2026.09.28\n"
        self.assertEqual(updates.newest_release(tags), "v2026.10.01")

    def test_skips_tags_that_are_not_releases(self):
        self.assertEqual(updates.newest_release("v9.9.9\nv2026.09.28.1\n"), "v2026.09.28.1")

    def test_no_release_gives_none(self):
        self.assertIsNone(updates.newest_release(""))
        self.assertIsNone(updates.newest_release("v1.0.0\n"))


if __name__ == "__main__":
    unittest.main()
