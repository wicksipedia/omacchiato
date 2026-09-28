import ApplicationServices
import AppKit
import CoreAudio
import CoreBluetooth
import CoreLocation
import CoreWLAN
import EventKit
import IOBluetooth
import IOKit.ps
import SystemConfiguration
import UniformTypeIdentifiers
// swiftc builds helper/ui into this module, and SwiftPM builds it as its own.
import SwiftUI
#if canImport(StatusGauge)
import StatusGauge
import ActivityPanel
import BarPills
import AIUsagePanel
import CalendarPanel
import MenuBarPanel
import PRPanel
import RowsPanel
import StatusPanel
import ThemePanel
import WeatherPanel
#endif

// --- plugins and the right cluster ---------------------------------------

// A pill from ~/.config/omacchiato/bar-plugins.conf: one INI section per
// pill, with a shell command whose stdout becomes the label.
struct BarPlugin: Equatable {
    var name = ""
    var command = ""
    var icon = ""
    var iconColor = ""
    var interval: TimeInterval = 30
}

var barPlugins = parsePlugins(confText("bar-plugins.conf"))

func parsePlugins(_ text: String) -> [BarPlugin] {
    var found: [BarPlugin] = []
    var current: BarPlugin?
    func flush() {
        // A section with no command draws nothing, so it is not a pill.
        if let c = current, !c.command.isEmpty { found.append(c) }
        current = nil
    }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line.hasPrefix("["), line.hasSuffix("]") {
            flush()
            current = BarPlugin(name: String(line.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces))
            continue
        }
        guard current != nil, let eq = line.firstIndex(of: "=") else { continue }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "command": current?.command = value
        case "icon": current?.icon = value
        case "icon_color": current?.iconColor = value
        // A runaway interval would spawn a process per frame.
        case "interval": current?.interval = max(1, Double(value) ?? 30)
        default: break
        }
    }
    flush()
    // A plugin must not shadow a built-in pill, or set() fights its provider.
    let builtin = Set(rightOrderAll)
    var seen = Set<String>()
    return found.filter { !$0.name.isEmpty && !builtin.contains($0.name) && seen.insert($0.name).inserted }
}

// A hidden pill also skips its provider: hiding weather stops the wttr.in
// fetches, and hiding bluetooth never touches the Bluetooth grant.
// Wifi and battery are opt-in because the status gauge already shows them;
// name a pill in bar-pills.conf to bring it back.
let optInPills: Set = ["wifi", "battery"]
var rightOrder = pillOrder(modes: pillModes, plugins: barPlugins)
var iconOnly = Set(pillModes.filter { $0.value == "icon" }.keys)

func pillOrder(modes: [String: String], plugins: [BarPlugin]) -> [String] {
    (["menubar"] + plugins.map(\.name) + rightOrderAll)
        .filter { modes[$0] != "hide" && (!optInPills.contains($0) || modes[$0] != nil) }
}

// The plugins to stop and to start when the config changes. A plugin
// whose command, icon or interval changed restarts.
func pluginChanges(old: [BarPlugin], oldOrder: [String], new: [BarPlugin], newOrder: [String])
    -> (stop: [String], start: [BarPlugin]) {
    let was = old.filter { oldOrder.contains($0.name) }
    let now = new.filter { newOrder.contains($0.name) }
    return (was.filter { !now.contains($0) }.map(\.name), now.filter { !was.contains($0) })
}

var rightItems: [String: BarItem] = [:]
// Rows the plugin last returned, keyed by pill name.
var pluginRows: [String: [PopupRow]] = [:]
// A plugin's panel object, when it has a SwiftUI panel. Replaces the popup rows.
var pluginPanels: [String: [String: Any]] = [:]

