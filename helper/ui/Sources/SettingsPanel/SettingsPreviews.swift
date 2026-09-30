#if DEBUG
import SwiftUI
#if canImport(PanelDesigns)
import PanelDesigns
#endif

extension SettingsReport {
    static let iconOrLabel: [Choice] = [.init(nil, "Icon and label"), .init("icon", "Icon only")]
    static let shownOnly: [Choice] = [.init(nil, "Shown")]

    static let sample = SettingsReport(
        pills: [
            Pill(key: "media", title: "Music", symbol: "music.note", tint: "pink",
                 summary: "The song that plays in Music. Shows while Music plays.", canHide: false,
                 numbers: [Number(key: "media", title: "Title length, in characters", range: 8...80, fallback: 28, value: 49),
                           Number(key: "media_notch", title: "Title length beside the notch", range: 8...80, fallback: 20, value: nil)],
                 switches: [Switch(key: "media_notch_fill", title: "Grow up to the notch", off: "no", value: nil)]),
            Pill(key: "menubar", title: "Menu Bar Apps", symbol: "menubar.rectangle", tint: "gray",
                 summary: "The icons that apps put in the menu bar.", styles: shownOnly),
            Pill(key: "weather", title: "Weather", symbol: "cloud.sun.fill", tint: "blue",
                 summary: "The weather here, from wttr.in.", styles: iconOrLabel),
            Pill(key: "wifi", title: "Wi-Fi", symbol: "wifi", tint: "blue",
                 summary: "The network and nearby networks. The status pill shows it too.", optIn: true,
                 styles: [.init("show", "Icon and label"), .init("icon", "Icon only")]),
            Pill(key: "bluetooth", title: "Bluetooth", symbol: "wave.3.right", tint: "blue",
                 summary: "Paired devices, to connect or disconnect.", value: "hide", styles: iconOrLabel),
            Pill(key: "brightness", title: "Display", symbol: "sun.max.fill", tint: "yellow",
                 summary: "Brightness, extra dimming and Night Shift.", value: "hide", styles: iconOrLabel),
            Pill(key: "mic", title: "Microphone", symbol: "mic.slash.fill", tint: "red",
                 summary: "Shows only while the microphone is muted. Super+M mutes it.", styles: shownOnly,
                 switches: [.init(key: "mic_hud", title: "Show a HUD when the microphone mutes", off: "off",
                                  value: nil)]),
            Pill(key: "volume", title: "Sound", symbol: "speaker.wave.2.fill", tint: "pink",
                 summary: "Volume and the output device.", value: "muted",
                 styles: iconOrLabel + [.init("muted", "Only while muted")],
                 switches: [.init(key: "volume_hud", title: "Show the volume HUD", off: "off", value: nil),
                            .init(key: "volume_click", title: "Click when the volume changes", off: "off",
                                  value: "off")]),
            Pill(key: "status", title: "Status", symbol: "gauge.with.dots.needle.67percent", tint: "green",
                 summary: "Battery and network in one gauge.", styles: shownOnly),
            Pill(key: "battery", title: "Battery", symbol: "battery.75percent", tint: "green",
                 summary: "The charge. The status pill shows it too.", optIn: true,
                 styles: [.init("show", "Icon and label"), .init("icon", "Icon only"), .init("time", "With time left")]),
            Pill(key: "clock", title: "Clock", symbol: "clock.fill", tint: "red",
                 summary: "The date and time, and today’s events.", styles: iconOrLabel,
                 panelValue: "month"),
            Pill(key: "activity", title: "Activity", symbol: "cpu", tint: "gray",
                 summary: "CPU and memory, and the busiest apps.", styles: shownOnly),
            Pill(key: "claude", title: "AI Usage", symbol: "sparkles", tint: "orange",
                 summary: "Plan usage of your AI tools.", group: .plugins, styles: iconOrLabel,
                 aiUsage: AIUsageOptions(command: "omacchiato-ai-usage --pill claude,codex:weekly --panel claude,codex,copilot --open claude"),
                 plugin: PluginFields(command: "omacchiato-ai-usage --pill claude,codex:weekly --panel claude,codex,copilot --open claude",
                                      interval: 300)),
            Pill(key: "github", title: "Pull Requests", symbol: "arrow.triangle.pull", tint: "purple",
                 summary: "Your open pull requests on GitHub.", group: .plugins, styles: iconOrLabel,
                 plugin: PluginFields(command: "omacchiato-github-prs -repo:wicksipedia/activity", interval: 300,
                                      args: .search, shownIcon: "\u{f407}")),
            Pill(key: "cpu", title: "Stats", symbol: "chart.bar.fill", tint: "teal", summary: "CPU, memory or disk use.",
                 group: .plugins, styles: iconOrLabel,
                 plugin: PluginFields(command: "omacchiato-stats cpu", interval: 10, icon: "\u{f4bc}", iconColor: "accent",
                                      args: .stats)),
            Pill(key: "keepawake", title: "Keep Awake", symbol: "cup.and.saucer.fill", tint: "orange",
                 summary: "Shows while an app keeps the Mac awake.", group: .plugins, styles: iconOrLabel,
                 numbers: [Number(key: "keep_awake_jiggle", title: "Move the mouse every, in minutes (0 is off)",
                                  range: 0...10, fallback: 1, value: nil),
                           Number(key: "keep_awake_battery", title: "Turn off on battery at, in percent (0 is off)",
                                  range: 0...90, fallback: 20, value: nil)],
                 switches: [.init(key: "keep_awake_display", title: "Let the display sleep", off: "on", value: nil),
                            .init(key: "keep_awake_lid", title: "Stay awake with the lid closed", off: "off", value: nil),
                            .init(key: "keep_awake_hud", title: "Show a HUD when keep awake changes", off: "off",
                                  value: nil)],
                 plugin: PluginFields(command: "omacchiato-keep-awake", interval: 10)),
            Pill(key: "hello", title: "Hello", symbol: "puzzlepiece.extension.fill", tint: "purple", summary: "A plugin pill.",
                 group: .plugins, styles: iconOrLabel, plugin: PluginFields(command: "echo hi", interval: 45)),
        ],
        numbers: [
            Number(key: "left_gap", title: "Gap between left pills", range: 0...24, fallback: 6, value: nil),
            Number(key: "right_gap", title: "Gap between right pills", range: 0...24, fallback: 6, value: 8),
        ],
        files: [
            File(name: "bar-pills.conf", url: URL(fileURLWithPath: "/Users/me/.config/omacchiato/bar-pills.conf"),
                 text: "bluetooth = hide\nvolume = muted\nmedia = 49\n"),
            File(name: "bar-plugins.conf", url: URL(fileURLWithPath: "/Users/me/.config/omacchiato/bar-plugins.conf"),
                 text: "[github]\ncommand = omacchiato-github-prs\ninterval = 300\n"),
        ],
        quitOnClose: QuitOnClose(on: true, kept: [
            .init(id: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app"),
            .init(id: "com.apple.Music", name: "Music", path: "/System/Applications/Music.app"),
            .init(id: "com.raycast.macos", name: "Raycast"),
        ], running: [.init(id: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")]))
}

private let size = (width: CGFloat(760), height: CGFloat(580))

// The real panels with their sample data, as the bar passes them.
private let actions: SettingsActions = {
    var actions = SettingsActions()
    actions.preview = { designPreview(kind: $0, design: $1) }
    return actions
}()

private let report: SettingsReport = {
    var report = SettingsReport.sample
    let kinds = ["status": "status", "menubar": "menubar", "clock": "clock", "activity": "activity",
                 "claude": "ai-usage", "github": "github-prs"]
    for i in report.pills.indices {
        guard let kind = kinds[report.pills[i].key], let designs = panelDesignNames[kind] else { continue }
        report.pills[i].panelKind = kind
        report.pills[i].panelDesigns = designs.map { .init($0.value, $0.title) }
    }
    return report
}()

private func page(_ page: SettingsView.Page, height: CGFloat = size.height) -> some View {
    SettingsView(report: report, actions: actions, page: page).frame(width: size.width, height: height)
}

#Preview("AI Usage") { page(.pill("claude"), height: 900) }
#Preview("Pull Requests") { page(.pill("github"), height: 900) }
#Preview("Stats") { page(.pill("cpu")) }
#Preview("A custom plugin") { page(.pill("hello")) }
#Preview("Keep Awake") { page(.pill("keepawake")) }
#Preview("Quit on Close") { page(.quitOnClose) }
#Preview("Music") { page(.pill("media")) }
#Preview("Sound, with a mode") { page(.pill("volume")) }
#Preview("Microphone") { page(.pill("mic")) }
#Preview("A hidden pill") { page(.pill("bluetooth")) }
#Preview("An opt-in pill") { page(.pill("battery")) }
#Preview("Clock") { page(.pill("clock"), height: 900) }
#Preview("Status") { page(.pill("status"), height: 900) }
#Preview("Layout") { page(.layout) }
#Preview("Add Plugin") { page(.addPlugin) }
#Preview("Config Files") { page(.files) }
#Preview("Light") { page(.pill("clock")).preferredColorScheme(.light) }
#endif
