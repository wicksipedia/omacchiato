import Foundation
import Testing
@testable import KeepAwakePanel

@Suite struct KeepAwakePanelTests {
    let json: [String: Any] = [
        "kind": "keep-awake",
        "holders": [
            ["name": "Steam", "pid": 1234, "duration": "2h 15m"],
            ["name": "caffeinate", "duration": "<1m"],
        ],
    ]

    @Test("the panel object decodes, pid missing on a holder that has none")
    func decodes() throws {
        let holders = try #require(KeepAwakeReport(json: json)?.holders)
        #expect(holders.map(\.name) == ["Steam", "caffeinate"])
        #expect(holders[0].pid == 1234)
        #expect(holders[0].duration == "2h 15m")
        #expect(holders[1].pid == nil)
    }

    @Test("another plugin's panel is not keep-awake")
    func otherKind() {
        #expect(KeepAwakeReport(json: ["kind": "airpods"]) == nil)
    }

    @Test("no holders decodes to an empty list")
    func noHolders() {
        #expect(KeepAwakeReport(json: ["kind": "keep-awake"])?.holders.isEmpty == true)
    }

    @Test("the panel object carries the bar's own state: on, and the end time of a timed run")
    func state() throws {
        let off = try #require(KeepAwakeReport(json: json))
        #expect(!off.on && off.until == nil)
        let timed = try #require(KeepAwakeReport(json: ["kind": "keep-awake", "on": true, "until": 1790748720]))
        #expect(timed.on && timed.until == Date(timeIntervalSince1970: 1790748720))
    }
}
