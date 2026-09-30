import Foundation
import SwiftUI
#if canImport(ThemePanel)
import ThemePanel
#endif

// What the settings window shows. The bar builds it from bar-pills.conf,
// its plugins and the table of known settings; the previews build it by
// hand.
public struct SettingsReport {
    // One value a setting can take. A nil value removes the key, which
    // gives the setting its default.
    public struct Choice: Hashable {
        public var value: String?
        public var title: String

        public init(_ value: String?, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    // One pill and everything about it, on one page.
    public struct Pill: Identifiable {
        // features: a plugin that is a feature of the Mac, not a pill to read, such as Keep Awake
        public enum Group: String { case bar = "Bar", plugins = "Plugins", features = "Features" }

        public var key: String
        public var title: String
        public var symbol: String
        public var tint: String          // a colour name: blue, green, orange, pink, purple, red, yellow, gray
        public var summary: String
        public var group: Group
        public var optIn: Bool           // shown only while its key is set, as wifi and battery are
        public var value: String?        // the raw value of the pill's key
        public var styles: [Choice]      // how it looks while shown; the first is the default
        public var panelDesigns: [Choice]
        public var panelValue: String?
        public var canHide: Bool         // false for a pill with no key to hide it, as Music
        public var numbers: [Number]
        public var switches: [Switch]
        public var aiUsage: AIUsageOptions?
        public var plugin: PluginFields?
        public var panelKind: String?    // which panel the designs belong to, for their previews

        public init(key: String, title: String, symbol: String, tint: String = "gray", summary: String = "",
                    group: Group = .bar, optIn: Bool = false, value: String? = nil, styles: [Choice] = [],
                    panelDesigns: [Choice] = [], panelValue: String? = nil,
                    canHide: Bool = true, numbers: [Number] = [], switches: [Switch] = [],
                    aiUsage: AIUsageOptions? = nil, plugin: PluginFields? = nil, panelKind: String? = nil) {
            self.key = key
            self.title = title
            self.symbol = symbol
            self.tint = tint
            self.summary = summary
            self.group = group
            self.optIn = optIn
            self.value = value
            self.styles = styles
            self.panelDesigns = panelDesigns
            self.panelValue = panelValue
            self.canHide = canHide
            self.numbers = numbers
            self.switches = switches
            self.aiUsage = aiUsage
            self.plugin = plugin
            self.panelKind = panelKind
        }

        public var id: String { key }

        public var shown: Bool { !canHide || (optIn ? value != nil : value != "hide") }

        // The value to write for the toggle. An opt-in pill needs a value to
        // show; any other pill shows with no key.
        public func value(shown: Bool) -> String? {
            optIn ? (shown ? styles.first?.value ?? "show" : nil) : (shown ? nil : "hide")
        }

        // The style picker's selection. A value that no style names still shows.
        public var style: String? { shown ? value : nil }

        public var shownStyles: [Choice] {
            styles.contains { $0.value == style } ? styles : styles + [Choice(style, style ?? "Default")]
        }

        // One control for show, hide and style: the styles, then Hidden.
        // An opt-in pill hides with no key; any other pill writes "hide".
        var hiddenValue: String? { optIn ? nil : "hide" }

        public var visibilityChoices: [Choice] {
            // a value that no style names still shows, as the current choice
            let listed = shown ? shownStyles : styles
            let shownOnes = listed.isEmpty ? [Choice(optIn ? "show" : nil, "Shown")] : listed
            return canHide ? shownOnes + [Choice(hiddenValue, "Hidden")] : shownOnes
        }

        public var visibility: String? { shown ? style : hiddenValue }

        public var shownPanelDesigns: [Choice] {
            panelDesigns.contains { $0.value == panelValue } || panelDesigns.isEmpty
                ? panelDesigns : panelDesigns + [Choice(panelValue, panelValue ?? "Default")]
        }
    }

    public struct Number: Identifiable {
        public var key: String
        public var title: String
        public var range: ClosedRange<Int>
        public var fallback: Int
        public var value: Int?
        public var unit: String              // "min", "%", "pt"; empty for a bare count
        public var zeroIsOff: Bool           // 0 turns the option off, so it reads as Off
        public var id: String { key }

        public init(key: String, title: String, range: ClosedRange<Int>, fallback: Int, value: Int?,
                    unit: String = "", zeroIsOff: Bool = false) {
            self.key = key
            self.title = title
            self.range = range
            self.fallback = fallback
            self.value = value
            self.unit = unit
            self.zeroIsOff = zeroIsOff
        }

        public func text(_ value: Int) -> String {
            if value == 0 && zeroIsOff { return "Off" }
            if unit.isEmpty { return "\(value)" }
            return unit == "%" ? "\(value)%" : "\(value) \(unit)"
        }
    }

    // The keys of a plugin's section in bar-plugins.conf, and what its command
    // takes. Keep in sync with parsePlugins in helper/bar/Plugins.swift.
    public struct PluginFields: Equatable {
        public enum Args: Equatable { case none, search, stats }

        public var command: String
        public var interval: Int         // seconds
        public var icon: String
        public var iconColor: String
        public var args: Args
        public var shownIcon: String     // the icon the pill draws now, which the plugin picks while icon is empty

        public init(command: String, interval: Int = 30, icon: String = "", iconColor: String = "", args: Args = .none,
                    shownIcon: String = "") {
            self.command = command
            self.interval = interval
            self.icon = icon
            self.iconColor = iconColor
            self.args = args
            self.shownIcon = shownIcon
        }

        // Nerd Font glyphs to pick from: the ones Omacchiato's scripts use, then common ones.
        public static let glyphs: [(String, String)] = [
            ("\u{ec82}", "Claude"), ("\u{ec81}", "OpenAI"), ("\u{ec1e}", "Copilot"), ("\u{f09b}", "GitHub"),
            ("\u{f407}", "Pull request"), ("\u{e725}", "Branch"), ("\u{F184F}", "Earbuds"), ("\u{F02CB}", "Headphones"),
            ("\u{F0EE0}", "CPU"), ("\u{F035B}", "Memory"), ("\u{F02CA}", "Disk"), ("\u{F0176}", "Coffee"),
            ("\u{F06B0}", "Update"), ("\u{f0e7}", "Bolt"), ("\u{f017}", "Clock"), ("\u{f073}", "Calendar"),
            ("\u{f0c2}", "Cloud"), ("\u{f001}", "Music"), ("\u{f120}", "Terminal"), ("\u{f121}", "Code"),
            ("\u{f0f3}", "Bell"), ("\u{f0e0}", "Mail"), ("\u{f005}", "Star"), ("\u{f004}", "Heart"),
            ("\u{f00c}", "Check"), ("\u{f071}", "Warning"), ("\u{f0ac}", "Globe"), ("\u{f013}", "Gear"),
        ]

        public static let intervals = [(10, "10 seconds"), (30, "30 seconds"), (60, "1 minute"), (300, "5 minutes"),
                                       (900, "15 minutes"), (3600, "1 hour")]
        public static let colors = [("", "Theme default"), ("accent", "Accent"), ("label", "Label"), ("muted", "Muted"),
                                    ("red", "Red"), ("green", "Green"), ("yellow", "Yellow")]

        public var program: String { command.split(separator: " ").first.map(String.init) ?? "" }
        // What follows the program: search qualifiers for github-prs, the metric for stats.
        public var argument: String {
            guard let space = command.firstIndex(of: " ") else { return "" }
            return command[command.index(after: space)...].trimmingCharacters(in: .whitespaces)
        }
        public func with(argument: String) -> String {
            argument.isEmpty ? program : program + " " + argument
        }
    }

    // A setting that is on or off. The default is on, with no key.
    public struct Switch: Identifiable {
        public var key: String
        public var title: String
        public var off: String           // the value that turns it off
        public var value: String?
        public var id: String { key }

        public init(key: String, title: String, off: String, value: String?) {
            self.key = key
            self.title = title
            self.off = off
            self.value = value
        }

        public var on: Bool { value != off }
    }

    public struct File: Identifiable {
        public var name: String          // bar-pills.conf
        public var url: URL
        public var text: String
        public var id: String { name }

        public init(name: String, url: URL, text: String) {
            self.name = name
            self.url = url
            self.text = text
        }
    }

    // Quit on close: the switch, the apps that stay open, and the running
    // apps that could join them.
    public struct QuitOnClose {
        public struct App: Identifiable {
            public var id: String            // the bundle ID
            public var name: String
            public var path: String?         // the app bundle, for its icon

            public init(id: String, name: String, path: String? = nil) {
                self.id = id
                self.name = name
                self.path = path
            }
        }

        public var on: Bool
        public var kept: [App]
        public var running: [App]

        public init(on: Bool, kept: [App], running: [App] = []) {
            self.on = on
            self.kept = kept
            self.running = running
        }
    }

    public var pills: [Pill]
    public var numbers: [Number]
    public var files: [File]
    public var theme: ThemeReport?
    public var quitOnClose: QuitOnClose?
    public var order: [String]           // the right-hand pills in bar order, hidden ones too
    public var orderSaved: Bool          // bar-pills.conf names an order, so Reset Order has work
    public var debug: Bool               // debug = on: the bar logs its memory each minute
    public var huds: [Switch]            // the HUD and click switches, on the HUDs & Sounds page

    public init(pills: [Pill], numbers: [Number] = [], files: [File] = [], theme: ThemeReport? = nil,
                quitOnClose: QuitOnClose? = nil, order: [String] = [], orderSaved: Bool = false, debug: Bool = false,
                huds: [Switch] = []) {
        self.order = order
        self.huds = huds
        self.debug = debug
        self.orderSaved = orderSaved
        self.pills = pills
        self.numbers = numbers
        self.files = files
        self.theme = theme
        self.quitOnClose = quitOnClose
    }
}

// The sidebar: Music on the left of the bar, the right-hand pills in bar
// order split into shown and hidden, and the features apart.
extension SettingsReport {
    public var sidebar: (left: [Pill], shown: [Pill], hidden: [Pill], features: [Pill]) {
        let features = pills.filter { $0.group == .features }
        let left = pills.filter { $0.key == "media" }
        let right = pills.filter { $0.group != .features && $0.key != "media" }
        let ordered = order.compactMap { key in right.first { $0.key == key } }
            + right.filter { !order.contains($0.key) }
        return (left, ordered.filter(\.shown), ordered.filter { !$0.shown }, features)
    }
}

// Keep in sync with the header that install.sh writes.
public let quitExceptionsHeader = "# Apps that stay open when their last window closes: one bundle ID a line."

public func quitExceptionsText(_ ids: [String]) -> String {
    var seen = Set<String>()
    return ([quitExceptionsHeader] + ids.filter { seen.insert($0).inserted }).joined(separator: "\n") + "\n"
}

public struct SettingsActions {
    public var set: (_ key: String, _ value: String?) -> Void = { _, _ in }
    public var save: (_ file: String, _ text: String) -> Void = { _, _ in }
    public var reveal: (URL) -> Void = { _ in }
    public var open: (URL) -> Void = { _ in }
    // A key of one plugin's section in bar-plugins.conf.
    public var setPlugin: (_ plugin: String, _ key: String, _ value: String) -> Void = { _, _, _ in }
    public var addPlugin: (_ name: String, _ command: String) -> Void = { _, _ in }
    public var removePlugin: (_ name: String) -> Void = { _ in }
    // Writes quit-on-close.conf with these bundle IDs.
    public var setQuitExceptions: ([String]) -> Void = { _ in }
    // Asks for an app with an open panel, and adds it to the apps that stay open.
    public var pickQuitException: () -> Void = {}
    // Saves the right-hand order; nil goes back to the default order.
    public var setOrder: ([String]?) -> Void = { _ in }
    public var theme = ThemeActions()
    // A design drawn with sample data, or nil for a panel with no preview.
    public var preview: (_ kind: String, _ design: String?) -> AnyView? = { _, _ in nil }

