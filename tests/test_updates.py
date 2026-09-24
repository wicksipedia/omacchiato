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
        self.assertEqual(out["rows"][-1]["terminal"], "omacchiato-update")

    def test_a_long_list_is_cut(self):
        out = updates.pill(["c%d" % i for i in range(15)])
        self.assertEqual(out["label"], "15")
        self.assertIn({"text": "and 5 more", "dim": True}, out["rows"])


if __name__ == "__main__":
    unittest.main()
