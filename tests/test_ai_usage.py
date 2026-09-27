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


class Panel(unittest.TestCase):
    def test_panel_drops_empty_plans_and_reads_health(self):
        ai.PANEL = ["claude", "codex"]
        ai.OPEN = ["claude"]
        quotas = {"claude": [{"provider": "Claude", "plan": "Max 5x", "metrics": [
            {"label": "Session", "used_percent": 42},
            {"label": "Chat", "used_percent": 0, "remaining_label": "0/0 left"}]}]}
        states = {"claude": {"status": {"indicator": "major", "description": "Claude Code: Partial outage"},
                             "incidents": []},
                  "codex": None}
        out = ai.panel(quotas, states, None)
        claude, codex = out["providers"]
        self.assertEqual([m["label"] for m in claude["metrics"]], ["Session"])
        self.assertEqual(claude["metrics"][0]["used"], 0.42)
        self.assertEqual((claude["severity"], claude["status"]), (2, "Claude Code: Partial outage"))
        self.assertEqual((codex["name"], codex["metrics"], codex["severity"]), ("Codex", [], 0))
        self.assertEqual((claude["open"], codex["open"]), (True, False))
        self.assertNotIn("days", out)


if __name__ == "__main__":
    unittest.main()
