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

    def test_each_provider_carries_its_reset(self):
        ai.PILL = [("claude", "5h"), ("codex", "5h")]
        soon = ai.datetime.now(ai.timezone.utc) + ai.timedelta(hours=2, minutes=5, seconds=30)
        q = quota(29)
        q[0]["metrics"][0]["resets_at"] = soon.isoformat()
        week = quota(12)
        week[0]["metrics"][0]["resets_at"] = (soon + ai.timedelta(days=6, hours=20, minutes=50)).isoformat()
        _, _, parts = ai.label({"claude": q, "codex": week})
        self.assertEqual([p["label"] for p in parts], ["29%", "2:05", "12%", "6d23h"])
        self.assertEqual(parts[1]["label_color"], "muted")
        self.assertTrue(parts[1]["under"])
        ai.STACK = False
        self.assertFalse(ai.label({"claude": q})[2][1]["under"])
        ai.STACK = True
        self.assertEqual([ai.whole(s) for s in (30, 42 * 60, (4 * 60 + 46) * 60, 3 * 86400 + 5, 6 * 86400 + 23.6 * 3600)],
                         ["0:01", "0:42", "4:46", "3d", "7d"])

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
        out = ai.panel(quotas, states, None, 1_700_000_000)
        claude, codex = out["providers"]
        self.assertEqual([m["label"] for m in claude["metrics"]], ["Session"])
        self.assertEqual(claude["metrics"][0]["used"], 0.42)
        self.assertEqual((claude["severity"], claude["status"]), (2, "Claude Code: Partial outage"))
        self.assertEqual((codex["name"], codex["metrics"], codex["severity"]), ("Codex", [], 0))
        self.assertEqual((claude["open"], codex["open"]), (True, False))
        self.assertEqual(out["updated"], 1_700_000_000)
        self.assertNotIn("days", out)

    def test_usage_read_at_is_the_oldest_shown_provider(self):
        entry = {"usage": {"claude": {"at": 100, "outputs": []}, "codex": {"at": 200, "outputs": []}}}
        self.assertEqual(ai.usage_read_at(entry, ["claude", "codex"]), 100)
        self.assertEqual(ai.usage_read_at(entry, ["codex"]), 200)

    def test_usage_read_at_falls_back_to_now_with_nothing_cached(self):
        self.assertEqual(ai.usage_read_at({}, ["claude"]), ai.NOW)

    def test_each_day_carries_the_same_weekday_a_week_before(self):
        from datetime import date, timedelta
        ai.PANEL, ai.OPEN = [], []
        today = date.today()
        stats = {"days": {today.isoformat(): [500, 1.0]}, "day_models": {}, "models": [],
                 "sessions": 1, "active_ms": 0,
                 "prior": {(today - timedelta(days=7)).isoformat(): {"Opus 5.5": 200, "Sonnet 5": 100},
                           (today - timedelta(days=13)).isoformat(): 40}}
        days = ai.panel({}, {}, stats, ai.NOW)["days"]
        self.assertEqual(len(days), 7)
        self.assertEqual((days[-1]["date"], days[-1]["prior"]), (today.isoformat(), 300))
        self.assertEqual(days[-1]["prior_models"], {"Opus 5.5": 200, "Sonnet 5": 100})
        self.assertEqual((days[0]["prior"], days[0]["prior_models"]), (40, {"Other": 40}))
        self.assertEqual(sum(d["prior"] for d in days), 340)
        self.assertEqual(days[-1]["model_costs"], {"Other": 1.0})
        self.assertEqual(days[-1]["prior_costs"], {})


    def test_each_client_gets_a_chart_colour(self):
        models = [["claude-opus-5-5", 700, 0], ["claude-sonnet-5", 80, 0], ["claude-sonnet-5-5", 6, 0],
                  ["gpt-6.1-sol", 5, 0], ["gpt-5.6-terra", 1, 0]]
        clients = {m[0]: "codex" if m[0].startswith("gpt") else "claude" for m in models}
        self.assertEqual([m[0] for m in ai.chart_order(models, clients)],
                         ["claude-opus-5-5", "claude-sonnet-5", "gpt-6.1-sol", "claude-sonnet-5-5", "gpt-5.6-terra"])
        self.assertEqual(ai.chart_order(models, {}), models)
        colours = [m.get("color") for m in ai.model_colours(ai.chart_order(models, clients), clients)]
        claude, codex = ai.PROVIDERS["claude"]["shades"], ai.PROVIDERS["codex"]["shades"]
        self.assertEqual(colours, [claude[0], claude[1], codex[0], None, None])


class Refresh(unittest.TestCase):
    def test_a_refresh_request_shortens_the_cache_to_the_floor(self):
        import os
        os.environ.pop("OMACCHIATO_REFRESH", None)
        self.assertEqual(ai.max_age(), ai.FRESH_S)
        os.environ["OMACCHIATO_REFRESH"] = "1"
        try:
            self.assertEqual(ai.max_age(), ai.REFRESH_FLOOR_S)
        finally:
            del os.environ["OMACCHIATO_REFRESH"]


class PillIcon(unittest.TestCase):
    def test_one_provider_shows_the_icon_from_the_settings(self):
        ai.PILL = [("claude", "5h")]
        self.assertEqual(ai.pill_icon("20%", [{"label": "0:50"}], "", "X"), "X")

    def test_one_provider_with_no_icon_set_shows_its_logo(self):
        ai.PILL = [("claude", "5h")]
        self.assertEqual(ai.pill_icon("20%", [], "", ""), ai.PROVIDERS["claude"]["glyph"])

    def test_several_providers_leave_the_logos_to_the_parts(self):
        ai.PILL = [("claude", "5h"), ("codex", "5h")]
        self.assertEqual(ai.pill_icon("", [{"label": "20%"}], "!", "X"), "!")

    def test_nothing_used_shows_the_idle_icon(self):
        ai.PILL = [("claude", "5h")]
        self.assertEqual(ai.pill_icon("", [], "", "X"), ai.IDLE_ICON)


if __name__ == "__main__":
    unittest.main()
