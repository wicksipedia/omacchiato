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

    @Test("the last chosen time decodes, and a custom one reads as its minutes")
    func last() throws {
        #expect(KeepAwakeReport(json: json)?.last == "on")
        let custom = try #require(KeepAwakeReport(json: ["kind": "keep-awake", "last": "for 75"]))
        #expect(custom.last == "for 75" && custom.lastMinutes == 75)
        #expect(KeepAwakeReport(json: ["kind": "keep-awake", "last": "on"])?.lastMinutes == nil)
    }

    @Test("the custom time steps by 15 minutes, from 15 minutes to 12 hours")
    func customSteps() {
        #expect(customMinutes(45, by: 1) == 60)
        #expect(customMinutes(15, by: -1) == 15)
        #expect(customMinutes(720, by: 1) == 720)
        #expect(customLabel(75) == "1 hr 15 min")
        #expect(customLabel(45) == "45 min")
        #expect(customLabel(120) == "2 hr")
    }
}
