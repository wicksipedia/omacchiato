import Foundation
import Testing
@testable import AIUsagePanel

@Suite struct AIUsagePanelTests {
    typealias Metric = AIUsageReport.Metric

    @Test("the forecast follows the rate so far to the reset")
    func forecast() {
        // 40% of the window gone, 20% used: 50% at the reset
        #expect(Metric(label: "5h", used: 0.2, resetsIn: 3 * 3600, span: 5 * 3600).forecastText
                == "On pace for 50% at the reset.")
        // 50% gone, 80% used: full in 37m, well before the reset
        #expect(Metric(label: "5h", used: 0.8, resetsIn: 2.5 * 3600, span: 5 * 3600).forecastText
                == "Runs out in 37m, 1h 52m before the reset.")
        #expect(Metric(label: "5h", used: 1, resetsIn: 600, span: 5 * 3600).forecastText
                == "Limit reached. Resets in 10m.")
        // too early in the window to say
        #expect(Metric(label: "5h", used: 0.1, resetsIn: 4.9 * 3600, span: 5 * 3600).forecastText == nil)
    }

    @Test("the reset time names the day")
    func resetAt() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let us = Locale(identifier: "en_US")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!  // a Tuesday
        #expect(resetAtText(now + 2 * 3600 - 10, now: now, calendar: cal, locale: us) == "Today 2:00\u{202F}PM")
        #expect(resetAtText(now + 4 * 86400 + 2 * 3600, now: now, calendar: cal, locale: us) == "Sat 2:00\u{202F}PM")
        #expect(resetAtText(now + 30 * 86400, now: now, calendar: cal, locale: us) == "Nov 5")
    }

    @Test("the panel reads the script's JSON")
    func decode() throws {
        let text = """
        {"kind": "ai-usage",
         "providers": [{"id": "claude-0", "name": "Claude", "plan": "Max 5x", "color": "#D97757",
                        "metrics": [{"label": "Session", "used": 0.42, "resets_in": 10800, "span": 18000}],
                        "severity": 2, "status": "Claude Code: Partial outage",
                        "incidents": [{"name": "Errors", "status": "identified",
                                       "at": "2026-09-28T01:02:03.456Z", "url": "https://x.test"}]},
                       {"id": "codex-0", "name": "Codex", "color": "label", "metrics": []}],
         "days": [{"date": "2026-09-28", "models": {"Opus 5.5": 30000000}, "cost": 11.2}],
         "models": [{"name": "Opus 5.5", "tokens": 30000000, "cost": 11.2}],
         "sessions": 3, "active_hours": 2, "updated": 1769000000}
        """
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let report = try #require(AIUsageReport(json: json))
        #expect(report.providers.map(\.name) == ["Claude", "Codex"])
        #expect(report.providers[0].metrics[0].elapsed == 0.4)
        #expect(report.providers[0].incidents[0].at != nil)
        #expect(!report.providers[0].healthy && report.providers[1].healthy)
        #expect(report.weekTokens == 30_000_000)
        #expect(report.sessions == 3 && report.activeHours == 2)
        #expect(report.updated == Date(timeIntervalSince1970: 1769000000))
        #expect(AIUsageReport(json: ["kind": "other"]) == nil)
    }

    @Test("without an updated field, the panel reads as just read")
    func decodeWithoutUpdated() throws {
        let now = Date()
        let report = try #require(AIUsageReport(json: ["kind": "ai-usage", "providers": []], now: now))
        #expect(report.updated == now)
    }

    @Test("the week counts tokens or cost by model, and an older cache charts its cost as Other")
    func measures() throws {
        let report = try #require(AIUsageReport(json: ["kind": "ai-usage", "providers": [], "days": [
            ["date": "2026-10-01", "models": ["Opus 5.5": 300], "cost": 3.0,
             "model_costs": ["Opus 5.5": 3.0], "prior_models": ["Opus 5.5": 100], "prior_costs": ["Opus 5.5": 2.0]],
            ["date": "2026-10-02", "models": ["Opus 5.5": 100], "cost": 1.5],
        ]]))
        #expect(report.weekValue(.tokens) == 400)
        #expect(report.weekValue(.cost) == 4.5)
        #expect(report.days[1].values(.cost) == ["Other": 1.5])
        #expect(report.weekChange(.cost) == 1.25)
        #expect(UsageMeasure.cost.text(4.5) == "$4.50")
    }
}
