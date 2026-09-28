#if DEBUG
import SwiftUI

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
                 summary: "The icons that apps put in the menu bar.", styles: shownOnly,
                 panelDesigns: [.init(nil, "List"), .init("grid", "Grid"), .init("dock", "Dock")]),
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
                 summary: "Shows only while the microphone is muted.", styles: shownOnly),
            Pill(key: "volume", title: "Sound", symbol: "speaker.wave.2.fill", tint: "pink",
                 summary: "Volume and the output device.", value: "muted",
                 styles: iconOrLabel + [.init("muted", "Only while muted")]),
            Pill(key: "status", title: "Status", symbol: "gauge.with.dots.needle.67percent", tint: "green",
                 summary: "Battery and network in one gauge.", styles: shownOnly,
                 panelDesigns: [.init(nil, "Gauge"), .init("control-center", "Control Center"), .init("settings", "Settings")]),
            Pill(key: "battery", title: "Battery", symbol: "battery.75percent", tint: "green",
                 summary: "The charge. The status pill shows it too.", optIn: true,
                 styles: [.init("show", "Icon and label"), .init("icon", "Icon only"), .init("time", "With time left")]),
            Pill(key: "clock", title: "Clock", symbol: "clock.fill", tint: "red",
                 summary: "The date and time, and today’s events.", styles: iconOrLabel,
                 panelDesigns: [.init(nil, "Timeline"), .init("up-next", "Up Next"), .init("month", "Month")],
                 panelValue: "month"),
            Pill(key: "activity", title: "Activity", symbol: "cpu", tint: "gray",
                 summary: "CPU and memory, and the busiest apps.", styles: shownOnly,
                 panelDesigns: [.init(nil, "Monitor"), .init("widgets", "Widgets"), .init("top", "Top")]),
            Pill(key: "claude", title: "AI Usage", symbol: "sparkles", tint: "orange",
                 summary: "Plan usage of your AI tools.", group: .plugins, styles: iconOrLabel,
                 panelDesigns: [.init(nil, "Rings"), .init("screen-time", "Screen Time"), .init("forecast", "Forecast")],
                 aiUsage: AIUsageOptions(command: "omacchiato-ai-usage --pill claude,codex:weekly --panel claude,codex,copilot --open claude"),
                 plugin: PluginFields(command: "omacchiato-ai-usage --pill claude,codex:weekly --panel claude,codex,copilot --open claude",
                                      interval: 300)),
            Pill(key: "github", title: "Pull Requests", symbol: "arrow.triangle.pull", tint: "purple",
                 summary: "Your open pull requests on GitHub.", group: .plugins, styles: iconOrLabel,
                 panelDesigns: [.init(nil, "Inbox"), .init("reminders", "Reminders"), .init("tracker", "Tracker")],
                 plugin: PluginFields(command: "omacchiato-github-prs -repo:wicksipedia/activity", interval: 300,
                                      args: .search, shownIcon: "\u{f407}")),
            Pill(key: "cpu", title: "Stats", symbol: "chart.bar.fill", tint: "teal", summary: "CPU, memory or disk use.",
                 group: .plugins, styles: iconOrLabel,
                 plugin: PluginFields(command: "omacchiato-stats cpu", interval: 10, icon: "\u{f4bc}", iconColor: "accent",
                                      args: .stats)),
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
        ])
}

private let size = (width: CGFloat(760), height: CGFloat(580))

// The settings module draws no real panel, so these stand in for the
// design previews. The bar passes the real panels with their sample data.
private let standInActions: SettingsActions = {
    var actions = SettingsActions()
    actions.preview = { _, design in
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(design ?? "Default design").font(.headline)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.25)).frame(height: i == 0 ? 60 : 24)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 22))
        .foregroundStyle(.white))
    }
    return actions
}()

private let withDesigns: SettingsReport = {
    var report = SettingsReport.sample
    for i in report.pills.indices where report.pills[i].key == "clock" { report.pills[i].panelKind = "clock" }
    return report
}()

#Preview("AI Usage") { SettingsView(report: .sample, page: .pill("claude")).frame(width: size.width, height: size.height) }
#Preview("Pull Requests") { SettingsView(report: .sample, page: .pill("github")).frame(width: size.width, height: size.height) }
#Preview("Stats") { SettingsView(report: .sample, page: .pill("cpu")).frame(width: size.width, height: size.height) }
#Preview("A custom plugin") { SettingsView(report: .sample, page: .pill("hello")).frame(width: size.width, height: size.height) }
#Preview("Music") { SettingsView(report: .sample, page: .pill("media")).frame(width: size.width, height: size.height) }
#Preview("Sound, with a mode") { SettingsView(report: .sample, page: .pill("volume")).frame(width: size.width, height: size.height) }
#Preview("Microphone") { SettingsView(report: .sample, page: .pill("mic")).frame(width: size.width, height: size.height) }
#Preview("A hidden pill") { SettingsView(report: .sample, page: .pill("bluetooth")).frame(width: size.width, height: size.height) }
#Preview("An opt-in pill") { SettingsView(report: .sample, page: .pill("battery")).frame(width: size.width, height: size.height) }
#Preview("Popup designs, with stand-in panels") {
    SettingsView(report: withDesigns, actions: standInActions, page: .pill("clock")).frame(width: size.width, height: 900)
}
#Preview("Layout") { SettingsView(report: .sample).frame(width: size.width, height: size.height) }
#Preview("Add Plugin") { SettingsView(report: .sample, page: .addPlugin).frame(width: size.width, height: size.height) }
#Preview("Config Files") { SettingsView(report: .sample, page: .files).frame(width: size.width, height: size.height) }
#Preview("Light") {
    SettingsView(report: .sample, page: .pill("clock")).frame(width: size.width, height: size.height).preferredColorScheme(.light)
}
#endif
