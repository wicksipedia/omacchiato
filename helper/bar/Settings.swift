import AppKit
import SwiftUI
#if canImport(StatusGauge)
import PanelDesigns
import SettingsPanel
import ThemePanel
#endif

// --- the Omacchiato Settings window -----------------------------------------

// What each pill's page offers. Keep in sync with the code that reads each
// key: pillOrder and iconOnly (Plugins.swift), updateVolume and
// updateBattery (Providers.swift), panelView (Popups.swift), leftGap,
// rightGap and mediaMaxWidth (BarView.swift).
struct PillInfo {
    var title: String
    var symbol: String
    var tint: String
    var summary: String
    var extras: [SettingsReport.Choice] = []
    var styled = true                    // false for a pill with no label, where "icon only" does nothing
}

let builtinPills: [String: PillInfo] = [
    "menubar": .init(title: "Menu Bar Apps", symbol: "menubar.rectangle", tint: "gray",
                     summary: "The icons that apps put in the menu bar.", styled: false),
    "weather": .init(title: "Weather", symbol: "cloud.sun.fill", tint: "blue",
                     summary: "The weather here, from wttr.in."),
    "wifi": .init(title: "Wi-Fi", symbol: "wifi", tint: "blue",
                  summary: "The network and nearby networks. The status pill shows it too."),
    "bluetooth": .init(title: "Bluetooth", symbol: "wave.3.right", tint: "blue",
                       summary: "Paired devices, to connect or disconnect."),
    "brightness": .init(title: "Display", symbol: "sun.max.fill", tint: "yellow",
                        summary: "Brightness, extra dimming and Night Shift."),
    "mic": .init(title: "Microphone", symbol: "mic.slash.fill", tint: "red",
                 summary: "Shows only while the microphone is muted. Super+M mutes it.", styled: false),
    "volume": .init(title: "Sound", symbol: "speaker.wave.2.fill", tint: "pink",
                    summary: "Volume and the output device.", extras: [.init("muted", "Only while muted")]),
    "status": .init(title: "Status", symbol: "gauge.with.dots.needle.67percent", tint: "green",
                    summary: "Battery and network in one gauge.", styled: false),
    "battery": .init(title: "Battery", symbol: "battery.75percent", tint: "green",
                     summary: "The charge. The status pill shows it too.",
                     extras: [.init("time", "With time left")]),
    "clock": .init(title: "Clock", symbol: "clock.fill", tint: "red",
                   summary: "The date and time, and today’s events."),
    "activity": .init(title: "Activity", symbol: "cpu", tint: "gray",
                      summary: "CPU and memory in one icon. Its popup lists the busiest apps.", styled: false),
]

// A plugin's page takes its look from the script it runs. A plugin prints
// no panel while its pill is empty, so the panel's kind cannot say.
let pluginPrograms = ["omacchiato-ai-usage": "ai-usage", "omacchiato-github-prs": "github-prs",
                      "omacchiato-airpods": "airpods", "omacchiato-keep-awake": "keep-awake",
                      "omacchiato-updates": "updates", "omacchiato-stats": "stats"]

let pluginKinds: [String: PillInfo] = [
    "ai-usage": .init(title: "AI Usage", symbol: "sparkles", tint: "orange", summary: "Plan usage of your AI tools."),
    "github-prs": .init(title: "Pull Requests", symbol: "arrow.triangle.pull", tint: "purple",
                        summary: "Your open pull requests on GitHub."),
    "airpods": .init(title: "AirPods", symbol: "airpods.pro", tint: "gray",
                     summary: "Battery and noise control, while AirPods are connected."),
    "keep-awake": .init(title: "Keep Awake", symbol: "cup.and.saucer.fill", tint: "orange",
                        summary: "Shows while an app keeps the Mac awake."),
    "updates": .init(title: "Updates", symbol: "arrow.down.circle.fill", tint: "blue",
                     summary: "Shows when a new Omacchiato release is out."),
    "stats": .init(title: "Stats", symbol: "chart.bar.fill", tint: "teal",
                   summary: "One number in the bar: CPU, memory or disk use. For the busiest apps, use Activity."),
]

let panelDesigns = panelDesignNames.mapValues { $0.map { SettingsReport.Choice($0.value, $0.title) } }

