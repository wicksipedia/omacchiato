import Foundation
import Testing
@testable import StatsPanel

@Suite struct StatsPanelTests {
    @Test("a CPU report decodes its cores and top processes")
    func cpu() throws {
        let json: [String: Any] = [
            "kind": "stats", "metric": "cpu", "percent": 0.42, "cores": 8,
            "top": [["name": "WindowServer", "value": 0.45], ["name": "claude", "value": 0.09]],
        ]
        let report = try #require(StatsReport(json: json))
        #expect(report.metric == .cpu)
        #expect(report.percent == 0.42)
        #expect(report.cores == 8)
        #expect(report.top.map(\.name) == ["WindowServer", "claude"])
        #expect(report.top.map(\.value) == [0.45, 0.09])
    }

    @Test("a memory report decodes its parts as whole bytes")
    func ram() throws {
        let json: [String: Any] = [
            "kind": "stats", "metric": "ram", "percent": 0.62,
            "used": 39_900_000_000, "total": 64_000_000_000,
            "app": 31_000_000_000, "wired": 5_700_000_000, "compressed": 3_200_000_000,
        ]
        let report = try #require(StatsReport(json: json))
        #expect(report.metric == .ram)
        #expect(report.used == 39_900_000_000)
        #expect(report.app == 31_000_000_000)
        #expect(report.wired == 5_700_000_000)
        #expect(report.compressed == 3_200_000_000)
    }

    @Test("a disk report carries the Storage Settings link")
    func disk() throws {
        let json: [String: Any] = [
            "kind": "stats", "metric": "disk", "percent": 0.283,
            "used": 564_708_454_400, "total": 1_995_165_736_960, "free": 1_430_457_282_560,
            "settings": "x-apple.systempreferences:com.apple.settings.Storage",
        ]
        let report = try #require(StatsReport(json: json))
        #expect(report.metric == .disk)
        #expect(report.free == 1_430_457_282_560)
        #expect(report.settings?.absoluteString == "x-apple.systempreferences:com.apple.settings.Storage")
    }

    @Test("another plugin's panel is not stats")
    func otherKind() {
        #expect(StatsReport(json: ["kind": "github-prs"]) == nil)
    }

    @Test("an unknown metric name is not decoded")
    func unknownMetric() {
        #expect(StatsReport(json: ["kind": "stats", "metric": "swap"]) == nil)
    }
}
