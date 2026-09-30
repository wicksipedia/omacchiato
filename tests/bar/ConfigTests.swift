import Testing
@testable import omacchiato_bar

@Suite struct ConfigTests {
    @Test("a conf file reads as key-value pairs, and comments and bad lines are skipped")
    func conf() {
        let text = "# a comment\nvolume = muted\n\nnot a setting\nmedia=49\n  clock = hide  \n"
        #expect(parseConf(text) == ["volume": "muted", "media": "49", "clock": "hide"])
    }

    @Test("plugins read from INI sections, and a section with no command or a built-in name is dropped")
    func plugins() {
        let text = """
        [github]
        command = gh-prs
        interval = 0
        [empty]
        icon = x
        [clock]
        command = date
        [github]
        command = again
        """
        let plugins = parsePlugins(text)
        #expect(plugins.map(\.name) == ["github"])
        #expect(plugins.first?.command == "gh-prs")
        #expect(plugins.first?.interval == 1)
    }

    @Test("the pill order hides hidden pills and shows opt-in pills only when named")
    func order() {
        let plugins = [BarPlugin(name: "github", command: "x")]
        let order = pillOrder(modes: ["clock": "hide", "battery": "time", "github": "icon"], plugins: plugins)
        #expect(order.first == "menubar")
        #expect(order.contains("github"))
        #expect(order.contains("battery"))
        #expect(!order.contains("wifi"))
        #expect(!order.contains("clock"))
    }

    @Test("a saved order moves built-in and plugin pills, and the rest follow in the default order")
    func savedOrder() {
        let plugins = [BarPlugin(name: "github", command: "x"), BarPlugin(name: "claude", command: "y")]
        let order = pillOrder(modes: ["order": "clock, github, status"], plugins: plugins)
        #expect(Array(order.prefix(3)) == ["clock", "github", "status"])
        #expect(Array(order.dropFirst(3)) == ["menubar", "claude", "weather", "bluetooth", "brightness",
                                              "mic", "volume", "activity"])
    }

    @Test("a saved order drops unknown names and repeats; with no order the bar keeps its default")
    func savedOrderEdges() {
        let plugins = [BarPlugin(name: "github", command: "x")]
        let plain = pillOrder(modes: [:], plugins: plugins)
        #expect(pillOrder(modes: ["order": "gone, clock, clock"], plugins: plugins)
                == ["clock"] + plain.filter { $0 != "clock" })
        #expect(pillOrder(modes: ["order": ""], plugins: plugins) == plain)
    }

    @Test("a hidden pill keeps its place in the saved order and comes back to it")
    func hiddenKeepsPlace() {
        let full = fullPillOrder(modes: ["order": "clock, status", "clock": "hide"], plugins: [])
        #expect(Array(full.prefix(2)) == ["clock", "status"])
        #expect(pillOrder(modes: ["order": "clock, status", "clock": "hide"], plugins: []).first == "status")
    }

    @Test("a reload stops removed, hidden and changed plugins, and starts new, shown and changed ones")
    func changes() {
        let a = BarPlugin(name: "a", command: "x"), b = BarPlugin(name: "b", command: "y")
        let c = BarPlugin(name: "c", command: "z"), b2 = BarPlugin(name: "b", command: "y2")
        let change = pluginChanges(old: [a, b, c], oldOrder: ["a", "b"],
                                   new: [a, b2, c], newOrder: ["b", "c"])
        #expect(change.stop == ["a", "b"])
        #expect(change.start.map(\.name) == ["b", "c"])
        let same = pluginChanges(old: [a], oldOrder: ["a"], new: [a], newOrder: ["a"])
        #expect(same.stop.isEmpty && same.start.isEmpty)
    }
}

@Suite struct SettingsCoverageTests {
    @Test("the settings window has a page for every pill the bar can draw")
    func everyPill() {
        let keys = Set(settingsReport().pills.map(\.key))
        for pill in ["menubar"] + rightOrderAll + barPlugins.map(\.name) {
            #expect(keys.contains(pill), "no settings page for \(pill)")
        }
    }
}
