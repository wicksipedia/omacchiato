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

struct ReservedTopTests {
    @Test("a notch strip taller than the bar needs no extra space")
    func notched() {
        #expect(reservedTop(barHeight: 34, screen: NSRect(x: 0, y: 0, width: 1800, height: 1169),
                            visible: NSRect(x: 0, y: 0, width: 1800, height: 1131)) == 0)
    }

    @Test("a display with a hidden menu bar reserves the whole bar")
    func hiddenMenuBar() {
        #expect(reservedTop(barHeight: 34, screen: NSRect(x: -806, y: 1169, width: 3440, height: 1440),
                            visible: NSRect(x: -806, y: 1169, width: 3440, height: 1440)) == 34)
    }
}

struct ColumnOrderTests {
    @Test("the apps on screen give the order, left to right")
    func seen() {
        #expect(columnOrder(["claude", "safari"], seen: ["safari", "claude"], last: []) == ["safari", "claude"])
    }

    @Test("a column scrolled off screen keeps its place from the last look")
    func partial() {
        #expect(columnOrder(["a", "b", "c"], seen: ["b"], last: ["a", "b", "c"]) == ["a", "b", "c"])
        #expect(columnOrder(["a", "b", "c"], seen: ["c", "a"], last: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test("a new app goes last, and a closed one drops out")
    func changes() {
        #expect(columnOrder(["a", "b", "d"], seen: [], last: ["b", "c", "a"]) == ["b", "a", "d"])
    }

    @Test("a hidden workspace keeps the order it showed in")
    func remembered() {
        var json: [String: Any] = ["version": 2, "monitors": [[
            "display": 1, "activeWorkspace": "w1", "focused": true,
            "workspaces": [
                ["id": "w1", "kind": "ordinary", "occupied": true, "applications": ["claude", "safari"]],
                ["id": "w2", "kind": "ordinary", "occupied": true, "applications": ["outlook"]],
            ],
        ] as [String: Any]]]
        var orders: [String: [String]] = [:]
        let shown = defiSnapshot(json, onScreen: { _ in ["safari", "claude", "herdr"] }, orders: &orders)
        #expect(shown.wsApps["w1"] == ["safari", "claude"])

        var monitor = (json["monitors"] as! [[String: Any]])[0]
        monitor["activeWorkspace"] = "w2"
        json["monitors"] = [monitor]
        let hidden = defiSnapshot(json, onScreen: { _ in ["outlook"] }, orders: &orders)
        #expect(hidden.wsApps["w1"] == ["safari", "claude"])
    }
}
