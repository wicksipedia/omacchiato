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
import CheatsheetPanel
#endif

// --- cheatsheet (Super+K) --------------------------------------------------
// Reads the live config — OmniWM's settings.toml and omacchiato's Karabiner
// rules — never a list kept here. A cheatsheet that can disagree with the
// keys is worse than none. The config's own section comments become the
// headings, so the grouping is the author's, not a second opinion.

// "Control+Option+Command+Shift+1" becomes "Super+Shift+1": Caps Lock sends
// Control+Option+Command, so collapse it back to Super, the one key the
// user presses. Key names arrive already capitalised. Dropping " Arrow"
// turns "Left Arrow" into "Left".
func prettyOmniKey(_ raw: String) -> String {
    var rest = raw
    var parts: [String] = []
    if rest.hasPrefix("Control+Option+Command+") {
        parts.append("Super")
        rest = String(rest.dropFirst("Control+Option+Command+".count))
    }
    for comp in rest.split(separator: "+") {
        var key = String(comp)
        if key.hasSuffix(" Arrow") { key = String(key.dropLast(" Arrow".count)) }
        parts.append(key)
    }
    return parts.joined(separator: "+")
}

// Turns "switchWorkspace.0" into "switch workspace 1". The raw catalog id
// keeps the config's exact wording, but printed verbatim it reads as a
// mess: 0-based suffixes beside 1-based keycaps, and camelCase words. This
// keeps the id's meaning but translates its casing and indexing to match
// the keycap next to it.
func humanizeOmniId(_ id: String) -> String {
    func words(_ s: String) -> String {
        var out = ""
        for ch in s { out.append(ch.isUppercase ? " " + String(ch).lowercased() : String(ch)) }
        return out.trimmingCharacters(in: .whitespaces)
    }
    let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
    // dwindle reality beats the catalog's niri-flavored names: moveColumn
    // is a tile swap there, the binding people reach for daily, and plain
    // move stacks into the neighbor as a group
    let renamed = ["moveColumn": "swap window", "move": "stack into"]
    let head = renamed[parts[0]] ?? words(parts[0])
    guard parts.count > 1 else { return head }
    if let n = Int(parts[1]) { return "\(head) \(n + 1)" }
    switch parts[1] {
    case "decrease10Percent": return "\(head) −10%"
    case "increase10Percent": return "\(head) +10%"
    default: return "\(head) \(words(parts[1]))"
    }
}

// A strict-decoder rewrite can strip the comment headings. When that
// happens, the sheet groups by id family instead.
func omniGroup(_ id: String) -> String {
    let h = String(id.split(separator: ".").first ?? "")
    if h.lowercased().contains("workspace") { return "Workspaces" }
    if h.hasPrefix("focus") { return "Focus" }
    if h.hasPrefix("move") || h.hasPrefix("summon") { return "Move" }
    if h.contains("Span") || h.hasPrefix("resize") || h.hasPrefix("balance")
        || h.hasPrefix("cycleSize") || h.hasPrefix("set") { return "Size" }
    if h.hasPrefix("toggle") || h.contains("Layout") || h.contains("Column")
        || h.hasPrefix("preselect") || h.contains("olumn") { return "Layout & columns" }
    return "System"
}

