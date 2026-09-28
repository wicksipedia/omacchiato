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
}