    public init() {}
}

// Sets one `key = value` line of a conf file and keeps the rest as it is:
// comments, blank lines, order and keys it does not know. The last line
// with the key is the one the bar reads, so that line changes, and the
// earlier ones go. A nil value removes the key. A new key goes at the end.
public func confSet(_ text: String, key: String, value: String?) -> String {
    var lines = text.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    func isKey(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return false }
        return t[..<eq].trimmingCharacters(in: .whitespaces) == key
    }
    let hits = lines.indices.filter { isKey(lines[$0]) }
    if let last = hits.last, let value {
        lines[last] = "\(key) = \(value)"
        for i in hits.dropLast().reversed() { lines.remove(at: i) }
    } else if let value {
        lines.append("\(key) = \(value)")
    } else {
        for i in hits.reversed() { lines.remove(at: i) }
    }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
}

// Sets one `key = value` line inside an INI section and keeps the rest.
// A new key goes after the section's last line. A missing section is added.
public func iniSet(_ text: String, section: String, key: String, value: String) -> String {
    var lines = text.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
    guard let start = trimmed.firstIndex(of: "[\(section)]") else {
        return (lines + (lines.isEmpty ? [] : [""]) + ["[\(section)]", "\(key) = \(value)"]).joined(separator: "\n") + "\n"
    }
    let end = trimmed[(start + 1)...].firstIndex { $0.hasPrefix("[") && $0.hasSuffix("]") } ?? lines.count
    if let hit = (start + 1..<end).last(where: { i in
        let t = trimmed[i]
        guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return false }
        return t[..<eq].trimmingCharacters(in: .whitespaces) == key
    }) {
        lines[hit] = "\(key) = \(value)"
    } else {
        let last = (start..<end).last { !trimmed[$0].isEmpty } ?? start
        lines.insert("\(key) = \(value)", at: last + 1)
    }
    return lines.joined(separator: "\n") + "\n"
}

