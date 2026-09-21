import unittest

from loader import load

ai = load("omacchiato-ai-usage")


def quota(pct):
    return [{"account": {"is_active": True}, "metrics": [{"label": "5h", "used_percent": pct}]}]


class Label(unittest.TestCase):
    def test_provider_at_zero_leaves_the_pill(self):
        ai.PILL = [("claude", "5h"), ("codex", "5h")]
        text, _, parts = ai.label({"claude": quota(40), "codex": quota(0.2)})
        self.assertEqual(text, "")
        self.assertEqual([p["label"] for p in parts], ["40%"])

    def test_every_provider_at_zero_shows_the_idle_icon(self):
        # an empty label with no parts is what main() turns into IDLE_ICON
        ai.PILL = [("claude", "5h"), ("codex", "5h")]
        self.assertEqual(ai.label({"claude": quota(0), "codex": quota(0.4)}), ("", "muted", []))

    def test_one_provider_reads_as_text(self):
        ai.PILL = [("claude", "5h")]
        self.assertEqual(ai.label({"claude": quota(12)}), ("12%", "green", []))


if __name__ == "__main__":
    unittest.main()