// [[hotkeys]] tables out of OmniWM's settings.toml: a binding string and
// an action id per table, in either order.
func omniwmCheatEntries() -> [CheatEntry] {
    let path = "\(NSHomeDirectory())/.config/omniwm/settings.toml"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    var entries: [CheatEntry] = []
    var group = ""
    var lastWasComment = false
    var inHotkey = false
    var binding = ""
    var id = ""
    func flush() {
        // The settings file lists every catalog id, and most are Unassigned.
        // A cheatsheet should show only what you can press. About 90
        // unassigned rows are left out — they made the sheet an unreadable
        // wall.
        if inHotkey, !binding.isEmpty, binding != "Unassigned", !id.isEmpty {
            entries.append(CheatEntry(
                group: group.isEmpty ? omniGroup(id) : group,
                key: prettyOmniKey(binding), action: humanizeOmniId(id)))
        }
        binding = ""
        id = ""
    }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            // A comment between tables starts the next group. A finished
            // pending entry belongs to the heading it was written under,
            // not the one about to start. TOML allows comments between a
            // table's own keys, so a half-read table still keeps them.
            if !binding.isEmpty, !id.isEmpty { flush() }
            // The first line of a comment block is the heading; later
            // lines are prose. Strip any "---" ruler decoration from it.
            if !lastWasComment {
                var title = String(line.dropFirst())
                    .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                if let c = title.firstIndex(where: { $0 == ":" || $0 == "." }) {
                    title = String(title[..<c])
                }
                title = title.trimmingCharacters(in: .whitespaces)
                if title.count > 34 { title = String(title.prefix(33)) + "…" }
                group = title
            }
            lastWasComment = true
            continue
        }
        lastWasComment = false
        if line.hasPrefix("[") {
            flush()
            inHotkey = line == "[[hotkeys]]"
            continue
        }
        guard inHotkey, let eq = line.firstIndex(of: "=") else { continue }
        let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard let q = value.first, q == "'" || q == "\"",
            let close = value.dropFirst().firstIndex(of: q)
        else { continue }
        let v = String(value[value.index(after: value.startIndex)..<close])
        if key == "binding" { binding = v } else if key == "id" { id = v }
    }
    flush()
    // Derived groups arrive interleaved: switch and move alternate per
    // workspace. This sorts by section while keeping each section's
    // original order, using an explicit index tiebreak instead of relying
    // on sort's stability.
    let sectionOrder = ["Workspaces", "Focus", "Move", "Layout & columns", "Size", "System"]
    let indexed = entries.enumerated().map { ($0.offset, $0.element) }
    entries = indexed.sorted { a, b in
        let ga = sectionOrder.firstIndex(of: a.1.group) ?? 99
        let gb = sectionOrder.firstIndex(of: b.1.group) ?? 99
        return ga != gb ? ga < gb : a.0 < b.0
    }.map { $0.1 }
    // Exec chords live in Karabiner because OmniWM's hotkeys cannot run a
    // command. The sheet must show them, or half the shortcut map is
    // invisible. Read back the rules omacchiato injected, by their
    // description prefix.
    entries.append(contentsOf: karabinerExecCheatEntries())
    return collapseCheatEntries(entries)
}

// Reads "omacchiato-omniwm: terminal" rules from karabiner.json. The
// description holds the action name; from.key_code and its modifiers hold
// the chord.
func karabinerExecCheatEntries() -> [CheatEntry] {
    let path = "\(NSHomeDirectory())/.config/karabiner/karabiner.json"
    guard let data = FileManager.default.contents(atPath: path),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let profiles = root["profiles"] as? [[String: Any]] else { return [] }
    var entries: [CheatEntry] = []
    for profile in profiles {
        guard (profile["selected"] as? Bool) ?? (profiles.count == 1),
            let cm = profile["complex_modifications"] as? [String: Any],
            let rules = cm["rules"] as? [[String: Any]] else { continue }
        for rule in rules {
            guard let desc = rule["description"] as? String,
                desc.hasPrefix("omacchiato-omniwm: "),
                let manips = rule["manipulators"] as? [[String: Any]],
                let from = manips.first?["from"] as? [String: Any],
                let keyCode = from["key_code"] as? String else { continue }
            let mods = ((from["modifiers"] as? [String: Any])?["mandatory"] as? [String]) ?? []
            entries.append(CheatEntry(group: "Apps and system (Karabiner)",
                key: karabinerChord(keyCode, mods: mods),
                action: String(desc.dropFirst("omacchiato-omniwm: ".count))))
        }
    }
    return entries
}

// Writes a Karabiner key_code and its mandatory modifiers as the sheet's
// chord text. Command, Control and Option together are Super.
func karabinerChord(_ keyCode: String, mods: [String]) -> String {
    let names = ["return_or_enter": "Enter", "spacebar": "Space", "tab": "Tab", "escape": "Esc",
                 "equal_sign": "=", "hyphen": "-", "grave_accent_and_tilde": "Grave"]
    let key = names[keyCode] ?? keyCode.uppercased()
    var parts: [String] = []
    let isSuper = ["command", "control", "option"].allSatisfy(mods.contains)
    if isSuper { parts.append("Super") }
    for (mod, name) in [("control", "Control"), ("option", "Option"), ("command", "Command")]
    where !isSuper && mods.contains(mod) { parts.append(name) }
    if mods.contains("shift") { parts.append("Shift") }
    return (parts + [key]).joined(separator: "+")
}

