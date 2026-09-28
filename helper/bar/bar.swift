// omacchiato-bar: the status bar, its popups and its OSDs, in one process.
// It keeps the window model in memory and updates it from SkyLight and
// OmniWM events, so a workspace switch needs no subprocess call. The
// right-cluster pills read IOPS, CoreAudio, DisplayServices,
// SCDynamicStore and IOBluetooth directly instead of shelling out.
// Timings land in /tmp/omacchiato-bar.log as `switch <ws> <ms>`.
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

// DisplayServices is private. Control Center uses the same calls, and so
// does helper/main.swift, for `omacchiato-helper brightness`.
@_silgen_name("DisplayServicesGetBrightness")
func DSGetBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func DSSetBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32

// Brightness has a publisher. The callback's later arguments are untyped
// and unused; the ABI needs their arity, not their content.
typealias DSBrightnessProc = @convention(c) (UnsafeRawPointer?, CGDirectDisplayID, UnsafeRawPointer?, UnsafeRawPointer?) -> Void
@_silgen_name("DisplayServicesRegisterForBrightnessChangeNotifications")
func DSRegisterBrightnessNotifications(_ display: CGDirectDisplayID, _ context: UnsafeMutableRawPointer?, _ callback: DSBrightnessProc) -> Int32

@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func BTGetPower() -> Int32

// --- SkyLight window events -----------------------------------------------

typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32
@_silgen_name("SLSRequestNotificationsForWindows")
func SLSRequestNotificationsForWindows(_ cid: Int32, _ windows: UnsafePointer<UInt32>, _ count: Int32) -> CGError
@_silgen_name("SLSRegisterNotifyProc")
func SLSRegisterNotifyProc(_ proc: NotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError
@_silgen_name("SLSGetEventPort")
func SLSGetEventPort(_ cid: Int32, _ port: UnsafeMutablePointer<mach_port_t>) -> CGError
@_silgen_name("SLEventCreateNextEvent")
func SLEventCreateNextEvent(_ cid: Int32) -> Unmanaged<CGEvent>?

let EVENT_WINDOW_MOVE: UInt32 = 806
let EVENT_WINDOW_RESIZE: UInt32 = 807
// Sending a window to another workspace orders it out; it does not move
// it. A workspace switch fires 806/808/815. A window changing workspace
// fires only 808 and 815. Watch both 808 and 815: the pairing is
// observed, not documented.
let EVENT_WINDOW_ORDER: UInt32 = 808
let EVENT_WINDOW_VISIBILITY: UInt32 = 815
let EVENT_WINDOW_CREATE: UInt32 = 1325
let EVENT_WINDOW_DESTROY: UInt32 = 1326

// --- plumbing -------------------------------------------------------------

// OmniWM can start or quit while this runs, so check per use, never
// cache. The running-app lookup is in-process and cheap enough to be the
// whole check.
let omniwmBundleID = "com.barut.OmniWM"

// Match by prefix. The dev build, com.barut.OmniWM.dev, uses the same socket.
func isOmniWM(_ bundleID: String?) -> Bool {
    bundleID?.hasPrefix(omniwmBundleID) == true
}

func omniwmActive() -> Bool {
    NSWorkspace.shared.runningApplications.contains { isOmniWM($0.bundleIdentifier) }
}

// the wrapper finds omniwmctl in the Homebrew link, the release app or a dev build
let omniwmctlBin = NSHomeDirectory() + "/.local/bin/omacchiato-omniwmctl"

@discardableResult
func omniwmctl(_ args: [String]) -> String { shell(omniwmctlBin, args, timeout: omniTimeout) }

// Some callers run on the main thread, so a hung OmniWM must not hang the bar.
let omniTimeout: TimeInterval = 2

// One query, unwrapped to its payload. The CLI prints the whole
// IPCResponse envelope; the payload sits two levels down, at
// result.payload (see OmniWM docs/IPC-CLI.md, Response Format).
func omniQuery(_ name: String, _ args: [String] = []) -> [String: Any]? {
    // Fast path: omacchiato-omni keeps a persistent socket and starts in
    // about 3 ms; omniwmctl needs about 10 ms. It speaks
    // `query <name> [fields-csv]` and prints the same envelope. A flag
    // like --focused stays on omniwmctl.
    let omni = "\(NSHomeDirectory())/.local/bin/omacchiato-omni"
    var out = ""
    if FileManager.default.isExecutableFile(atPath: omni),
       args.isEmpty || (args.count == 2 && args[0] == "--fields") {
        out = shell(omni, args.isEmpty ? ["query", name] : ["query", name, args[1]], timeout: omniTimeout)
    }
    if out.isEmpty {
        out = omniwmctl(["query", name] + args + ["--format", "json"])
    }
    guard let data = out.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (root["ok"] as? Bool) == true,
          let result = root["result"] as? [String: Any]
    else { return nil }
    return result["payload"] as? [String: Any]
}

// Click to jump. OmniWM's focus-name call resolves a raw workspace ID
// across all monitors, which matches a chip on either display.
func focusWorkspace(_ ws: String) {
    omniwmctl(["workspace", "focus-name", ws])
}

// A click on one card of a chip's hand focuses that app's window.
func focusApp(_ app: String, on ws: String) {
    let wins = omniQuery("windows", ["--fields", "id,workspace,app"])?["windows"] as? [[String: Any]] ?? []
    // ponytail: the first window of the app wins; a hand shows each app once
    guard let id = wins.first(where: {
        ($0["workspace"] as? [String: Any])?["rawName"] as? String == ws
            && ($0["app"] as? [String: Any])?["name"] as? String == app
    })?["id"] as? String else { return focusWorkspace(ws) }
    omniwmctl(["window", "navigate", id])
}

// The card under x in a chip whose hand holds `count` cards, left to right.
func handIndex(at x: CGFloat, in slot: NSRect, count: Int) -> Int {
    let n = min(count, 3)
    return min(n - 1, max(0, Int((x - slot.minX) / slot.width * CGFloat(n))))
}

let logURL = URL(fileURLWithPath: "/tmp/omacchiato-bar.log")
func tlog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: logURL)
    }
}

