import Foundation
import Testing
@testable import omacchiato_bar

private func fixture(_ name: String) -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../fixtures/\(name).json")
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

struct DefiSnapshotTests {
    let s = defiSnapshot(fixture("defi-two-displays"))

    @Test("each display lists its workspaces in order, without the inactive trailing one")
    func workspacesPerDisplay() {
        #expect(s.perMonitor["1"]?.workspaces == ["__defi_dynamic_1", "dev", "__defi_dynamic_3"])
        #expect(s.perMonitor["1"]?.visible == "__defi_dynamic_3")
    }

    @Test("an active trailing workspace shows, so the display marks where it is")
    func activeTrailing() {
        #expect(s.perMonitor["2"]?.workspaces == ["__defi_dynamic_4"])
        #expect(s.perMonitor["2"]?.visible == "__defi_dynamic_4")
    }

    @Test("a chip shows the workspace name, or else its position")
    func labels() {
        #expect(s.labels["__defi_dynamic_1"] == "1")
        #expect(s.labels["dev"] == "dev")
        #expect(s.labels["__defi_dynamic_4"] == "1")
    }

    @Test("the focused display gives the focused workspace and app")
    func focus() {
        #expect(s.focused == "__defi_dynamic_3")
        #expect(s.focusedApp == "dev.herdr.app")
    }

    @Test("occupied workspaces carry their apps")
    func apps() {
        #expect(s.occupied == ["__defi_dynamic_1", "__defi_dynamic_3"])
        #expect(s.wsApps["__defi_dynamic_1"] == ["com.microsoft.Outlook", "com.microsoft.teams2"])
    }

    @Test("an unknown state version gives an empty snapshot")
    func unknownVersion() {
        var json = fixture("defi-two-displays")
        json["version"] = 3
        #expect(defiSnapshot(json).perMonitor.isEmpty)
    }
}
