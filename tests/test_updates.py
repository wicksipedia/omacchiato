import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from loader import load

updates = load("omacchiato-updates")


def commit(subject, hash="a1b2c3d", age="2 hours ago"):
    return {"hash": hash, "subject": subject, "age": age}


class Pill(unittest.TestCase):
    def test_up_to_date_hides_the_pill(self):
        self.assertEqual(updates.pill([]), {"icon": "", "label": ""})

    def test_new_commits_show_their_count_and_an_update_row(self):
        out = updates.pill([commit("Fix a"), commit("Add b")])
        self.assertEqual(out["label"], "2")
        self.assertEqual([r.get("text") for r in out["rows"][1:3]], ["Fix a", "Add b"])
        self.assertIn("/bin/omacchiato-update", out["rows"][-1]["terminal"])

    def test_a_long_list_is_cut(self):
        out = updates.pill([commit("c%d" % i) for i in range(15)])
        self.assertEqual(out["label"], "15")
        self.assertIn({"text": "And 5 more", "dim": True}, out["rows"])


class Panel(unittest.TestCase):
    def test_carries_the_release_and_the_commits(self):
        out = updates.pill([commit("Fix a", hash="abc1234", age="2 hours ago")], target="v2026.10.01")
        panel = out["panel"]
        self.assertEqual(panel["kind"], "updates")
        self.assertEqual(panel["target"], "v2026.10.01")
        self.assertEqual(panel["commits"], [{"hash": "abc1234", "subject": "Fix a", "age": "2 hours ago"}])
        self.assertEqual(panel["more"], 0)
        self.assertIn("/bin/omacchiato-update", panel["update"])

    def test_no_release_yet_carries_no_target(self):
        out = updates.pill([commit("Fix a")])
        self.assertIsNone(out["panel"]["target"])

    def test_a_long_list_is_cut_to_the_shown_commits(self):
        out = updates.pill([commit("c%d" % i) for i in range(15)])
        self.assertEqual(len(out["panel"]["commits"]), 10)
        self.assertEqual(out["panel"]["more"], 5)

    def test_carries_the_fetch_time(self):
        out = updates.pill([commit("Fix a")], fetched=1700000000)
        self.assertEqual(out["panel"]["updated"], 1700000000)


class Channel(unittest.TestCase):
    def test_edge_updates_with_the_edge_flag(self):
        out = updates.pill([commit("Fix a")], channel="edge", counts={"release": 0, "edge": 1})
        self.assertTrue(out["panel"]["update"].startswith("/bin/sh -c '"))
        self.assertIn("omacchiato-update --edge;", out["panel"]["update"])
        self.assertIn("--edge", out["rows"][-1]["terminal"])
        self.assertEqual(out["panel"]["channel"], "edge")
        self.assertEqual(out["panel"]["counts"], {"release": 0, "edge": 1})

    def test_release_updates_with_no_flag(self):
        self.assertNotIn("--edge", updates.pill([commit("Fix a")])["panel"]["update"])

    def test_the_file_picks_the_channel_and_junk_falls_back_to_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "update-channel"
            with patch.object(updates, "CHANNEL_FILE", path):
                self.assertEqual(updates.read_channel(), "release")
                path.write_text("edge\n")
                self.assertEqual(updates.read_channel(), "edge")
                path.write_text("nightly\n")
                self.assertEqual(updates.read_channel(), "release")


class FetchedAt(unittest.TestCase):
    def test_reads_the_mtime_of_fetch_head(self):
        with tempfile.TemporaryDirectory() as tmp:
            fetch_head = Path(tmp) / ".git" / "FETCH_HEAD"
            fetch_head.parent.mkdir()
            fetch_head.touch()
            os.utime(fetch_head, (1700000000, 1700000000))
            with patch.object(updates, "REPO", Path(tmp)), \
                 patch.object(updates, "git", lambda *a, **kw: ".git/FETCH_HEAD\n"):
                self.assertEqual(updates.fetched_at(), 1700000000)

    def test_no_git_path_gives_none(self):
        with patch.object(updates, "git", lambda *a, **kw: None):
            self.assertIsNone(updates.fetched_at())

    def test_missing_file_gives_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(updates, "REPO", Path(tmp)), \
                 patch.object(updates, "git", lambda *a, **kw: ".git/FETCH_HEAD\n"):
                self.assertIsNone(updates.fetched_at())


class NewestRelease(unittest.TestCase):
    def test_takes_the_first_date_tag_of_the_sorted_list(self):
        tags = "v2026.10.01\nv2026.09.28.1\nv2026.09.28\n"
        self.assertEqual(updates.newest_release(tags), "v2026.10.01")

    def test_skips_tags_that_are_not_releases(self):
        self.assertEqual(updates.newest_release("v9.9.9\nv2026.09.28.1\n"), "v2026.09.28.1")

    def test_no_release_gives_none(self):
        self.assertIsNone(updates.newest_release(""))
        self.assertIsNone(updates.newest_release("v1.0.0\n"))


class ParseLog(unittest.TestCase):
    def test_splits_hash_subject_and_age(self):
        text = "abc1234\x1fFix a\x1f2 hours ago\ndef5678\x1fAdd b\x1f3 days ago\n"
        self.assertEqual(updates.parse_log(text),
                         [{"hash": "abc1234", "subject": "Fix a", "age": "2 hours ago"},
                          {"hash": "def5678", "subject": "Add b", "age": "3 days ago"}])

    def test_no_output_gives_an_empty_list(self):
        self.assertEqual(updates.parse_log(None), [])
        self.assertEqual(updates.parse_log(""), [])


if __name__ == "__main__":
    unittest.main()