func settingsReport() -> SettingsReport {
    func pill(_ key: String, _ info: PillInfo, group: SettingsReport.Pill.Group, designs: String) -> SettingsReport.Pill {
        let optIn = optInPills.contains(key)
        // An opt-in pill needs a value to show, so its default style is "show".
        let styles: [SettingsReport.Choice] = info.styled
            ? [.init(optIn ? "show" : nil, "Icon and label"), .init("icon", "Icon only")] + info.extras
            : [.init(optIn ? "show" : nil, "Shown")] + info.extras
        return .init(key: key, title: info.title, symbol: info.symbol, tint: info.tint, summary: info.summary,
                     group: group, optIn: optIn, value: pillModes[key], styles: styles,
                     panelDesigns: panelDesigns[designs] ?? [], panelValue: pillModes[key + "_panel"],
                     panelKind: panelDesigns[designs] == nil ? nil : designs)
    }
    var pills = ["menubar"].compactMap { key in builtinPills[key].map { pill(key, $0, group: .bar, designs: key) } }
    for key in rightOrderAll {
        guard let info = builtinPills[key] else { continue }
        var page = pill(key, info, group: .bar, designs: key)
        pills.append(page)
    }
    for plugin in barPlugins {
        let program = (plugin.command.split(separator: " ").first.map(String.init) ?? "") as NSString
        let kind = pluginPrograms[program.lastPathComponent] ?? pluginPanels[plugin.name]?["kind"] as? String ?? ""
        let info = pluginKinds[kind]
            ?? PillInfo(title: plugin.name.prefix(1).uppercased() + plugin.name.dropFirst(),
                        symbol: "puzzlepiece.extension.fill", tint: "purple", summary: "A plugin pill.")
        var page = pill(plugin.name, info, group: kind == "keep-awake" ? .features : .plugins, designs: kind)
        page.plugin = .init(command: plugin.command, interval: Int(plugin.interval), icon: plugin.icon,
                            iconColor: plugin.iconColor,
                            args: kind == "github-prs" ? .search : kind == "stats" ? .stats : .none,
                            shownIcon: rightItems[plugin.name]?.icon ?? "")
        if kind == "ai-usage" { page.aiUsage = AIUsageOptions(command: plugin.command) }
        if kind == "keep-awake" {
            page.numbers = [number("keep_awake_jiggle", "Move the mouse every", 0...10, 1, unit: "min", zeroIsOff: true),
                            number("keep_awake_battery", "Turn off on battery at", 0...90, 20, unit: "%", zeroIsOff: true)]
            // on by default, so the switch is off when the key holds its "off" value
            page.switches = [.init(key: "keep_awake_display", title: "Let the display sleep", off: "on",
                                   value: pillModes["keep_awake_display"]),
                             .init(key: "keep_awake_lid", title: "Stay awake with the lid closed", off: "off",
                                   value: pillModes["keep_awake_lid"])]
        }
        pills.append(page)
    }
    func number(_ key: String, _ title: String, _ range: ClosedRange<Int>, _ fallback: Int,
                unit: String = "", zeroIsOff: Bool = false) -> SettingsReport.Number {
        .init(key: key, title: title, range: range, fallback: fallback, value: pillModes[key].flatMap { Int($0) },
              unit: unit, zeroIsOff: zeroIsOff)
    }
    // The music pill shows while Music plays, so it has no key to hide it.
    pills.insert(.init(key: "media", title: "Music", symbol: "music.note", tint: "pink",
                       summary: "The song that plays in Music, at the left of the bar, while Music plays.",
                       canHide: false,
                       numbers: [number("media", "Title length", 8...80, 28, unit: "characters"),
                                 number("media_notch", "Title length beside the notch", 8...80, 20, unit: "characters")],
                       switches: [.init(key: "media_notch_fill", title: "Grow up to the notch", off: "no",
                                        value: pillModes["media_notch_fill"])]), at: 0)
    let numbers = [number("left_gap", "Gap between left pills", 0...24, 6, unit: "pt"),
                   number("right_gap", "Gap between right pills", 0...24, 6, unit: "pt")]
    let files = liveConfigFiles.enumerated().map { i, name in
        SettingsReport.File(name: name, url: configDir.appendingPathComponent(name), text: configTexts[i])
    }
    return SettingsReport(pills: pills, numbers: numbers, files: files, theme: settingsThemes,
                          quitOnClose: quitOnCloseReport(),
                          order: fullPillOrder(modes: pillModes, plugins: barPlugins),
                          orderSaved: pillModes["order"] != nil, debug: pillModes["debug"] == "on",
                          huds: hudSwitches.map { .init(key: $0.key, title: $0.title, off: "off", value: pillModes[$0.key]) },
                          hudPosition: pillModes["hud_position"])
}

// The HUDs and the volume click, on one page. Each is on unless its key is off.
let hudSwitches = [(key: "volume_hud", title: "Volume HUD when a volume key is pressed"),
                   (key: "volume_click", title: "Click when the volume changes"),
                   (key: "mic_hud", title: "Microphone HUD when it mutes or unmutes"),
                   (key: "keep_awake_hud", title: "Keep Awake HUD when it turns on or off")]