struct BundleIdentifier {
    let rawValue: String

    init?(_ rawValue: String) {
        let segments = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments.allSatisfy({ segment in
                  guard let first = segment.unicodeScalars.first,
                        BundleIdentifier.isAlphanumeric(first) else { return false }
                  return segment.unicodeScalars.allSatisfy(BundleIdentifier.isAlphanumericOrHyphen)
              })
        else { return nil }
        self.rawValue = rawValue
    }

    private static func isAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }

    private static func isAlphanumericOrHyphen(_ scalar: UnicodeScalar) -> Bool {
        isAlphanumeric(scalar) || scalar.value == 45
    }
}

enum WorkspaceIcon {
    case glyph(String)
    case image(NSImage)
    case unavailable
}

enum WorkspaceIconDeclaration {
    case glyph(String)
    case bundle(BundleIdentifier)
}

struct WorkspaceIconConfig {
    let values: [String: WorkspaceIcon]

    func icon(for workspace: String) -> WorkspaceIcon? {
        if let icon = values[workspace] { return icon }
        guard workspace.count > 1,
              workspace.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let last = workspace.unicodeScalars.last,
              (49...57).contains(last.value)
        else { return nil }
        return values[String(Character(last))]
    }
}

func loadWorkspaceIconConfig() -> WorkspaceIconConfig {
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omacchiato/workspace-icons.conf")
    guard FileManager.default.fileExists(atPath: file.path) else {
        return WorkspaceIconConfig(values: [:])
    }
    guard let text = try? String(contentsOf: file, encoding: .utf8) else {
        tlog("workspace-icons: could not read \(file.path)")
        return WorkspaceIconConfig(values: [:])
    }

    var declarations: [String: WorkspaceIconDeclaration] = [:]
    for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let lineNumber = offset + 1
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        guard let separator = line.firstIndex(of: "=") else {
            tlog("workspace-icons: malformed line \(lineNumber)")
            continue
        }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else {
            tlog("workspace-icons: malformed line \(lineNumber)")
            continue
        }

        let declaration: WorkspaceIconDeclaration?
        if let bundle = BundleIdentifier(value) {
            declaration = .bundle(bundle)
        } else if value.unicodeScalars.count == 1 {
            declaration = .glyph(value)
        } else {
            declaration = nil
        }
        guard let declaration else {
            tlog("workspace-icons: malformed line \(lineNumber)")
            continue
        }
        if declarations[key] != nil {
            tlog("workspace-icons: duplicate \(key) on line \(lineNumber), last valid value wins")
        }
        declarations[key] = declaration
    }

    var values: [String: WorkspaceIcon] = [:]
    for (key, declaration) in declarations {
        switch declaration {
        case .glyph(let glyph):
            values[key] = .glyph(glyph)
        case .bundle(let identifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier.rawValue) else {
                tlog("workspace-icons: \(key) could not resolve \(identifier.rawValue)")
                values[key] = .unavailable
                continue
            }
            values[key] = .image(NSWorkspace.shared.icon(forFile: url.path))
        }
    }
    return WorkspaceIconConfig(values: values)
}