// The flags of omacchiato-ai-usage, read from and written back to the
// plugin's command. Keep in sync with main() in bin/omacchiato-ai-usage.
public struct AIUsageOptions: Equatable {
    public struct Entry: Equatable {
        public var id: String
        public var window: String        // 5h, weekly or 30d

        public init(id: String, window: String = "5h") {
            self.id = id
            self.window = window
        }
    }

    public static let providers = [("claude", "Claude"), ("codex", "Codex"), ("copilot", "Copilot")]
    public static let windows = [("5h", "Session"), ("weekly", "Week"), ("30d", "30 days")]

    public var rest: [String]            // the program and any flag this does not know, in order
    public var pill: [Entry]
    public var panel: [String]?          // nil: the providers of the pill
    public var open: [String]?           // nil: the first provider of the popup
    public var inline: Bool

    // nil for a command with quotes, which a split on spaces would break.
    public init?(command: String) {
        guard !command.contains("\""), !command.contains("'") else { return nil }
        var rest: [String] = [], pill: [Entry] = [Entry(id: "claude")]
        var panel: [String]?, open: [String]?, inline = false
        func ids(_ s: String) -> [String] { s.split(separator: ",").map { String($0).lowercased() } }
        var tokens = command.split(separator: " ").map(String.init)[...]
        while let token = tokens.popFirst() {
            let (flag, attached) = token.hasPrefix("--") && token.contains("=")
                ? (String(token[..<token.firstIndex(of: "=")!]), String(token[token.index(after: token.firstIndex(of: "=")!)...]))
                : (token, nil)
            switch flag {
            case "--pill", "--panel", "--open":
                guard let value = attached ?? tokens.popFirst() else { continue }
                if flag == "--pill" {
                    pill = ids(value).map {
                        let parts = $0.split(separator: ":", maxSplits: 1).map(String.init)
                        return Entry(id: parts[0], window: parts.count > 1 ? parts[1] : "5h")
                    }
                } else if flag == "--panel" { panel = ids(value) } else { open = ids(value) }
            case "--inline": inline = true
            default: rest.append(token)
            }
        }
        self.rest = rest
        self.pill = pill
        self.panel = panel
        self.open = open
        self.inline = inline
    }