// Folds a numbered run into one row: "Super+1 … Super+9 / workspace slot N"
// becomes "Super+[1-9] / workspace slot". Each key and action must hold the
// same number, and the numbers must run without a gap. The row takes the
// place of the first entry of its run.
func collapseCheatEntries(_ entries: [CheatEntry]) -> [CheatEntry] {
    func split(_ e: CheatEntry) -> (template: String, number: Int)? {
        guard let last = e.key.last, let n = last.wholeNumberValue,
            e.action.hasSuffix(" \(n)") else { return nil }
        let action = String(e.action.dropLast(" \(n)".count))
        return ("\(e.group)\u{1}\(e.key.dropLast())\u{1}\(action)", n)
    }
    var runs: [String: [Int]] = [:]
    for e in entries { if let s = split(e) { runs[s.template, default: []].append(s.number) } }
    var out: [CheatEntry] = []
    var emitted: Set<String> = []
    for e in entries {
        guard let s = split(e), let ns = runs[s.template], ns.count >= 3,
            ns.sorted() == Array(ns.min()!...ns.max()!) else { out.append(e); continue }
        guard emitted.insert(s.template).inserted else { continue }
        out.append(CheatEntry(group: e.group, key: "\(e.key.dropLast())[\(ns.min()!)-\(ns.max()!)]",
                              action: String(e.action.dropLast(" \(s.number)".count))))
    }
    return out
}

// The window covers the screen, so a search that shrinks the sheet never
// resizes it.
final class CheatWindow: NSWindow {
    var model: CheatsheetModel?

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown: hideCheatsheet()
        case .keyDown: cheatKey(event)
        default: super.sendEvent(event)
        }
    }

    private func cheatKey(_ event: NSEvent) {
        guard let model else { return }
        switch event.keyCode {
        case 53: // Esc clears a search first, and closes on the second press
            if model.filter.isEmpty { hideCheatsheet() } else { model.filter = "" }
        case 51:
            if !model.filter.isEmpty { model.filter.removeLast() }
        case 40 where event.modifierFlags.contains([.command, .control, .option]):
            hideCheatsheet() // Super+K closes the sheet, which holds key focus
        default:
            guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
                !event.modifierFlags.contains(.command),
                chars.rangeOfCharacter(from: .alphanumerics.union(CharacterSet(charactersIn: "+- "))) != nil
            else { return }
            model.filter += chars
        }
    }
}

var cheatWindow: CheatWindow?
var cheatPrevApp: NSRunningApplication?
var cheatClickMonitor: Any?
var cheatResignObserver: NSObjectProtocol?

func hideCheatsheet(restoreFocus: Bool = true) {
    guard let window = cheatWindow else { return }
    cheatWindow = nil
    if let m = cheatClickMonitor { NSEvent.removeMonitor(m) }
    if let o = cheatResignObserver { NotificationCenter.default.removeObserver(o) }
    cheatClickMonitor = nil
    cheatResignObserver = nil
    window.orderOut(nil)
    // after a click on another app, that app keeps the focus it just took
    if restoreFocus { cheatPrevApp?.activate() }
    cheatPrevApp = nil
}

func toggleCheatsheet() {
    if cheatWindow != nil { hideCheatsheet(); return }
    let entries = omniwmCheatEntries()
    guard !entries.isEmpty else {
        tlog("cheatsheet: no bindings parsed from omniwm settings.toml")
        return
    }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
    let model = CheatsheetModel(entries: entries)
    let view = CheatsheetView(model: model)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    let window = CheatWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.model = model
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.contentView = NSHostingView(rootView: view)
    cheatPrevApp = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    cheatWindow = window
    // A clear window passes clicks to the app behind it, so watch other apps.
    cheatClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
        hideCheatsheet(restoreFocus: false)
    }
    cheatResignObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in hideCheatsheet(restoreFocus: false) }
    tlog("cheatsheet: \(entries.count) bindings")
}
