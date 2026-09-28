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
}
