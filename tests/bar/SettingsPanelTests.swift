import Foundation
import SwiftUI
import Testing
@testable import SettingsPanel

@Suite struct SettingsPanelTests {
    let file = "# pills\nvolume = muted\n\n# the title\nmedia = 49\n"

    @Test("setting a key changes its line and keeps the comments, blank lines and order")
    func replace() {
        #expect(confSet(file, key: "media", value: "30") == "# pills\nvolume = muted\n\n# the title\nmedia = 30\n")
    }

    @Test("a new key goes at the end")
    func add() {
        #expect(confSet(file, key: "clock", value: "hide") == file + "clock = hide\n")
        #expect(confSet("", key: "clock", value: "hide") == "clock = hide\n")
    }

    @Test("a nil value removes the key, and a commented-out line stays")
    func remove() {
        let text = "# volume = hide\nvolume = muted\n"
        #expect(confSet(text, key: "volume", value: nil) == "# volume = hide\n")
    }

    @Test("with the key twice, the last line changes and the earlier one goes")
    func duplicate() {
        #expect(confSet("a = 1\nb = 2\na = 3\n", key: "a", value: "4") == "b = 2\na = 4\n")
    }

    @Test("a file with no change comes back the same, with a newline at the end")
    func roundTrip() {
        #expect(confSet(file, key: "volume", value: "muted") == file)
        #expect(confSet("volume = muted", key: "volume", value: "muted") == "volume = muted\n")
    }

    @Test("an ordinary pill shows with no key and hides with hide")
    func toggle() {
        let styles: [SettingsReport.Choice] = [.init(nil, "Icon and label"), .init("icon", "Icon only")]
        let pill = SettingsReport.Pill(key: "clock", title: "Clock", symbol: "clock", styles: styles)
        #expect(pill.shown)
        #expect(pill.value(shown: false) == "hide")
        #expect(pill.value(shown: true) == nil)
        var hidden = pill
        hidden.value = "hide"
        #expect(!hidden.shown)
        #expect(hidden.style == nil)
    }

    @Test("an opt-in pill shows only with a value, and turns on with its first style")
    func optIn() {
        let pill = SettingsReport.Pill(key: "battery", title: "Battery", symbol: "battery.75percent", optIn: true,
                                       styles: [.init("show", "Icon and label"), .init("time", "With time left")])
        #expect(!pill.shown)
        #expect(pill.value(shown: true) == "show")
        #expect(pill.value(shown: false) == nil)
    }

    @Test("a value that no style names is added to the picker")
    func unknownValue() {
        let pill = SettingsReport.Pill(key: "volume", title: "Sound", symbol: "speaker", value: "loud",
                                       styles: [.init(nil, "Icon and label"), .init("icon", "Icon only")])
        #expect(pill.shownStyles.map(\.title) == ["Icon and label", "Icon only", "loud"])
    }

    let plugins = "# my plugins\n[github]\ncommand = gh-prs\n\n[claude]\ncommand = ai\ninterval = 300\n"