let workspaceIconConfig = loadWorkspaceIconConfig()

// --- theme ------------------------------------------------------------
// Reads the omarchy theme file (still named sketchybar.sh) once at
// startup, and keeps the values as colours.

struct Palette {
    var itemBG = NSColor.black   // the pills on the bar
    var rowBG = NSColor.black    // a filled row or track inside a popup
    var accent = NSColor.systemBlue
    var label = NSColor.white
    var muted = NSColor.gray
    var barBG = NSColor.black
    var red = NSColor.systemRed
    var green = NSColor.systemGreen
    var yellow = NSColor.systemYellow
}

extension NSColor {
    // The bar window is not opaque, so the window server hit-tests it by
    // alpha. A pill at alpha 0 draws fine but takes no clicks except on
    // glyph strokes.
    var clickable: NSColor {
        alphaComponent > 0 ? self : withAlphaComponent(0.01)
    }
}

func color(fromARGB v: UInt64) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: CGFloat((v >> 24) & 0xff) / 255)
}

func loadPalette(_ file: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/omarchy/current/theme/sketchybar.sh")) -> Palette {
    var p = Palette()
    var sawRowBG = false
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return p }
    for line in text.split(separator: "\n") {
        let parts = line.replacingOccurrences(of: "export ", with: "").split(separator: "=")
        guard parts.count == 2, parts[1].hasPrefix("0x"),
              let v = UInt64(parts[1].dropFirst(2), radix: 16) else { continue }
        switch parts[0] {
        case "ITEM_BG": p.itemBG = color(fromARGB: v).clickable
        case "ROW_BG": p.rowBG = color(fromARGB: v); sawRowBG = true
        case "ACCENT": p.accent = color(fromARGB: v)
        case "LABEL_COLOR": p.label = color(fromARGB: v)
        case "MUTED": p.muted = color(fromARGB: v)
        case "BAR_BG_SOLID": p.barBG = color(fromARGB: v)
        case "RED": p.red = color(fromARGB: v)
        case "GREEN": p.green = color(fromARGB: v)
        case "YELLOW": p.yellow = color(fromARGB: v)
        default: break
        }
    }
    // A theme file with no ROW_BG key is old; it used ITEM_BG for both
    // pills and popup fills.
    if !sawRowBG { p.rowBG = p.itemBG }
    return p
}

// Ask for the font family by name and check the match. A missing family
// logs a fallback once, at startup, instead of failing silently.
func nerdFont(_ face: String, _ size: CGFloat) -> NSFont {
    let desc = NSFontDescriptor(fontAttributes: [
        .family: "JetBrainsMono Nerd Font",
        .face: face,
    ])
    if let f = NSFont(descriptor: desc, size: size), f.familyName == "JetBrainsMono Nerd Font" {
        return f
    }
    tlog("font: JetBrainsMono Nerd Font \(face) unavailable — using system mono")
    return .monospacedSystemFont(ofSize: size, weight: face == "Bold" ? .bold : .semibold)
}

// The menu bar face for pill text. A plugin label can hold a Nerd Font
// glyph, so the Nerd Font follows in the cascade list. Digits are fixed
// width, so a percent or a clock does not shift pills beside it.
func menuBarFont(_ weight: NSFont.Weight, _ size: CGFloat = 13) -> NSFont {
    let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    let nerd = NSFontDescriptor(fontAttributes: [.family: "JetBrainsMono Nerd Font"])
    return NSFont(descriptor: base.fontDescriptor.addingAttributes([.cascadeList: [nerd]]), size: size) ?? base
}