func quitOnCloseReport() -> SettingsReport.QuitOnClose {
    func app(_ id: String) -> SettingsReport.QuitOnClose.App {
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
        let name = path.map { FileManager.default.displayName(atPath: $0) } ?? id
        return .init(id: id, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, path: path)
    }
    let text = (try? String(contentsOf: quitOnCloseFile, encoding: .utf8)) ?? ""
    // the file's order, which is the order the user added them in
    let kept = text.split(separator: "\n").compactMap { parseExceptions(String($0)).first }
    let running = NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .compactMap(\.bundleIdentifier)
        .filter { id in !kept.contains(id) && !neverQuitPrefixes.contains(where: { id.hasPrefix($0) }) }
    return .init(on: pillModes["quit_on_close"] == "on", kept: kept.map(app),
                 running: Set(running).map(app).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
}

// A change applies at once: the bar reloads here, so it does not wait for
// the watcher, which then finds nothing new.
func applyConfig(_ name: String, _ text: String) {
    writeConfig(name, text)
    configTexts = liveConfigFiles.map(confText)
    reloadConfig()
}

let settingsActions: SettingsActions = {
    var actions = SettingsActions()
    actions.set = { key, value in
        applyConfig("bar-pills.conf", confSet(confText("bar-pills.conf"), key: key, value: value))
    }
    actions.save = { applyConfig($0, $1) }
    actions.theme = themeActions
    actions.preview = { designPreview(kind: $0, design: $1) }
    actions.setPlugin = { plugin, key, value in
        applyConfig("bar-plugins.conf", iniSet(confText("bar-plugins.conf"), section: plugin, key: key, value: value))
    }
    actions.addPlugin = { name, command in
        applyConfig("bar-plugins.conf", iniSet(confText("bar-plugins.conf"), section: name, key: "command", value: command))
    }
    actions.removePlugin = { name in
        applyConfig("bar-plugins.conf", iniRemove(confText("bar-plugins.conf"), section: name))
    }
    actions.setQuitExceptions = { ids in
        try? quitExceptionsText(ids).write(to: quitOnCloseFile, atomically: true, encoding: .utf8)
        refreshSettings()
    }
    actions.setOrder = { keys in
        applyConfig("bar-pills.conf", confSet(confText("bar-pills.conf"), key: "order",
                                              value: keys?.joined(separator: ", ")))
    }
    actions.pickQuitException = {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Keep Open"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        settingsActions.setQuitExceptions(quitOnCloseReport().kept.map(\.id) + [id])
    }
    actions.reveal = { url in
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
    // -t opens the default text editor: macOS maps no app to .conf.
    actions.open = { url in
        if !FileManager.default.fileExists(atPath: url.path) { writeConfig(url.lastPathComponent, "") }
        DispatchQueue.global(qos: .userInitiated).async { _ = shell("/usr/bin/open", ["-t", url.path]) }
    }
    return actions
}()

// The bar is an agent app with no menu bar, so the window maps the edit
// and close keys itself.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector?
        switch key {
        case "w": close(); return true
        case "x": action = #selector(NSText.cut(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        case "z": action = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// The themes, read when the window opens and after Apply. Each theme loads
// its wallpaper, too slow to repeat on every change of a setting.
var settingsThemes: ThemeReport?

var settingsWindow: SettingsWindow?
var settingsCloseObserver: NSObjectProtocol?
var settingsPrevApp: NSRunningApplication?

// A link from a popup opens its pill's page. A new id resets the page
// that the window keeps as state; a refresh keeps the id and the page.
var settingsLink = (page: SettingsView.Page.layout, id: 0)

func showSettings() { showSettings(page: nil) }

// Keep in sync with GLYPHS in install.sh.
let glyphNamesFile = NSString(string: "~/.local/lib/nerd-font-glyphnames.json").expandingTildeInPath

func showSettings(page: SettingsView.Page?) {
    closePopup()
    settingsThemes = themeReport()
    if GlyphLibrary.glyphs.isEmpty, let data = FileManager.default.contents(atPath: glyphNamesFile) {
        GlyphLibrary.glyphs = loadGlyphs(data)
    }
    if let page {
        settingsLink = (page, settingsLink.id + 1)
        (settingsWindow?.contentViewController as? NSHostingController<AnyView>)?.rootView = settingsRoot()
    }
    if settingsWindow == nil {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                    backing: .buffered, defer: false)
        window.title = "Omacchiato Settings"
        window.isReleasedWhenClosed = false
        // A hosting controller, not a bare hosting view: only it keeps the
        // page below the toolbar that the split view adds.
        window.contentViewController = NSHostingController(rootView: settingsRoot())
        window.setContentSize(NSSize(width: 760, height: 580))
        window.center()
        settingsCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                               queue: .main) { _ in
            settingsPrevApp?.activate()
            settingsPrevApp = nil
            // A closed window kept every page's views, the theme wallpapers
            // and the icon list: about 80 MB. The next open builds them again.
            DispatchQueue.main.async {
                settingsCloseObserver.map(NotificationCenter.default.removeObserver)
                settingsCloseObserver = nil
                settingsWindow = nil
                settingsThemes = nil
                GlyphLibrary.glyphs = []
                // the allocator keeps freed pages until asked; give them back now
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { malloc_zone_pressure_relief(nil, 0) }
            }
        }
        settingsWindow = window
    }
    if settingsPrevApp == nil, NSWorkspace.shared.frontmostApplication != .current {
        settingsPrevApp = NSWorkspace.shared.frontmostApplication
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
}

func refreshSettings() {
    guard let window = settingsWindow, window.isVisible,
          let host = window.contentViewController as? NSHostingController<AnyView> else { return }
    host.rootView = settingsRoot()
}

func settingsRoot() -> AnyView {
    AnyView(SettingsView(report: settingsReport(), actions: settingsActions, page: settingsLink.page).id(settingsLink.id))
}
