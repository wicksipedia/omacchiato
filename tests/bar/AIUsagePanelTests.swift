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
         "sessions": 3, "active_hours": 2}
        """
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let report = try #require(AIUsageReport(json: json))
        #expect(report.providers.map(\.name) == ["Claude", "Codex"])
        #expect(report.providers[0].metrics[0].elapsed == 0.4)
        #expect(report.providers[0].incidents[0].at != nil)
        #expect(!report.providers[0].healthy && report.providers[1].healthy)
        #expect(report.weekTokens == 30_000_000)
        #expect(report.sessions == 3 && report.activeHours == 2)
        #expect(AIUsageReport(json: ["kind": "other"]) == nil)
    }
}