// --- model ----------------------------------------------------------------

// Shared state across every display: the focused workspace, the front
// app, and which workspaces hold what. Anything that differs per screen,
// such as the workspace set or the notch, belongs to the surface.
final class Model {
    var focused = ""
    var wsApps: [String: [String]] = [:] // up to three app names per workspace, leftmost window first
    var focusedApp = "" // may be on any display
    var occupied: Set<String> = []
    var frontApp = ""
    var media = Media()
}

struct Media: Equatable {
    var running = false
    var playing = false
    var title = ""
}

let model = Model()
var palette = loadPalette()

// The slow path: who lives where. Three CLI calls, run only when a window
// is created or destroyed, never on a workspace switch.
//
// This runs off the main queue and applies its result on it. Measured
// fact: running the CLI calls inline on main blocked rendering for 7.6 s
// during one contended rebuild, and every switch queued behind it.
struct Snapshot {
    var perMonitor: [String: (workspaces: [String], visible: String)] = [:]
    var wsApps: [String: [String]] = [:]
    var focusedApp = ""
    var occupied: Set<String> = []
    var focused = ""
}

let rebuildQueue = DispatchQueue(label: "com.omacchiato.bar.rebuild")
// Music can hang an Apple Event for 120 s. Keep that off the workspace queue.
let mediaQueue = DispatchQueue(label: "com.omacchiato.bar.media")

// with no window manager the snapshot is empty, and the bar draws no chips
func fetchSnapshot() -> Snapshot {
    omniwmActive() ? omniwmSnapshot() : Snapshot()
}

// omniwmctl answers two queries: workspaces, with each one's display, and
// windows, with the app names the icon chips need. This slow path also
// carries focus; the workspace-bar stream below covers the fast path.
func omniwmSnapshot() -> Snapshot {
    var s = Snapshot()
    var sets: [String: [String]] = [:]
    var visible: [String: String] = [:]
    if let list = omniQuery("workspaces",
                            ["--fields", "raw-name,display"])?["workspaces"]
        as? [[String: Any]] {
        for w in list {
            guard let name = w["rawName"] as? String,
                  let monitor = (w["display"] as? [String: Any])?["id"] as? String else { continue }
            sets[monitor, default: []].append(name)
        }
    }
    // Visible and focused come from the displays query. The workspaces
    // query's isVisible/isFocused go dark on empty workspaces, so a
    // focused empty workspace 8 or 9 never lit its pill. omacchiato-ws
    // hit the same trap.
    if let displays = omniQuery("displays", [])?["displays"] as? [[String: Any]] {
        for d in displays {
            guard let id = d["id"] as? String,
                  let active = (d["activeWorkspace"] as? [String: Any])?["rawName"] as? String
            else { continue }
            visible[id] = active
            if (d["isCurrent"] as? Bool) == true { s.focused = active }
        }
    }
    for id in surfaces.map({ $0.monitorID }) {
        s.perMonitor[id] = (sets[id] ?? [], visible[id] ?? "")
    }

    var placed: [String: [(x: Double, y: Double, app: String)]] = [:]
    if let list = omniQuery("windows", ["--fields", "workspace,app,mode,frame,is-focused"])?["windows"]
        as? [[String: Any]] {
        for w in list {
            guard let ws = (w["workspace"] as? [String: Any])?["rawName"] as? String,
                  let app = (w["app"] as? [String: Any])?["name"] as? String else { continue }
            guard (w["mode"] as? String) != "floating" else { continue }
            s.occupied.insert(ws)
            if (w["isFocused"] as? Bool) == true { s.focusedApp = app }
            let frame = w["frame"] as? [String: Any]
            placed[ws, default: []].append((frame?["x"] as? Double ?? .infinity,
                                           frame?["y"] as? Double ?? .infinity, app))
        }
    }
    for (ws, wins) in placed {
        s.wsApps[ws] = handOf(layoutOrder(wins))
    }
    return s
}

