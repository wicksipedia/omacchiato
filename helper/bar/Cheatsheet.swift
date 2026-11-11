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

// --- cheatsheet (Super+K) --------------------------------------------------
// Reads the live config — OmniWM's settings.toml and omacchiato's Karabiner
// rules — never a list kept here. A cheatsheet that can disagree with the
// keys is worse than none. The config's own section comments become the
// headings, so the grouping is the author's, not a second opinion.

struct CheatEntry {
    let group: String
    let key: String
    let action: String
}

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
    return entries
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
            let hasShift = mods.contains("shift")
            let key = keyCode == "return_or_enter" ? "Enter"
                : keyCode == "spacebar" ? "Space" : keyCode.uppercased()
            let chord = "Super+" + (hasShift ? "Shift+" : "") + key
            entries.append(CheatEntry(group: "Apps and system (Karabiner)",
                key: chord, action: String(desc.dropFirst("omacchiato-omniwm: ".count))))
        }
    }
    return entries
}

let cheatColumns = 3
let cheatRowH: CGFloat = 20
let cheatPad: CGFloat = 18

// The sheet takes key focus while open, like the overview, so it can be
// typed into. hideCheatsheet hands focus back to the app that had it, so
// search never costs the user their window.
final class CheatWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
}

final class CheatsheetView: NSView {
    var entries: [CheatEntry] = []
    var filter = ""
    private var keyFont: NSFont { nerdFont("Bold", 12) }
    private var actFont: NSFont { nerdFont("Regular", 12) }
    private var headFont: NSFont { nerdFont("Bold", 13) }

    private func visibleEntries() -> [CheatEntry] {
        guard !filter.isEmpty else { return entries }
        let f = filter.lowercased()
        return entries.filter {
            $0.key.lowercased().contains(f) || $0.action.lowercased().contains(f)
                || $0.group.lowercased().contains(f)
        }
    }

    // rows are (heading?, entry?) laid into balanced columns
    private func rows() -> [(String?, CheatEntry?)] {
        var out: [(String?, CheatEntry?)] = []
        var seen = ""
        for e in visibleEntries() {
            if e.group != seen {
                if !out.isEmpty { out.append((nil, nil)) } // breathing room
                out.append((e.group, nil))
                seen = e.group
            }
            out.append((nil, e))
        }
        return out
    }

    private func columns() -> [[(String?, CheatEntry?)]] {
        let all = rows()
        guard !all.isEmpty else { return [] }
        let per = Int((Double(all.count) / Double(cheatColumns)).rounded(.up))
        return stride(from: 0, to: all.count, by: per).map {
            Array(all[$0..<min($0 + per, all.count)])
        }
    }

    private func columnWidths() -> [(key: CGFloat, total: CGFloat)] {
        columns().map { col in
            var k: CGFloat = 0, a: CGFloat = 0
            for (head, e) in col {
                if let head { k = max(k, advance(head, headFont)) }
                if let e {
                    k = max(k, advance(e.key, keyFont))
                    a = max(a, advance(e.action, actFont))
                }
            }
            return (k, k + 14 + a)
        }
    }

    func measure() -> NSSize {
        let cols = columns()
        guard !cols.isEmpty else { return NSSize(width: 320, height: 80) }
        let widths = columnWidths()
        let w = widths.reduce(0) { $0 + $1.total } + CGFloat(cols.count - 1) * 28
        let tallest = cols.map(\.count).max() ?? 0
        return NSSize(width: w + cheatPad * 2,
                      height: CGFloat(tallest) * cheatRowH + cheatPad * 2 + 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 8, yRadius: 8)
        palette.barBG.setFill()
        body.fill()
        palette.accent.setStroke()
        body.lineWidth = 1
        body.stroke()

        let title = filter.isEmpty
            ? "keybindings — Super is Caps Lock · type to search · Super+K, Esc or click to close"
            : "search: \(filter)▏ — \(visibleEntries().count) match\(visibleEntries().count == 1 ? "" : "es") · Esc clears"
        drawText(title, nerdFont("Bold", 12), palette.accent.withAlphaComponent(0.8),
                 leftAt: cheatPad, midY: bounds.maxY - cheatPad - 6)

        var x = cheatPad
        for (i, col) in columns().enumerated() {
            let width = columnWidths()[i]
            var y = bounds.maxY - cheatPad - 30
            for (head, e) in col {
                if let head {
                    drawText(head, headFont, palette.accent, leftAt: x, midY: y - cheatRowH / 2)
                } else if let e {
                    drawText(e.key, keyFont, palette.label, leftAt: x, midY: y - cheatRowH / 2)
                    drawText(e.action, actFont, palette.muted,
                             leftAt: x + width.key + 14, midY: y - cheatRowH / 2)
                }
                y -= cheatRowH
            }
            x += width.total + 28
        }
    }

    override func mouseDown(with event: NSEvent) { hideCheatsheet() }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // esc — clear an active search first, close on the second
            if filter.isEmpty { hideCheatsheet() } else { filter = ""; refit() }
        case 51: // backspace
            if !filter.isEmpty { filter.removeLast(); refit() }
        case 40 where event.modifierFlags.contains([.command, .control, .option]):
            hideCheatsheet() // Super+K also closes the sheet, even though it holds key focus
        default:
            guard let chars = event.charactersIgnoringModifiers,
                !chars.isEmpty,
                !event.modifierFlags.contains(.command),
                chars.rangeOfCharacter(from: .alphanumerics.union(CharacterSet(charactersIn: "+- "))) != nil
            else { return }
            filter += chars
            refit()
        }
    }

    // the sheet shrinks to its matches — re-measure and keep the centre
    private func refit() {
        guard let window = window else { needsDisplay = true; return }
        let size = measure()
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        frame = NSRect(origin: .zero, size: size)
        window.setFrame(NSRect(x: c.x - size.width / 2, y: c.y - size.height / 2,
                               width: size.width, height: size.height), display: true)
        needsDisplay = true
    }
}

var cheatWindow: CheatWindow?
var cheatPrevApp: NSRunningApplication?

func hideCheatsheet() {
    cheatWindow?.orderOut(nil)
    cheatWindow = nil
    // hand focus back to whoever had it before the sheet took key
    cheatPrevApp?.activate()
    cheatPrevApp = nil
}

func toggleCheatsheet() {
    if cheatWindow != nil { hideCheatsheet(); return }
    let entries = omniwmCheatEntries()
    guard !entries.isEmpty else {
        tlog("cheatsheet: no bindings parsed from omniwm settings.toml")
        return
    }
    let view = CheatsheetView(frame: .zero)
    view.entries = entries
    let size = view.measure()
    view.frame = NSRect(origin: .zero, size: size)
    // centred on the display holding the cursor, like every other
    // full-surface thing here
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
    let window = CheatWindow(
        contentRect: NSRect(x: screen.frame.midX - size.width / 2,
                            y: screen.frame.midY - size.height / 2,
                            width: size.width, height: size.height),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.contentView = view
    // Take key focus so typing filters; hideCheatsheet gives it back to this app.
    cheatPrevApp = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    cheatWindow = window
    tlog("cheatsheet: \(entries.count) bindings")
}