    public var panelIDs: [String] { panel ?? pill.map(\.id) }
    public var openIDs: [String] { open ?? Array(panelIDs.prefix(1)) }

    public var command: String {
        var parts = rest
        parts += ["--pill", pill.map { $0.window == "5h" ? $0.id : "\($0.id):\($0.window)" }.joined(separator: ",")]
        if let panel { parts += ["--panel", panel.joined(separator: ",")] }
        if let open { parts += ["--open", open.joined(separator: ",")] }
        if inline { parts.append("--inline") }
        return parts.joined(separator: " ")
    }

    // Turns a provider on or off in a list, and keeps the providers' order.
    public static func toggled(_ list: [String], _ id: String, _ on: Bool) -> [String] {
        let set = on ? Set(list).union([id]) : Set(list).subtracting([id])
        return providers.map(\.0).filter(set.contains) + list.filter { !providers.map(\.0).contains($0) && set.contains($0) }
    }
}

// Removes one INI section, with the blank lines before it.
public func iniRemove(_ text: String, section: String) -> String {
    var lines = text.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
    guard let start = trimmed.firstIndex(of: "[\(section)]") else { return text }
    let end = trimmed[(start + 1)...].firstIndex { $0.hasPrefix("[") && $0.hasSuffix("]") } ?? lines.count
    var from = start
    while from > 0, trimmed[from - 1].isEmpty { from -= 1 }
    lines.removeSubrange(from..<end)
    if let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
}
