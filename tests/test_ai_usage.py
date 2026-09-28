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

    def test_the_first_provider_carries_its_reset_as_hours_and_minutes(self):
        ai.PILL = [("claude", "5h"), ("codex", "5h")]
        soon = ai.datetime.now(ai.timezone.utc) + ai.timedelta(hours=2, minutes=5, seconds=30)
        q = quota(29)
        q[0]["metrics"][0]["resets_at"] = soon.isoformat()
        _, _, parts = ai.label({"claude": q, "codex": quota(12)})
        self.assertEqual([p["label"] for p in parts], ["29%", "2:05", "12%"])
        self.assertEqual(parts[1]["label_color"], "muted")
        self.assertTrue(parts[1]["under"])
        ai.STACK = False
        self.assertFalse(ai.label({"claude": q})[2][1]["under"])
        ai.STACK = True
        self.assertEqual([ai.whole(s) for s in (30, 42 * 60, (4 * 60 + 46) * 60, 3 * 86400 + 5)],
                         ["0:01", "0:42", "4:46", "3d"])

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

    def test_each_day_carries_the_same_weekday_a_week_before(self):
        from datetime import date, timedelta
        ai.PANEL, ai.OPEN = [], []
        today = date.today()
        stats = {"days": {today.isoformat(): [500, 1.0]}, "day_models": {}, "models": [],
                 "sessions": 1, "active_ms": 0,
                 "prior": {(today - timedelta(days=7)).isoformat(): {"Opus 5.5": 200, "Sonnet 5": 100},
                           (today - timedelta(days=13)).isoformat(): 40}}
        days = ai.panel({}, {}, stats)["days"]
        self.assertEqual(len(days), 7)
        self.assertEqual((days[-1]["date"], days[-1]["prior"]), (today.isoformat(), 300))
        self.assertEqual(days[-1]["prior_models"], {"Opus 5.5": 200, "Sonnet 5": 100})
        self.assertEqual((days[0]["prior"], days[0]["prior_models"]), (40, {"Other": 40}))
        self.assertEqual(sum(d["prior"] for d in days), 340)


if __name__ == "__main__":
    unittest.main()