// Leftmost window first, matching the workspace-bar stream's layout order
// for a niri workspace. OmniWM stacks a hidden workspace's windows on one
// frame, so a position tie falls back to query order, which is the
// layout order. Sorting by app name instead flipped the icons.
func layoutOrder(_ wins: [(x: Double, y: Double, app: String)]) -> [String] {
    wins.enumerated()
        .sorted { ($0.element.x, $0.element.y, $0.offset) < ($1.element.x, $1.element.y, $1.offset) }
        .map(\.element.app)
}

// Reports whether anything changed. A workspace switch also triggers
// window moves, but those snapshots come back identical, so the repaint
// and log line run only when something did change.
@discardableResult
func apply(_ s: Snapshot) -> Bool {
    var changed = false
    for surface in surfaces {
        guard let part = s.perMonitor[surface.monitorID] else { continue }
        if !part.workspaces.isEmpty, surface.workspaces != part.workspaces {
            surface.workspaces = part.workspaces
            surface.mine = Set(part.workspaces)
            changed = true
        }
        if !part.visible.isEmpty, surface.visible != part.visible {
            surface.visible = part.visible
            changed = true
        }
    }
    if model.occupied != s.occupied { model.occupied = s.occupied; changed = true }
    if model.wsApps != s.wsApps { model.wsApps = s.wsApps; changed = true }
    if model.focusedApp != s.focusedApp { model.focusedApp = s.focusedApp; changed = true }
    if !s.focused.isEmpty, model.focused != s.focused { model.focused = s.focused; changed = true }
    return changed
}

// --- media (Apple Music announces itself; the title needs no subprocess) --
// Apple Music posts a notification on every change, and its payload
// carries Name, Artist and Player State. The only subprocess left is a
// click command, where 20 ms is not noticeable.

let musicBundleID = "com.apple.Music"
// Apple Music posts its playback notification under the old iTunes name.
let musicNotification = "com.apple.iTunes.playerInfo"

func musicRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).isEmpty
}

