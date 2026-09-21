import unittest

from loader import load

gh = load("omacchiato-github-prs")


def pr(n, ci="SUCCESS", state="OPEN", reviews=0, decision=None, threads=(), base="main"):
    return {"number": n, "title": "t" * 80, "url": "https://github.com/a/b/pull/%d" % n,
            "baseRefName": base, "headRefName": "branch-%d" % n,
            "state": state, "isDraft": False, "mergeable": "MERGEABLE",
            "reviewDecision": decision, "repository": {"nameWithOwner": "a/b"},
            "reviews": {"totalCount": reviews}, "latestOpinionatedReviews": {"nodes": []},
            "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": ci}}}]},
            "reviewThreads": {"nodes": [
                {"isResolved": False, "comments": {"nodes": [{"author": {"login": who}}]}}
                for who in threads]}}


def texts(payload):
    return [r.get("text", "") for r in payload["rows"]]


class Render(unittest.TestCase):
    def test_list(self):
        p = gh.render([pr(1), pr(2, ci="FAILURE", reviews=1, decision="APPROVED")],
                      [pr(3, state="MERGED"), pr(4, state="CLOSED")], {"a/b#2", "a/b#3"}, "me")
        self.assertEqual((p["label"], p["color"]), ("2 !", "red"))
        t = texts(p)
        self.assertEqual((t[0], p["rows"][0]["detail"]), ("a/b", "3"))
        self.assertFalse(any("#4 " in x for x in t), "a read closed PR is hidden")
        self.assertTrue(t[1].startswith("#3 "))
        self.assertEqual(t[2].strip(), "Merged.")
        self.assertTrue(t[3].startswith("#2 "))
        self.assertEqual(len(t[3]), len("#2 ") + gh.TITLE_MAX)
        self.assertEqual(t[4].strip(), "CI failed.", "the mark already says approved")
        self.assertTrue(t[5].startswith("#1 "))
        self.assertEqual(t[6], "", "a waiting PR needs no sentence")
        marks = [(r.get("icon"), r.get("icon_color")) for r in p["rows"]]
        self.assertEqual(marks[1], gh.icon(pr(0, state="MERGED"), "me"))
        self.assertEqual(marks[3], gh.icon(pr(0, ci="FAILURE"), "me"))
        self.assertEqual(marks[5], gh.icon(pr(0), "me"))

    def test_label_counts_open_prs(self):
        self.assertEqual(gh.render([pr(1)], [], set())["label"], "1")

    def test_unsubscribed_pr_is_hidden(self):
        muted = dict(pr(5), viewerSubscription="UNSUBSCRIBED")
        self.assertEqual(gh.render([pr(1), muted], [], {"a/b#5"})["label"], "1")

    def test_stack(self):
        stacked = texts(gh.render([pr(11), pr(12, base="branch-11"), pr(13, base="branch-12")], [], set()))
        self.assertTrue(stacked[1].startswith("#11 "))
        self.assertTrue(stacked[2].startswith("  ↳ #12 "))
        self.assertTrue(stacked[3].startswith("    ↳ #13 "))

    def test_stack_loop_lists_both_once(self):
        loop = texts(gh.render([pr(14, base="branch-15"), pr(15, base="branch-14")], [], set()))
        self.assertEqual([sum("#%d " % n in x for x in loop) for n in (14, 15)], [1, 1])

    def test_no_branch_names_is_not_a_stack(self):
        blank = [dict(pr(n), baseRefName=None, headRefName=None) for n in (16, 17)]
        self.assertFalse(any("↳" in x for x in texts(gh.render(blank, [], set()))))


class Marks(unittest.TestCase):
    def test_approved_is_green_with_no_sentence(self):
        approved = pr(6, reviews=1, decision="APPROVED")
        self.assertEqual(gh.icon(approved, "me")[1], "green")
        self.assertEqual(gh.status(approved, "me"), "")

    def test_running_ci_shows_before_feedback(self):
        running = gh.icon(pr(7, ci="PENDING", reviews=1, decision="APPROVED"), "me")
        self.assertEqual(running[1], "yellow")
        self.assertNotEqual(running, gh.icon(pr(8, reviews=1, threads=("them",)), "me"))
        self.assertEqual(gh.icon(pr(7, ci="PENDING", reviews=1, threads=("them",)), "me"), running)

    def test_threads(self):
        self.assertEqual(gh.status(pr(8, reviews=1, threads=("them", "them")), "me"),
                         "2 review threads to resolve.")
        self.assertEqual(gh.icon(pr(9, threads=("me",)), "me"), gh.icon(pr(0), "me"),
                         "your own thread is not feedback")

    def test_conflict_reads_as_failed(self):
        self.assertEqual(gh.icon(dict(pr(10), mergeable="CONFLICTING"), "me"),
                         gh.icon(pr(0, ci="FAILURE"), "me"))


if __name__ == "__main__":
    unittest.main()
