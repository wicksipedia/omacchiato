import datetime
import unittest

from loader import load

release = load("omacchiato-release")
DAY = datetime.date(2026, 9, 28)


class NextVersion(unittest.TestCase):
    def test_the_first_release_of_a_day_is_the_date(self):
        self.assertEqual(release.next_version(DAY, {"v2026.09.27"}), "v2026.09.28")

    def test_a_second_release_on_the_same_day_counts_up(self):
        self.assertEqual(release.next_version(DAY, {"v2026.09.28"}), "v2026.09.28.1")
        self.assertEqual(release.next_version(DAY, {"v2026.09.28", "v2026.09.28.1"}),
                         "v2026.09.28.2")


class LatestVersion(unittest.TestCase):
    def test_sorts_by_number_not_by_text(self):
        tags = {"v2026.09.28", "v2026.09.28.2", "v2026.09.28.10", "v2026.09.27.5"}
        self.assertEqual(release.latest_version(tags), "v2026.09.28.10")

    def test_the_plain_date_comes_before_its_second_release(self):
        self.assertEqual(release.latest_version({"v2026.09.28", "v2026.09.28.1"}), "v2026.09.28.1")

    def test_ignores_tags_that_are_not_versions(self):
        self.assertEqual(release.latest_version({"v1.0.0", "wip", "v2026.10.01"}), "v2026.10.01")
        self.assertIsNone(release.latest_version({"v1.0.0"}))


class RepoSlug(unittest.TestCase):
    def test_https_and_ssh_remotes(self):
        for url in ("https://github.com/wicksipedia/omacchiato.git",
                    "https://github.com/wicksipedia/omacchiato",
                    "git@github.com:wicksipedia/omacchiato.git"):
            self.assertEqual(release.repo_slug(url), "wicksipedia/omacchiato")

    def test_refuses_another_host(self):
        with self.assertRaises(ValueError):
            release.repo_slug("https://gitlab.com/a/b.git")


if __name__ == "__main__":
    unittest.main()