func updateMedia(from info: [AnyHashable: Any]? = nil) {
    var next = Media()
    next.running = musicRunning()
    if next.running {
        if let info {
            next.playing = (info["Player State"] as? String) == "Playing"
            let name = info["Name"] as? String ?? ""
            let artist = info["Artist"] as? String ?? ""
            next.title = artist.isEmpty ? name : "\(artist) — \(name)"
        } else {
            next.title = model.media.title
            next.playing = model.media.playing
        }
    }
    guard next != model.media else { return }
    let t0 = DispatchTime.now().uptimeNanoseconds
    model.media = next
    fetchMediaArt()
    repaint()
    tlog(String(format: "media %@ %@ %.2f ms", next.playing ? "play" : "pause", next.title,
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

// "playpause", "next track" or "previous track". The Music notification repaints the pill.
func musicCommand(_ verb: String) {
    guard musicRunning() else { return }
    mediaQueue.async {
        _ = shell("/usr/bin/osascript", ["-e", "tell application \"Music\" to \(verb)"], timeout: 5)
    }
}

// startup only: the notification fires on change, so the current track
// has to be asked for once
func primeMedia() {
    guard musicRunning() else { return }
    mediaQueue.async {
        let script = """
        tell application "Music" to if it is running then \
        return (player state as text) & "|" & artist of current track & "|" & name of current track
        """
        let out = shell("/usr/bin/osascript", ["-e", script], timeout: 5)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = out.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return }
        DispatchQueue.main.async {
            model.media = Media(running: true, playing: parts[0] == "playing",
                                title: parts[1].isEmpty ? parts[2] : "\(parts[1]) — \(parts[2])")
            fetchMediaArt()
            repaint()
        }
    }
}

// The track's artwork, fetched once per track and shrunk to the pill's
// size, so a redraw never scales the 800 px original.
var mediaArt: NSImage?
var mediaArtTitle = ""
// Computed, not stored. Globals in this file initialise top to bottom,
// and pillHeight is declared later, so a stored value would read zero.
var mediaArtSide: CGFloat { MediaPill.artSide(pillHeight: pillHeight) }

func fetchMediaArt() {
    let title = model.media.title
    guard title != mediaArtTitle else { return }
    mediaArtTitle = title
    mediaArt = nil
    guard !title.isEmpty else { return }
    mediaQueue.async {
        let out = shell("/usr/bin/osascript", ["-e",
            "tell application \"Music\" to if it is running then return raw data of artwork 1 of current track"],
            timeout: 5)
        let image = imageFromAppleScriptData(out).map { thumbnail($0, side: mediaArtSide) }
        DispatchQueue.main.async {
            guard mediaArtTitle == title else { return }
            mediaArt = image
            repaint()
        }
    }
}

// osascript prints raw data as «data XXXX<hex>», with a four-letter type code
func imageFromAppleScriptData(_ out: String) -> NSImage? {
    guard let open = out.range(of: "«data "), let close = out.range(of: "»", options: .backwards),
          open.upperBound < close.lowerBound else { return nil }
    var data = Data()
    var high: UInt8?
    for c in out[open.upperBound..<close.lowerBound].utf8.dropFirst(4) {
        let v: UInt8
        switch c {
        case 48...57: v = c - 48
        case 65...70: v = c - 55
        case 97...102: v = c - 87
        default: return nil
        }
        if let h = high { data.append(h << 4 | v); high = nil } else { high = v }
    }
    return NSImage(data: data)
}

func thumbnail(_ image: NSImage, side: CGFloat) -> NSImage {
    let px = Int(side * 3) // sharp on any display scale up to 3x
    guard let full = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(full, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let small = ctx.makeImage() else { return image }
    return NSImage(cgImage: small, size: NSSize(width: side, height: side))
}

// --- right cluster ---------------------------------------------------------
// An item is data. Layout, hit-testing and drawing are generic over the
// list, so adding a pill needs one entry and one provider, with no
// per-item geometry, padding or width cache.

struct BarPart: Equatable {
    var icon = ""
    var iconColor: NSColor?
    var label = ""
    var labelColor: NSColor?
    var under = false
}

struct BarItem: Equatable {
    var icon = ""
    var label = ""
    var iconColor: NSColor?
    // a colour emoji draws its own colours and ignores an icon tint, so a
    // plugin's colour has to be able to land on the label instead
    var labelColor: NSColor?
    var drawing = true
    // more icon and label pairs after the first, so one plugin pill can
    // show several icons in their own colours
    var parts: [BarPart] = []
    // A second line that slides up in turn with the label, in the label's
    // width: tickerText is cut to fit, and tickerTail always shows.
    var tickerText = ""
    var tickerTail = ""
    // drawn in place of the icon and label
    var gauge: StatusGauge?
}

// screen order, left to right
let rightOrderAll = ["weather", "wifi", "bluetooth", "brightness", "mic", "volume", "status", "battery", "clock", "activity"]

// `<key> = <value>` lines in ~/.config/omacchiato/<name>
func readConf(_ name: String) -> [String: String] {
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omacchiato/\(name)")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
    var pairs: [String: String] = [:]
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"),
              let eq = line.firstIndex(of: "=") else { continue }
        pairs[line[..<eq].trimmingCharacters(in: .whitespaces)] =
            line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    }
    return pairs
}

// `<pill> = hide` or `<pill> = icon` per line. Read once at startup.
let pillModes = readConf("bar-pills.conf")

// Maps to System Settings > Accessibility > Display > Reduce Motion.
func dur(_ seconds: Double) -> Double {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : seconds
}

// The panels take the theme's accent and status colours. The panel glass
// follows the macOS appearance, so a theme of the other brightness keeps
// the system colours: a pale green on light glass is hard to read.
func applyPanelColors() {
    let darkSystem = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let bar = palette.barBG.usingColorSpace(.sRGB)
    let darkTheme = bar.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent < 0.5 } ?? darkSystem
    let themed = darkTheme == darkSystem
    PanelColors.accent = themed ? Color(nsColor: palette.accent) : .accentColor
    PanelColors.red = themed ? Color(nsColor: palette.red) : .red
    PanelColors.green = themed ? Color(nsColor: palette.green) : .green
    PanelColors.yellow = themed ? Color(nsColor: palette.yellow) : .yellow
    // themes carry no orange, and their yellow is amber enough for a warning
    PanelColors.orange = themed ? Color(nsColor: palette.yellow) : .orange
}
