import Foundation
import Testing
@testable import AirPodsPanel

@Suite struct AirPodsPanelTests {
    let json: [String: Any] = [
        "kind": "airpods",
        "settings": "x-apple.systempreferences:com.apple.Sound-Settings.extension",
        "devices": [[
            "name": "Matt’s AirPods Pro", "model": "AirPods Pro (2nd generation)",
            "type": "com.apple.airpods-pro-gen2", "cable": false, "mode": "adaptive",
            "battery": ["Case": 52, "Right": 82, "Left": 83],
            "modes": [["id": "off", "title": "Off", "run": "x off"],
                      ["id": "adaptive", "title": "Adaptive", "run": "x adaptive"]],
        ]],
    ]

    @Test("the panel object decodes, with the batteries left, right, then case")
    func decodes() throws {
        let device = try #require(AirPodsReport(json: json)?.devices.first)
        #expect(device.batteries.map(\.part) == ["Left", "Right", "Case"])
        #expect(device.modes.map(\.id) == ["off", "adaptive"])
        #expect(device.mode == "adaptive")
        #expect(device.subtitle == "AirPods Pro (2nd generation)")
    }

    @Test("another plugin's panel is not AirPods")
    func otherKind() {
        #expect(AirPodsReport(json: ["kind": "github-prs"]) == nil)
    }

    @Test("a model name inside the device name is not repeated")
    func subtitle() {
        let d = AirPodsReport.Device(name: "Matt’s AirPods Max", model: "AirPods Max", type: "", batteries: [])
        #expect(d.subtitle == nil)
    }
}
