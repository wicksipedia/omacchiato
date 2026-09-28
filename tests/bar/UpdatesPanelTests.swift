import Foundation
import Testing
@testable import UpdatesPanel

@Suite struct UpdatesPanelTests {
    let json: [String: Any] = [
        "kind": "updates",
        "target": "v2026.10.01",
        "update": "/bin/sh -c 'omacchiato-update'",
        "commits": [["hash": "abc1234", "subject": "Fix a", "age": "2 hours ago"],
                    ["hash": "def5678", "subject": "Add b", "age": "3 days ago"]],
        "more": 4,
        "updated": 1_700_000_000,
    ]

    @Test("the panel object decodes, in the order the commits arrived")
    func decodes() throws {
        let report = try #require(UpdatesReport(json: json))
        #expect(report.target == "v2026.10.01")
        #expect(report.commits.map(\.subject) == ["Fix a", "Add b"])
        #expect(report.more == 4)
        #expect(report.total == 6)
        #expect(report.updated == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("no fetch time yet leaves it empty")
    func noUpdated() {
        let noUpdated: [String: Any] = ["kind": "updates", "commits": [], "update": ""]
        #expect(UpdatesReport(json: noUpdated)?.updated == nil)
    }

    @Test("another plugin's panel is not an updates panel")
    func otherKind() {
        #expect(UpdatesReport(json: ["kind": "github-prs"]) == nil)
    }

    @Test("no release tag yet leaves the target empty")
    func noTarget() {
        let noTarget: [String: Any] = ["kind": "updates", "commits": [], "update": ""]
        #expect(UpdatesReport(json: noTarget)?.target == nil)
    }
}