func set(_ name: String, _ mutate: (inout BarItem) -> Void) {
    var item = rightItems[name] ?? BarItem()
    mutate(&item)
    guard item != rightItems[name] else { return } // unchanged, so no redraw needed
    let t0 = DispatchTime.now().uptimeNanoseconds
    rightItems[name] = item
    repaint()
    // Refresh an open popup here too, or it can go on showing a stale value.
    if openPopup == name { refreshPopup() }
    tlog(String(format: "item %@ %.2f ms", name, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

func shell(_ launch: String, _ args: [String], env: [String: String]? = nil,
           timeout: TimeInterval? = nil) -> String {
    execute(launch, args, env: env, timeout: timeout).out
}

struct ShellResult {
    var out = ""
    var err = ""
    var status: Int32 = -1 // -1 means the command did not start
    var timedOut = false
}

// Kills the whole process tree after `timeout` seconds, not just the top
// pid: a child of sh -c can hold the pipe open on its own.
func execute(_ launch: String, _ args: [String], env: [String: String]? = nil,
             timeout: TimeInterval? = nil) -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args
    if let env { p.environment = env }
    let pipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = pipe
    p.standardError = errPipe
    let started = Date()
    guard (try? p.run()) != nil else { return ShellResult(err: "cannot start \(launch)") }
    // Read stderr at the same time, or a full stderr pipe blocks the command.
    var errData = Data()
    let errRead = DispatchGroup()
    errRead.enter()
    DispatchQueue.global().async {
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        errRead.leave()
    }
    let stop = DispatchWorkItem {
        guard p.isRunning else { return }
        tlog("shell timeout \(launch) \(args.prefix(2).joined(separator: " "))")
        var tree = [p.processIdentifier]
        var next = 0
        while next < tree.count {
            tree += shell("/usr/bin/pgrep", ["-P", String(tree[next])])
                .split(separator: "\n").compactMap { pid_t($0) }
            next += 1
        }
        for pid in tree { kill(pid, SIGTERM) }
    }
    if let timeout { DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop) }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    stop.cancel()
    p.waitUntilExit()
    errRead.wait()
    let stopped = p.terminationReason == .uncaughtSignal && Date().timeIntervalSince(started) >= (timeout ?? .infinity)
    return ShellResult(out: String(data: out, encoding: .utf8) ?? "",
                       err: String(data: errData, encoding: .utf8) ?? "",
                       status: p.terminationStatus, timedOut: stopped)
}

// Read palette only on the main thread. A theme switch can rewrite it there
// while a plugin's colour still resolves from the previous interval.
func pluginColor(_ name: String?) -> NSColor? {
    switch name {
    case "accent": return palette.accent
    case "label": return palette.label
    case "muted": return palette.muted
    case "red": return palette.red
    case "green": return palette.green
    case "yellow": return palette.yellow
    default:
        // #RRGGBB, for a brand colour no theme carries.
        guard let hex = name, hex.count == 7, hex.hasPrefix("#"),
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

func pluginPopupRows(_ raw: [[String: Any]], of plugin: BarPlugin) -> [PopupRow] {
    raw.map { spec in
        // JSON cannot carry a closure, so turn a row's "url", "terminal", or
        // "run" into the action a click performs.
        var action: (() -> Void)?
        // x-apple.systempreferences opens only a System Settings page.
        if let link = spec["url"] as? String, let url = URL(string: link),
           ["https", "x-apple.systempreferences"].contains(url.scheme) {
            action = { NSWorkspace.shared.open(url) }
        } else if let command = spec["run"] as? String, !command.isEmpty {
            // The command runs as argv to sh, never spliced into a shell string:
            // a stray quote fails the command instead of starting a second one.
            // Trusted the same as "terminal". The plugin runs again after, so
            // an open popup shows the change.
            action = {
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = shell("/bin/sh", ["-c", command], env: pluginEnv(plugin))
                    runPlugin(plugin)
                }
            }
        } else if let command = spec["terminal"] as? String, !command.isEmpty {
            // The plugin's own command already runs with the bar's grants, so a
            // row's command may too. Ghostty runs it as --command, as the
            // activity popup does for btop, since btop's -e would ask to confirm.
            action = {
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = shell("/usr/bin/open", ["-na", terminalApp, "--args",
                                                "--title=omacchiato-plugin", "--command=\(command)"])
                }
            }
        }
        return PopupRow(icon: spec["icon"] as? String ?? "",
                        text: spec["text"] as? String ?? "",
                        detail: spec["detail"] as? String ?? "",
                        subtitle: spec["subtitle"] as? String ?? "",
                        separator: spec["separator"] as? Bool ?? false,
                        hero: spec["hero"] as? Bool ?? false,
                        dim: spec["dim"] as? Bool ?? false,
                        slider: spec["slider"] as? Double,
                        marker: spec["marker"] as? Double,
                        inlineBar: spec["bar"] as? Double,
                        action: action,
                        tint: pluginColor(spec["color"] as? String),
                        barTint: pluginColor(spec["bar_color"] as? String),
                        iconTint: pluginColor(spec["icon_color"] as? String),
                        section: spec["section"] as? String)
    }
}

// Sections a click opened or closed, keyed by plugin, header text, and the
// count of earlier headers with that text. Lost on restart.
var sectionOpen: [String: Bool] = [:]

// A header row toggles the rows after it, up to the next header or "end" row.
// A separator right before the next header stays, so closed sections keep their rules.
func foldSections(_ name: String, _ rows: [PopupRow]) -> [PopupRow] {
    var out: [PopupRow] = []
    var hiding = false
    var seen: [String: Int] = [:]
    for (index, var row) in rows.enumerated() {
        switch row.section {
        case "open", "closed":
            // The detail changes as numbers change, so the key cannot use it.
            seen[row.text, default: 0] += 1
            let key = "\(name)\t\(row.text)\t\(seen[row.text]!)"
            let open = sectionOpen[key] ?? (row.section == "open")
            row.open = open
            row.action = { sectionOpen[key] = !open; refreshPopup() }
            hiding = !open
        case "end":
            hiding = false
        default:
            let next = index + 1 < rows.count ? rows[index + 1].section : nil
            if hiding && !(row.separator && next != nil) { continue }
        }
        out.append(row)
    }
    return out
}

func pluginEnv(_ plugin: BarPlugin) -> [String: String] {
    // launchd gives this process a bare PATH, so a plugin's own script or a
    // Homebrew binary would not be found. Add common install locations first.
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:"
        + (env["PATH"] ?? "/usr/bin:/bin")
    // Pass the configured icon so a command can reuse it instead of
    // hardcoding the glyph.
    env["OMACCHIATO_PILL_ICON"] = plugin.icon
    return env
}

// Runs one plugin command at a time. A hung command must not pile up copies,
// and an old answer must not overwrite a new one. Requests made during a run
// fold into one more run after it ends.
struct RunGate {
    var running: Set<String> = []
    var again: Set<String> = []

    mutating func start(_ name: String) -> Bool {
        if running.insert(name).inserted { return true }
        again.insert(name)
        return false
    }

    // True when a request came in during the run.
    mutating func finish(_ name: String) -> Bool {
        running.remove(name)
        return again.remove(name) != nil
    }
}
var pluginGate = RunGate() // main thread only

// A run failed if it timed out, or exited non-zero with no output.
// Returns the problem plus stderr's first line, for the popup.
func pluginProblem(_ result: ShellResult, limit: TimeInterval) -> (what: String, detail: String)? {
    let firstErr = result.err.split(separator: "\n").first.map { String($0.prefix(60)) } ?? ""
    if result.timedOut { return ("no answer in \(Int(limit)) s", firstErr) }
    guard result.status != 0, result.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return ("failed with exit \(result.status)", firstErr)
}

// Rows from the last run that worked, shown under an error.
var pluginGoodRows: [String: [PopupRow]] = [:]

// Keep the last label but dim it, and put the error at the top of the
// popup. A pill that hides when all is well shows a warning icon instead.
func showPluginProblem(_ plugin: BarPlugin, _ problem: (what: String, detail: String)) {
    tlog("plugin \(plugin.name): \(problem.what) \(problem.detail)")
    var rows = [PopupRow(icon: "\u{F071}", text: problem.what, tint: palette.red, iconTint: palette.red)]
    if !problem.detail.isEmpty { rows.append(PopupRow(text: problem.detail, dim: true)) }
    rows.append(PopupRow(text: "Run Again", dim: true, action: { runPlugin(plugin) }))
    let good = pluginGoodRows[plugin.name] ?? []
    pluginRows[plugin.name] = rows + (good.isEmpty ? [] : [PopupRow(separator: true)] + good)
    pluginPanels[plugin.name] = nil
    set(plugin.name) {
        if $0.icon.isEmpty && $0.label.isEmpty { $0.icon = "\u{F071}" }
        $0.iconColor = palette.muted
        $0.labelColor = palette.muted
    }
    if openPopup == plugin.name { refreshPopup() }
}

func runPlugin(_ plugin: BarPlugin) {
    guard Thread.isMainThread else { DispatchQueue.main.async { runPlugin(plugin) }; return }
    guard pluginIsActive(plugin), pluginGate.start(plugin.name) else { return }
    DispatchQueue.global(qos: .utility).async {
        let env = pluginEnv(plugin)
        let limit = max(plugin.interval, 30)
        let result = execute("/bin/sh", ["-c", plugin.command], env: env, timeout: limit)
        if let problem = pluginProblem(result, limit: limit) {
            DispatchQueue.main.async {
                if pluginGate.finish(plugin.name) { runPlugin(plugin) }
                guard pluginIsActive(plugin) else { return }
                showPluginProblem(plugin, problem)
            }
            return
        }
        let out = result.out
        // A command may reply with a JSON object to set a colour and popup
        // rows. Anything else is a plain label, the common case, and needs
        // no quoting.
        let obj = out.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        // The cluster lays out from the right edge inwards, so an unbounded
        // label would push every other pill off the left.
        let plain = out.split(separator: "\n").first.map(String.init) ?? ""
        let label = String((obj?["label"] as? String ?? plain)
            .trimmingCharacters(in: .whitespaces).prefix(32))
        let rawParts = obj?["parts"] as? [[String: Any]] ?? []
        DispatchQueue.main.async {
            if pluginGate.finish(plugin.name) { runPlugin(plugin) }
            // The config can change during a run. A run of a plugin that went
            // away, or changed, must not bring its old pill back.
            guard pluginIsActive(plugin) else { return }
            pluginGoodRows[plugin.name] = pluginPopupRows(obj?["rows"] as? [[String: Any]] ?? [], of: plugin)
            pluginRows[plugin.name] = pluginGoodRows[plugin.name]
            pluginPanels[plugin.name] = obj?["panel"] as? [String: Any]
            let color = pluginColor(obj?["color"] as? String)
            let icon = obj?["icon"] as? String ?? plugin.icon
            let parts = rawParts.map {
                BarPart(icon: $0["icon"] as? String ?? "",
                        iconColor: pluginColor($0["icon_color"] as? String) ?? color,
                        label: String(($0["label"] as? String ?? "").prefix(32)),
                        labelColor: pluginColor($0["label_color"] as? String),
                        under: $0["under"] as? Bool ?? false)
            }
            set(plugin.name) {
                $0.icon = icon
                $0.label = label
                $0.iconColor = pluginColor(plugin.iconColor) ?? color
                $0.labelColor = color
                $0.parts = parts
            }
            // set() refreshes an open popup only when the pill changed, but the rows can change alone.
            if openPopup == plugin.name { refreshPopup() }
        }
    }
}

// While the screen is locked, nobody reads the bar. The timed runs stop,
// so no plugin calls GitHub or tokscale, and one run on unlock catches up.
var screenLocked = false

var pluginTimers: [String: Timer] = [:]

func activePlugins() -> [BarPlugin] { barPlugins.filter { rightOrder.contains($0.name) } }

func pluginIsActive(_ plugin: BarPlugin) -> Bool { rightOrder.contains(plugin.name) && barPlugins.contains(plugin) }

func startPlugin(_ plugin: BarPlugin) {
    pluginTimers[plugin.name]?.invalidate()
    runPlugin(plugin)
    pluginTimers[plugin.name] = Timer.scheduledTimer(withTimeInterval: plugin.interval, repeats: true) { _ in
        if !screenLocked { runPlugin(plugin) }
    }
}

func stopPlugin(_ name: String) {
    pluginTimers.removeValue(forKey: name)?.invalidate()
    rightItems[name] = nil
    pluginRows[name] = nil
    pluginGoodRows[name] = nil
    pluginPanels[name] = nil
}

func startPlugins() {
    activePlugins().forEach(startPlugin)
    let center = DistributedNotificationCenter.default()
    center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
        screenLocked = true
    }
    center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
        screenLocked = false
        activePlugins().forEach(runPlugin)
        if rightOrder.contains("weather") { updateWeather() }
    }
}