    @Test("an INI key changes inside its own section only")
    func iniReplace() {
        #expect(iniSet(plugins, section: "claude", key: "interval", value: "60")
            == "# my plugins\n[github]\ncommand = gh-prs\n\n[claude]\ncommand = ai\ninterval = 60\n")
    }

    @Test("a new INI key goes after the section's last line, before the blank line")
    func iniAdd() {
        #expect(iniSet(plugins, section: "github", key: "interval", value: "300")
            == "# my plugins\n[github]\ncommand = gh-prs\ninterval = 300\n\n[claude]\ncommand = ai\ninterval = 300\n")
    }

    @Test("a new section goes at the end")
    func iniNewSection() {
        #expect(iniSet(plugins, section: "hello", key: "command", value: "echo hi").hasSuffix("interval = 300\n\n[hello]\ncommand = echo hi\n"))
    }

    @Test("removing a section takes its blank line with it")
    func iniRemoveSection() {
        #expect(iniRemove(plugins, section: "github") == "# my plugins\n[claude]\ncommand = ai\ninterval = 300\n")
        #expect(iniRemove(plugins, section: "claude") == "# my plugins\n[github]\ncommand = gh-prs\n")
    }

    @Test("the AI usage flags read and write back, and unknown flags stay")
    func aiUsage() throws {
        let o = try #require(AIUsageOptions(command: "/bin/ai --pill claude,codex:weekly --extra x --panel=claude --inline"))
        #expect(o.pill == [.init(id: "claude"), .init(id: "codex", window: "weekly")])
        #expect(o.panelIDs == ["claude"])
        #expect(o.openIDs == ["claude"])
        #expect(o.inline)
        #expect(o.command == "/bin/ai --extra x --pill claude,codex:weekly --panel claude --inline")
        #expect(AIUsageOptions(command: "ai --pill 'claude'") == nil)
    }

    @Test("a provider toggles in the providers' order")
    func toggled() {
        #expect(AIUsageOptions.toggled(["copilot"], "claude", true) == ["claude", "copilot"])
        #expect(AIUsageOptions.toggled(["claude", "copilot"], "claude", false) == ["copilot"])
    }

    @Test("a plugin's argument is what follows its program")
    func argument() {
        let f = SettingsReport.PluginFields(command: "omacchiato-stats  cpu")
        #expect(f.program == "omacchiato-stats")
        #expect(f.argument == "cpu")
        #expect(f.with(argument: "ram") == "omacchiato-stats ram")
        #expect(f.with(argument: "") == "omacchiato-stats")
    }

    @Test("the quit-on-close exceptions write one bundle ID a line, once each, in order, under the header")
    func quitExceptions() {
        #expect(quitExceptionsText(["com.apple.Music", "com.raycast.macos", "com.apple.Music"])
                == quitExceptionsHeader + "\ncom.apple.Music\ncom.raycast.macos\n")
        #expect(quitExceptionsText([]) == quitExceptionsHeader + "\n")
    }

    @Test("the sidebar lists Music on the left, shown pills in bar order, then hidden ones, and features apart")
    func sidebar() {
        typealias Pill = SettingsReport.Pill
        let report = SettingsReport(pills: [
            Pill(key: "media", title: "Music", symbol: "", canHide: false),
            Pill(key: "clock", title: "Clock", symbol: ""),
            Pill(key: "wifi", title: "Wi-Fi", symbol: "", optIn: true),
            Pill(key: "status", title: "Status", symbol: ""),
            Pill(key: "github", title: "Pull Requests", symbol: "", group: .plugins),
            Pill(key: "keepawake", title: "Keep Awake", symbol: "", group: .features),
        ], order: ["github", "status", "wifi", "clock", "keepawake"])
        let sidebar = report.sidebar
        #expect(sidebar.left.map(\.key) == ["media"])
        #expect(sidebar.shown.map(\.key) == ["github", "status", "clock"])
        #expect(sidebar.hidden.map(\.key) == ["wifi"])
        #expect(sidebar.features.map(\.key) == ["keepawake"])
    }

    @Test("one control shows, hides or styles a pill; an opt-in pill hides with no key")
    func visibility() {
        typealias Pill = SettingsReport.Pill
        let styles: [SettingsReport.Choice] = [.init(nil, "Icon and label"), .init("icon", "Icon only")]
        let volume = Pill(key: "volume", title: "Sound", symbol: "", value: "hide", styles: styles)
        #expect(volume.visibilityChoices.map(\.title) == ["Icon and label", "Icon only", "Hidden"])
        #expect(volume.visibility == "hide")
        #expect(Pill(key: "volume", title: "Sound", symbol: "", value: "icon", styles: styles).visibility == "icon")

        let wifi = Pill(key: "wifi", title: "Wi-Fi", symbol: "", optIn: true, styles: [.init("show", "Shown")])
        #expect(wifi.visibilityChoices.map(\.value) == ["show", nil])
        #expect(wifi.visibility == nil)

        let music = Pill(key: "media", title: "Music", symbol: "", canHide: false)
        #expect(!music.visibilityChoices.contains { $0.title == "Hidden" })
    }

    @Test("a number reads with its unit, and 0 reads as Off where 0 turns the option off")
    func numberText() {
        typealias Number = SettingsReport.Number
        let jiggle = Number(key: "keep_awake_jiggle", title: "Move the mouse every", range: 0...10, fallback: 1,
                            value: nil, unit: "min", zeroIsOff: true)
        #expect(jiggle.text(1) == "1 min")
        #expect(jiggle.text(0) == "Off")
        let battery = Number(key: "keep_awake_battery", title: "Turn off on battery at", range: 0...90, fallback: 20,
                             value: nil, unit: "%", zeroIsOff: true)
        #expect(battery.text(20) == "20%")
        #expect(Number(key: "left_gap", title: "Gap", range: 0...24, fallback: 6, value: nil, unit: "pt").text(0) == "0 pt")
        #expect(Number(key: "x", title: "X", range: 0...9, fallback: 1, value: nil).text(3) == "3")
    }

    @Test("the glyph list reads from glyphnames.json, and a search matches every word of the query")
    func glyphs() throws {
        let json = #"""
        {"METADATA": {"version": "3.5.1"},
         "md-coffee": {"char": "\#u{F0176}", "code": "f0176"},
         "md-coffee_maker": {"char": "\#u{F109F}", "code": "f109f"},
         "fa-coffee": {"char": "\#u{F0F4}", "code": "f0f4"},
         "cod-github": {"char": "\#u{EA84}", "code": "ea84"}}
        """#
        let glyphs = loadGlyphs(Data(json.utf8))
        #expect(glyphs.count == 4)
        #expect(searchGlyphs(glyphs, "coffee").map(\.name) == ["fa-coffee", "md-coffee", "md-coffee_maker"])
        #expect(searchGlyphs(glyphs, "md coffee").first?.char == "\u{F0176}")
        #expect(searchGlyphs(glyphs, "GitHub").map(\.name) == ["cod-github"])
        #expect(searchGlyphs(glyphs, "").count == 4)
        #expect(loadGlyphs(Data("not json".utf8)).isEmpty)
    }

    @Test("an inserted icon goes at the cursor, over a selection, or at the end with no cursor")
    func insertIcon() {
        let text = "icon = \nx"
        let cursor = text.index(text.startIndex, offsetBy: 7)
        #expect(insertGlyph("*", into: text, at: TextSelection(insertionPoint: cursor)) == "icon = *\nx")
        let word = text.startIndex..<text.index(text.startIndex, offsetBy: 4)
        #expect(insertGlyph("*", into: text, at: TextSelection(range: word)) == "* = \nx")
        #expect(insertGlyph("*", into: text, at: nil) == "icon = \nx*")
    }
}

