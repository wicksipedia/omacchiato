// omacchiato-bar — a native bar surface, in ONE process.
//
// SLICE: workspace chips + front-app pill, on the built-in display only,
// drawn over sketchybar's own bar so the two can be watched side by side
// (sketchybar keeps the external display). This exists to answer one
// question with numbers rather than opinion: how much of the bar's
// latency is the work, and how much is the process boundaries?
//
// The shape of the answer is in the data flow. sketchybar learns that a
// workspace changed, forks a shell script, and that script spawns five
// window-manager CLI calls (~23 ms each) to ask what happened — 220 ms
// before a pixel moves. This daemon already holds the window model in
// memory, fed by the same SkyLight notifications the other daemons use,
// so a workspace switch touches no subprocess at all: update one field,
// draw one frame. The slow path (which windows exist, where) runs only
// on window create/destroy, off the critical path.
//
// Timings land in /tmp/omacchiato-bar.log as `switch <ws> <ms>`.
//
// The right cluster is the same eight pills the bar already carries, but
// reading their sources directly instead of forking a script that forks
// `pmset`, `osascript`, `networksetup` and `ipconfig`: IOPS for power,
// CoreAudio for volume, DisplayServices for brightness, SCDynamicStore
// for the network, IOBluetooth for devices. Every one of those is a
// publisher, so nothing here polls except the clock and the weather,
// which have no publisher to listen to.
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

// DisplayServices (private) — the same calls Control Center makes, and
// the same ones helper/main.swift uses for `omacchiato-helper brightness`.
@_silgen_name("DisplayServicesGetBrightness")
func DSGetBrightness(_ display: CGDirectDisplayID, _ value: UnsafeMutablePointer<Float>) -> Int32
@_silgen_name("DisplayServicesSetBrightness")
func DSSetBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Int32

// Brightness has a publisher after all. The callback's later arguments
// are deliberately untyped and never dereferenced: the arity is what the
// ABI needs, the contents are not ours to trust.
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
// Sending a window to another workspace ORDERS IT OUT, it does not move
// it: measured with a SkyLight probe, a workspace switch fires
// 806/808/815 but a window changing workspace fires only 808 and 815.
// Watching 806 for that is why the chips sat stale until some unrelated
// app next opened a window. They arrive as a pair; both are watched
// because the pairing is observed behaviour, not a documented promise.
let EVENT_WINDOW_ORDER: UInt32 = 808
let EVENT_WINDOW_VISIBILITY: UInt32 = 815
let EVENT_WINDOW_CREATE: UInt32 = 1325
let EVENT_WINDOW_DESTROY: UInt32 = 1326

// --- plumbing -------------------------------------------------------------

// OmniWM can start or quit while this daemon runs, so whether it is up is
// decided per use, never cached: the running-app check is an in-process
// lookup, cheap enough to be the whole detection.
let omniwmBundleID = "com.barut.OmniWM"

// Match by prefix: the dev build, com.barut.OmniWM.dev, uses the same socket.
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
// IPCResponse envelope; everything the bar wants lives two levels down
// at result.payload (OmniWM docs/IPC-CLI.md, "Response Format").
func omniQuery(_ name: String, _ args: [String] = []) -> [String: Any]? {
    // fast path: omacchiato-omni holds a persistent socket and launches in
    // ~3 ms where omniwmctl (Swift) needs ~10; it speaks `query <name>
    // [fields-csv]` and prints the same envelope. Anything fancier
    // (selector flags like --focused) stays on omniwmctl.
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

// click-to-jump. OmniWM's focus-name resolves a numeric raw workspace ID
// across all monitors, which is exactly what a chip on either display
// means.
func focusWorkspace(_ ws: String) {
    omniwmctl(["workspace", "focus-name", ws])
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

private struct BundleIdentifier {
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

private enum WorkspaceIcon {
    case glyph(String)
    case image(NSImage)
    case unavailable
}

private enum WorkspaceIconDeclaration {
    case glyph(String)
    case bundle(BundleIdentifier)
}

private struct WorkspaceIconConfig {
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

private func loadWorkspaceIconConfig() -> WorkspaceIconConfig {
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

private let workspaceIconConfig = loadWorkspaceIconConfig()

// --- theme ----------------------------------------------------------------
// The same palette sketchybar reads. Parsed once and kept as colours, not
// re-sourced per item by sixteen shell scripts.

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
    // The bar window is not opaque, so the window server takes the window's
    // click shape from the alpha channel. A pill at alpha 0 draws correctly
    // but stops accepting clicks anywhere except the glyph strokes.
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
    // a theme written before these were separate names only ITEM_BG, and
    // back then the pills and the popup fills were the same colour
    if !sawRowBG { p.rowBG = p.itemBG }
    return p
}

// Ask for the family by name and VERIFY we got it. sketchybar's
// `--default` silently handed half the bar "Hack Nerd Font", which is not
// installed, so the text fell back to a system face and nothing said so.
// A missing family is a loud fallback here, once, at startup.
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

// --- model ----------------------------------------------------------------

// Shared across every display: which workspace has focus, what the front
// app is, which workspaces hold what. Anything that differs per screen —
// the workspace set, the visible one, the notch — belongs to the surface.
final class Model {
    var focused = "" // globally focused workspace
    var wsApps: [String: [String]] = [:] // ws -> up to three app names, leftmost window first
    var focusedApp = "" // the app of the focused window, wherever it is
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

// SLOW path: who lives where. Three CLI calls — and it runs only when a
// window is created or destroyed, never on a workspace switch.
//
// It is computed OFF the main queue and applied on it. Measured the hard
// way: with the CLI calls inline on main, one contended rebuild blocked
// the render path for 7.6 seconds and every switch queued behind it. The
// architecture only pays off if subprocess work never sits on the path a
// frame has to travel.
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

// The answers out of omniwmctl: workspaces arrive with their display in
// one query, and the windows query brings the app names the icon
// chips need. The snapshot also carries focus: it rides the slow path
// here, and the workspace-bar stream below covers the fast one.
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
    // visible/focused come from the DISPLAYS query: the workspaces
    // query's isVisible/isFocused go dark on EMPTY workspaces (the
    // same trap omacchiato-ws hit), and the pill for a focused empty 8/9
    // never lit up
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

// Leftmost window first, to match the workspace-bar stream: it lists a
// niri workspace's apps in layout order. OmniWM parks the windows of a
// hidden workspace on one frame, so a tie keeps the query order, which
// is the layout order. A tie on the app name flipped the icons.
func layoutOrder(_ wins: [(x: Double, y: Double, app: String)]) -> [String] {
    wins.enumerated()
        .sorted { ($0.element.x, $0.element.y, $0.offset) < ($1.element.x, $1.element.y, $1.offset) }
        .map(\.element.app)
}

// Reports whether anything actually moved. A workspace switch produces
// window moves too, and those snapshots come back identical — saying so
// keeps the repaint (and the log line) for the times something changed.
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
// Apple Music posts a playback notification on every change, and that
// payload already carries Name, Artist and Player State. So the only
// subprocess left is the one a click sends — user-initiated, where 20 ms
// does not show.

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

// The current track's artwork, fetched once per track change and shrunk to
// the pill's size, so a redraw never scales the full 800 px original.
var mediaArt: NSImage?
var mediaArtTitle = ""
// computed, not stored: this file's globals initialise top to bottom, and
// pillHeight is declared further down, so a stored value read it as zero
var mediaArtSide: CGFloat { pillHeight - 6 }

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
// list, so adding a pill is one entry and one provider — no per-item
// geometry, no padding arithmetic, no width caches.

struct BarPart: Equatable {
    var icon = ""
    var iconColor: NSColor?
    var label = ""
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
}

// screen order, left to right
let rightOrderAll = ["weather", "wifi", "bluetooth", "brightness", "mic", "volume", "battery", "clock", "activity"]

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

// --- --request-permissions -------------------------------------------------
// A direct run asks for the terminal's grants, so start the switch through
// omacchiato-permissions. It runs before the bar draws or subscribes to
// anything. It can read only the globals above this line.

final class PermissionAnswer: NSObject, CBCentralManagerDelegate, CLLocationManagerDelegate {
    var answered = false
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if CBCentralManager.authorization != .notDetermined { answered = true }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { answered = true }
    }
    // the prompt stays up until the person answers it
    func wait() {
        let deadline = Date().addingTimeInterval(120)
        while !answered, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    }
}

func requestPermissions() -> Never {
    func report(_ name: String, _ state: String) {
        print(name, state)
        fflush(stdout)
    }

    // AEDeterminePermissionToAutomateTarget blocks until the person answers
    for (name, bundleID) in [("automation-system-events", "com.apple.systemevents"),
                             ("automation-ghostty", "com.mitchellh.ghostty"),
                             ("automation-music", musicBundleID),
                             ("automation-calendar", "com.apple.iCal")] {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true) {
        case noErr: report(name, "granted")
        case OSStatus(errAEEventNotPermitted): report(name, "denied")
        default: report(name, "unknown") // procNotFound: the app is not running
        }
    }

    // Asked even when the bluetooth pill is hidden: a plugin command runs as
    // the bar's child, so it reads Bluetooth with the bar's grant. The AirPods
    // pill does.
    let answer = PermissionAnswer()
    var central: CBCentralManager?
    if CBCentralManager.authorization == .notDetermined {
        central = CBCentralManager(delegate: answer, queue: .main)
        answer.wait()
    }
    _ = central
    switch CBCentralManager.authorization {
    case .allowedAlways: report("bluetooth", "granted")
    case .notDetermined: report("bluetooth", "unknown")
    default: report("bluetooth", "denied")
    }

    // Skip the grant of a hidden pill. Only the wifi pill reads the location.
    if pillModes["wifi"] != "hide" {
        let answer = PermissionAnswer()
        let manager = CLLocationManager()
        manager.delegate = answer
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            answer.wait()
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized: report("location", "granted")
        case .notDetermined: report("location", "unknown")
        default: report("location", "denied")
        }
    }

    // The clock popup lists what is left of today.
    if pillModes["clock"] != "hide" {
        let answer = PermissionAnswer()
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            EKEventStore().requestFullAccessToEvents { _, _ in answer.answered = true }
            answer.wait()
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: report("calendar", "granted")
        case .notDetermined: report("calendar", "unknown")
        default: report("calendar", "denied")
        }
    }

    // Last, because its dialog does not block: it stays up after the exit.
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    report("accessibility", AXIsProcessTrustedWithOptions(prompt) ? "granted" : "denied")
    report("done", "")
    exit(0)
}

// A pill defined in ~/.config/omacchiato/bar-plugins.conf: an INI section
// per pill, with a shell command whose stdout becomes the label. This is
// the escape hatch from rebuilding for every new widget.
struct BarPlugin {
    var name = ""
    var command = ""
    var icon = ""
    var iconColor = ""
    var interval: TimeInterval = 30
}

let barPlugins: [BarPlugin] = {
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omacchiato/bar-plugins.conf")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    var found: [BarPlugin] = []
    var current: BarPlugin?
    func flush() {
        // a section with no command draws nothing, so it is not a pill
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
        // a runaway interval would spawn a process per frame
        case "interval": current?.interval = max(1, Double(value) ?? 30)
        default: break
        }
    }
    flush()
    // a plugin may not shadow a built-in pill: set() would fight its provider
    let builtin = Set(rightOrderAll)
    var seen = Set<String>()
    return found.filter { !$0.name.isEmpty && !builtin.contains($0.name) && seen.insert($0.name).inserted }
}()

// A hidden pill also skips its provider, so hiding weather stops the
// wttr.in fetches and hiding bluetooth never touches the Bluetooth grant.
let rightOrder = (["menubar"] + barPlugins.map(\.name) + rightOrderAll).filter { pillModes[$0] != "hide" }
let iconOnly = Set(pillModes.filter { $0.value == "icon" }.keys)

// Accessibility > Display > Reduce motion: the popup must appear at once.
func dur(_ seconds: Double) -> Double {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : seconds
}

// `popup = glass` puts the popup on Liquid Glass instead of a flat fill.
// Reduce transparency turns it off again.
var popupGlass: Bool {
    pillModes["popup"] == "glass"
        && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
}
var rightItems: [String: BarItem] = [:]
// popup rows a plugin last returned, keyed by pill name
var pluginRows: [String: [PopupRow]] = [:]

func set(_ name: String, _ mutate: (inout BarItem) -> Void) {
    var item = rightItems[name] ?? BarItem()
    mutate(&item)
    guard item != rightItems[name] else { return } // no pixels owed
    let t0 = DispatchTime.now().uptimeNanoseconds
    rightItems[name] = item
    repaint()
    // an open popup shows the same state as its pill — the brightness
    // popup kept whatever value it was built with while the pill moved
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
    var status: Int32 = -1 // -1 when the command did not start
    var timedOut = false
}

// After `timeout` seconds, stop the command and every process under it, and
// return what it printed. A child of sh -c can hold the pipe open.
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
    // read stderr at the same time, or a full stderr pipe blocks the command
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

// The command is argv to sh, never spliced into a shell string: the
// config is the user's own file, but a value carrying a quote should
// still fail as a command rather than become a second one.
// palette is read on the main thread only: a theme switch rewrites it,
// and a plugin resolves its colour one interval later either way
func pluginColor(_ name: String?) -> NSColor? {
    switch name {
    case "accent": return palette.accent
    case "label": return palette.label
    case "muted": return palette.muted
    case "red": return palette.red
    case "green": return palette.green
    case "yellow": return palette.yellow
    default:
        // #RRGGBB, for a brand colour that no theme carries
        guard let hex = name, hex.count == 7, hex.hasPrefix("#"),
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

func pluginPopupRows(_ raw: [[String: Any]], of plugin: BarPlugin) -> [PopupRow] {
    raw.map { spec in
        // a row's "url", "terminal" or "run" becomes the action a click
        // performs: JSON cannot carry a closure
        var action: (() -> Void)?
        // x-apple.systempreferences opens a System Settings page and nothing else
        if let link = spec["url"] as? String, let url = URL(string: link),
           ["https", "x-apple.systempreferences"].contains(url.scheme) {
            action = { NSWorkspace.shared.open(url) }
        } else if let command = spec["run"] as? String, !command.isEmpty {
            // same trust as "terminal"; the plugin runs again so an open popup shows the change
            action = {
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = shell("/bin/sh", ["-c", command], env: pluginEnv(plugin))
                    runPlugin(plugin)
                }
            }
        } else if let command = spec["terminal"] as? String, !command.isEmpty {
            // The plugin's own command already runs with the bar's grants, so a
            // row it prints may name a command too. Ghostty gets it as
            // --command, like the activity pill's btop: -e asks to confirm.
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

// the sections a click opened or closed, by plugin, header text and the
// count of earlier headers with that text. The bar forgets them when it restarts.
var sectionOpen: [String: Bool] = [:]
// The rows a popup holds before folding. Inline bars share one label
// column and one number column, and measuring those over the VISIBLE
// rows moved every bar when a section opened.
var popupBarSource: [PopupRow] = []

// A header row toggles the rows after it, up to the next header or "end" row.
// A separator right before the next header stays, so closed sections keep their rules.
func foldSections(_ name: String, _ rows: [PopupRow]) -> [PopupRow] {
    var out: [PopupRow] = []
    var hiding = false
    var seen: [String: Int] = [:]
    for (index, var row) in rows.enumerated() {
        switch row.section {
        case "open", "closed":
            // the detail changes as numbers change, so the key cannot use it
            seen[row.text, default: 0] += 1
            let key = "\(name)\t\(row.text)\t\(seen[row.text]!)"
            let open = sectionOpen[key] ?? (row.section == "open")
            row.detail = [row.detail, open ? "▾" : "▸"].filter { !$0.isEmpty }.joined(separator: " ")
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
    // launchd hands this process a bare PATH, so a plugin naming its
    // own script or a Homebrew binary would silently find nothing.
    // Put the places a command is actually installed in front of it.
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:"
        + (env["PATH"] ?? "/usr/bin:/bin")
    // the configured icon, so a command can decorate it rather than
    // having to hardcode the glyph its own config already names
    env["OMACCHIATO_PILL_ICON"] = plugin.icon
    return env
}

// A plugin runs once at a time: a hung command must not pile up a new copy
// on each tick, and an old answer must not overwrite a new one. Requests
// during a run fold into one more run when it ends.
struct RunGate {
    var running: Set<String> = []
    var again: Set<String> = []

    mutating func start(_ name: String) -> Bool {
        if running.insert(name).inserted { return true }
        again.insert(name)
        return false
    }

    // true when a request came during the run
    mutating func finish(_ name: String) -> Bool {
        running.remove(name)
        return again.remove(name) != nil
    }
}
var pluginGate = RunGate() // main thread only

// A run failed if it timed out, or if it exited non-zero and printed
// nothing. The answer is the problem and stderr's first line, for the popup.
func pluginProblem(_ result: ShellResult, limit: TimeInterval) -> (what: String, detail: String)? {
    let firstErr = result.err.split(separator: "\n").first.map { String($0.prefix(60)) } ?? ""
    if result.timedOut { return ("no answer in \(Int(limit)) s", firstErr) }
    guard result.status != 0, result.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return ("failed with exit \(result.status)", firstErr)
}

// the rows of the last run that worked, shown under an error
var pluginGoodRows: [String: [PopupRow]] = [:]

// Keep the last label but dim it, and put the error at the top of the
// popup. A pill that hides when all is well shows a warning icon instead.
func showPluginProblem(_ plugin: BarPlugin, _ problem: (what: String, detail: String)) {
    tlog("plugin \(plugin.name): \(problem.what) \(problem.detail)")
    var rows = [PopupRow(icon: "\u{F071}", text: problem.what, tint: palette.red, iconTint: palette.red)]
    if !problem.detail.isEmpty { rows.append(PopupRow(text: problem.detail, dim: true)) }
    rows.append(PopupRow(text: "run again", dim: true, action: { runPlugin(plugin) }))
    let good = pluginGoodRows[plugin.name] ?? []
    pluginRows[plugin.name] = rows + (good.isEmpty ? [] : [PopupRow(separator: true)] + good)
    set(plugin.name) {
        if $0.icon.isEmpty && $0.label.isEmpty { $0.icon = "\u{F071}" }
        $0.iconColor = palette.muted
        $0.labelColor = palette.muted
    }
    if openPopup == plugin.name { refreshPopup() }
}

func runPlugin(_ plugin: BarPlugin) {
    guard Thread.isMainThread else { DispatchQueue.main.async { runPlugin(plugin) }; return }
    guard pluginGate.start(plugin.name) else { return }
    DispatchQueue.global(qos: .utility).async {
        let env = pluginEnv(plugin)
        let limit = max(plugin.interval, 30)
        let result = execute("/bin/sh", ["-c", plugin.command], env: env, timeout: limit)
        if let problem = pluginProblem(result, limit: limit) {
            DispatchQueue.main.async {
                if pluginGate.finish(plugin.name) { runPlugin(plugin) }
                showPluginProblem(plugin, problem)
            }
            return
        }
        let out = result.out
        // A command may answer with a JSON object to set a colour and
        // popup rows. Anything else is a plain label, which stays the
        // common case and needs no quoting.
        let obj = out.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        // the cluster is laid out from the right edge inwards, so an
        // unbounded label would push every other pill off the left
        let plain = out.split(separator: "\n").first.map(String.init) ?? ""
        let label = String((obj?["label"] as? String ?? plain)
            .trimmingCharacters(in: .whitespaces).prefix(32))
        let rawParts = obj?["parts"] as? [[String: Any]] ?? []
        DispatchQueue.main.async {
            if pluginGate.finish(plugin.name) { runPlugin(plugin) }
            pluginGoodRows[plugin.name] = pluginPopupRows(obj?["rows"] as? [[String: Any]] ?? [], of: plugin)
            pluginRows[plugin.name] = pluginGoodRows[plugin.name]
            let color = pluginColor(obj?["color"] as? String)
            let icon = obj?["icon"] as? String ?? plugin.icon
            let parts = rawParts.map {
                BarPart(icon: $0["icon"] as? String ?? "",
                        iconColor: pluginColor($0["icon_color"] as? String) ?? color,
                        label: String(($0["label"] as? String ?? "").prefix(32)))
            }
            set(plugin.name) {
                $0.icon = icon
                $0.label = label
                $0.iconColor = pluginColor(plugin.iconColor) ?? color
                $0.labelColor = color
                $0.parts = parts
            }
            // set() refreshes an open popup only when the pill changed, and the rows can change alone
            if openPopup == plugin.name { refreshPopup() }
        }
    }
}

func startPlugins() {
    for plugin in barPlugins where rightOrder.contains(plugin.name) {
        runPlugin(plugin)
        Timer.scheduledTimer(withTimeInterval: plugin.interval, repeats: true) { _ in
            runPlugin(plugin)
        }
    }
}

// --- clock (no publisher: the one honest timer, aligned to the minute)
func updateClock() {
    let f = DateFormatter()
    f.dateFormat = "EEE dd MMM  HH:mm"
    loadTodayEvents()
    let now = Date()
    let next = todayEvents.first { soonLabel(start: $0.startDate, allDay: $0.isAllDay, now: now) != nil }
    soonMeetingLink = next.flatMap { meetingLink(url: $0.url, location: $0.location, notes: $0.notes) }
    set("clock") {
        $0.icon = "󰃰"
        $0.label = f.string(from: now)
        $0.tickerText = next.map { $0.title ?? "event" } ?? ""
        $0.tickerTail = next.flatMap { soonLabel(start: $0.startDate, allDay: $0.isAllDay, now: now) } ?? ""
    }
}

// The clock names the next event from 10 minutes before it until
// 5 minutes after it starts. A click then opens its meeting link.
var soonMeetingLink: URL?

func soonLabel(start: Date, allDay: Bool, now: Date) -> String? {
    guard !allDay else { return nil }
    let left = start.timeIntervalSince(now)
    guard left > -5 * 60, left <= 10 * 60 else { return nil }
    return left <= 0 ? "now" : "in \(Int((left / 60).rounded(.up)))m"
}

// A link that opens the event in Calendar. A repeating event shares one
// identifier, so the link also names the start of this occurrence, in UTC.
func calendarLink(id: String, start: Date, repeats: Bool) -> URL? {
    guard let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
    var path = safe
    if repeats {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        path = f.string(from: start) + "/" + safe
    }
    return URL(string: "ical://ekevent/\(path)?method=show&options=more")
}

// The event URL if it has one, else the first video call link in the
// location or the notes.
func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
    if let url, url.scheme == "https" { return url }
    let hosts = ["teams.microsoft.com", "teams.live.com", "zoom.us", "meet.google.com", "webex.com", "whereby.com"]
    for text in [location, notes].compactMap({ $0 }) {
        for word in text.split(whereSeparator: { $0.isWhitespace || "<>\"()".contains($0) }) {
            guard let link = URL(string: String(word)), link.scheme == "https",
                  let host = link.host?.lowercased(),
                  hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
            return link
        }
    }
    return nil
}

// --- battery (IOPS publishes, capacity ticks included)
// IOPS carries the charge and the time; health, cycles and the live draw
// only exist in the registry entry.
func smartBattery() -> [String: Any] {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return [:] }
    defer { IOObjectRelease(service) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any]
    else { return [:] }
    return dict
}

// High power mode has no public API, and pmset costs about 13 ms. That is
// fine on a notification and would not be on a timer, so it is cached.
var highPowerMode = false

func readHighPowerMode() -> Bool {
    shell("/usr/bin/pmset", ["-g"])
        .split(separator: "\n")
        .first { $0.contains("powermode") }?
        .split(separator: " ").last == "2"
}

// Only LOW power mode publishes a change, so leaving high power for
// automatic is a silent transition. The minute tick catches it; the
// notification just makes the low-power case immediate.
// Never assign highPowerMode directly. The icon is only redrawn when this
// notices a change, so a silent write leaves the pill stale for good: the
// popup used to set it, and the next tick then saw nothing to do.
func applyHighPowerMode(_ high: Bool) {
    guard high != highPowerMode else { return }
    highPowerMode = high
    updateBattery()
}

func refreshPowerMode() {
    DispatchQueue.global(qos: .utility).async {
        let high = readHighPowerMode()
        DispatchQueue.main.async { applyHighPowerMode(high) }
    }
}

func powerModeName() -> String? {
    if ProcessInfo.processInfo.isLowPowerModeEnabled { return "low power" }
    return highPowerMode ? "high power" : nil
}

func updateBattery() {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
    else { return }
    for source in list {
        guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int else { continue }
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        // same thresholds and glyphs the bar already uses
        var icon = "󰂃", color = palette.red
        switch pct {
        case 90...: icon = "󰁹"; color = palette.green
        case 60..<90: icon = "󰂀"; color = palette.label
        case 30..<60: icon = "󰁾"; color = palette.label
        case 10..<30: icon = "󰁻"; color = palette.yellow
        default: break
        }
        if charging { icon = "󰂄"; color = palette.green }
        // a leaf or a speedometer beside the cell, so the mode is visible
        // without opening anything
        let mode = ProcessInfo.processInfo.isLowPowerModeEnabled ? "\u{F032A}"
            : (highPowerMode ? "\u{F04C5}" : "")
        // `battery = time`: the icon alone on AC; on battery, the time left
        // in whole hours, or in minutes under an hour. 65535 means the
        // estimate is not ready yet.
        var label = "\(pct)%"
        if pillModes["battery"] == "time" {
            let minutes = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            label = charging || minutes <= 0 || minutes >= 65535 ? ""
                : (minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
        }
        set("battery") { $0.icon = icon + mode; $0.iconColor = color; $0.label = label }
        return
    }
}

// --- volume (CoreAudio publishes on the device itself)
func defaultOutputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

func defaultInputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

// A device with no mute switch is muted by having its input volume taken
// to zero instead, so a pill that only read the switch would miss it.
func micMuted() -> Bool {
    let dev = defaultInputDevice()
    guard dev != 0 else { return false }

    var muted: UInt32 = 0
    var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
    var muteSize = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &muteSize, &muted) == noErr, muted != 0 {
        return true
    }

    var level: Float32 = -1
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                          mScope: kAudioDevicePropertyScopeInput,
                                          mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &level) == noErr else { return false }
    return level <= 0.0001
}

// the pill exists to say the microphone is off, so it draws only then
func updateMic() {
    let muted = micMuted()
    set("mic") {
        $0.drawing = muted
        $0.icon = muted ? "\u{F036D}" : ""
        $0.iconColor = muted ? palette.red : nil
    }
}

func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                               mScope: kAudioDevicePropertyScopeOutput, mElement: element)
}

func readVolume() -> (percent: Int, muted: Bool)? {
    let dev = defaultOutputDevice()
    guard dev != 0 else { return nil }

    var muted: UInt32 = 0
    var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
    var muteSize = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &muteSize, &muted)

    var level: Float32 = 0
    var addr = volumeAddress(kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Float32>.size)
    if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &level) != noErr {
        // a device without a master channel: average the stereo pair
        var sum: Float32 = 0
        var found = 0
        for channel in UInt32(1)...UInt32(2) {
            var chAddr = volumeAddress(channel)
            var chSize = UInt32(MemoryLayout<Float32>.size)
            var value: Float32 = 0
            if AudioObjectGetPropertyData(dev, &chAddr, 0, nil, &chSize, &value) == noErr {
                sum += value
                found += 1
            }
        }
        guard found > 0 else { return nil }
        level = sum / Float32(found)
    }
    return (Int((level * 100).rounded()), muted != 0)
}

func toggleMute() {
    let dev = defaultOutputDevice()
    guard dev != 0, let now = readVolume() else { return }
    var value: UInt32 = now.muted ? 0 : 1
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                          mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMain)
    AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
}

func writeVolume(_ percent: Int) {
    let dev = defaultOutputDevice()
    guard dev != 0 else { return }
    var value = Float32(min(100, max(0, percent))) / 100
    let size = UInt32(MemoryLayout<Float32>.size)
    var addr = volumeAddress(kAudioObjectPropertyElementMain)
    if AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &value) != noErr {
        for channel in UInt32(1)...UInt32(2) {
            var chAddr = volumeAddress(channel)
            AudioObjectSetPropertyData(dev, &chAddr, 0, nil, size, &value)
        }
    }
}

// the output devices the volume popup lists — the same enumeration
// helper/main.swift does for `omacchiato-helper audio`, without the round trip
func audioOutputDevices() -> [(id: AudioDeviceID, name: String)] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
    else { return [] }

    var result: [(AudioDeviceID, String)] = []
    for id in ids {
        // output-capable only: a device with no output streams is a mic
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0
        else { continue }

        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var ok = false
        withUnsafeMutablePointer(to: &name) { ptr in
            ok = AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, ptr) == noErr
        }
        guard ok else { continue }
        result.append((id, name as String))
    }
    return result
}

func setDefaultOutputDevice(_ id: AudioDeviceID) {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var dev = id
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                               UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
}

func updateVolume() {
    guard let v = readVolume() else { return }
    let silent = v.muted || v.percent == 0
    // `volume = muted` makes it the mic pill's twin: drawn only while
    // the output is silent
    if pillModes["volume"] == "muted" {
        set("volume") {
            $0.drawing = silent
            $0.icon = silent ? "󰝟" : ""
            $0.iconColor = silent ? palette.red : nil
            $0.label = ""
        }
        return
    }
    let icon: String
    if silent {
        icon = "󰝟"
    } else if v.percent >= 70 {
        icon = "󰕾"
    } else if v.percent >= 30 {
        icon = "󰖀"
    } else {
        icon = "󰕿"
    }
    set("volume") { $0.icon = icon; $0.iconColor = nil; $0.label = v.muted ? "mute" : "\(v.percent)%" }
}

// --- shade (below the hardware minimum, without an overlay window) -------
// QuickShade and friends float a translucent black window over everything.
// That works, but the window is real: it sits in the z-order, it covers
// the bar, and it turns every screenshot black — including yours. Scaling
// the display's GAMMA instead dims at scanout, so there is no window, it
// applies over fullscreen apps, and captures come out normal.
//
// It also fails safe. Gamma set by a process is reset when that process
// exits (verified), so a crash or an uninstall restores the screen by
// itself and there is no way to be left staring at a dark display.
//
// Bonus: unlike DisplayServices this reaches EXTERNAL displays, which have
// no backlight API without DDC.
let shadeFile = "\(NSHomeDirectory())/.local/state/omacchiato/shade"
let shadeFloor: Double = 0.15 // never darker than this fraction of output

var shade: Double = {
    guard let t = try? String(contentsOfFile: shadeFile, encoding: .utf8),
          let v = Double(t.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
    return min(1, max(0, v))
}()

func applyShade() {
    let scale = Float(1 - shade * (1 - shadeFloor))
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(8, &ids, &count) == .success else { return }
    for i in 0..<Int(count) {
        if shade <= 0.001 {
            CGDisplayRestoreColorSyncSettings()
        } else {
            CGSetDisplayTransferByFormula(ids[i], 0, scale, 1, 0, scale, 1, 0, scale, 1)
        }
    }
}

func setShade(_ value: Double) {
    shade = min(1, max(0, value))
    applyShade()
    try? String(format: "%.3f", shade).write(toFile: shadeFile, atomically: true, encoding: .utf8)
    updateBrightness()
}

// --- brightness (DisplayServices publishes; built-in panel only)
func builtinDisplayID() -> CGDirectDisplayID {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
}

func updateBrightness() {
    var value: Float = 0
    guard DSGetBrightness(builtinDisplayID(), &value) == 0, value.isFinite else {
        set("brightness") { $0.drawing = false } // hide rather than lie
        return
    }
    let pct = Int((value * 100).rounded())
    // Shaded reads as BELOW zero, because that is what it is: past the
    // point the backlight can go. The moon says which side of zero you are on.
    if shade > 0.001 {
        set("brightness") {
            $0.drawing = true
            $0.icon = "\u{F0594}"
            $0.iconColor = palette.muted
            $0.label = "−\(Int((shade * 100).rounded()))%"
        }
        return
    }
    let icon = pct >= 66 ? "󰃠" : (pct >= 33 ? "󰃟" : "󰃞")
    set("brightness") { $0.drawing = true; $0.icon = icon; $0.iconColor = nil; $0.label = "\(pct)%" }
}

// --- location (what the network name costs) -------------------------------
// macOS classes the SSID as location data. Two things are required and
// neither alone is enough: this grant, and a BUNDLED binary — measured,
// an unbundled build reads nil with authorisation held, services on and
// updates running, while a bundled one reads the name the instant the
// answer lands. Nothing here reads a coordinate; the authorisation IS
// the API, and the manager exists only to ask for it.
//
// Gated like bluetooth: TCC judges the RESPONSIBLE process, so only the
// launchd-started bar may prompt and running it by hand stays quiet.
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var managed: Bool { ProcessInfo.processInfo.environment["OMACCHIATO_MANAGED"] != nil }

    func start() {
        manager.delegate = self
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            updateWifi() // the name is readable now; the pill may predate it
        case .denied, .restricted:
            tlog("location: denied — the wi-fi pill stays nameless")
        default:
            guard managed else {
                tlog("location: not launchd-managed, so not prompting")
                return
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    // the name appears the moment the answer lands — no restart, and no
    // polling for a permission that publishes
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        tlog("location: authorization now \(m.authorizationStatus.rawValue)")
        updateWifi()
    }
}
let locationGate = LocationGate()

// --- night shift (CBBlueLightClient publishes) ---------------------------
// Private CoreBrightness, reached by reflection the way omacchiato-helper
// reaches it. It has a publisher: setStatusNotificationBlock fires on
// every change whoever made it — the schedule, Control Center, System
// Settings, us. The popup used to cache what one subprocess printed
// the first time it opened, so anything that turned night shift off
// afterwards left the row reading yesterday's answer until the bar
// restarted.
struct BlueLightStatus {
    // `active` read true in every state measured here — toggle on and
    // off, inside and outside the schedule window — so the row reads
    // `enabled`, which is the field setEnabled: actually moves
    var active: ObjCBool = false
    var enabled: ObjCBool = false
    var sunSchedulePermitted: ObjCBool = false
    var mode: Int32 = 0
    var schedule: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
    var disableFlags: UInt64 = 0
    var available: ObjCBool = false
}

let blueLight: (cls: NSObject.Type, client: NSObject)? = {
    guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                 RTLD_LAZY) != nil,
        let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
    else {
        tlog("CoreBrightness unavailable — no night shift row")
        return nil
    }
    return (cls, cls.init())
}()

func blueLightStatus() -> BlueLightStatus? {
    let sel = NSSelectorFromString("getBlueLightStatus:")
    guard let bl = blueLight, let m = class_getInstanceMethod(bl.cls, sel) else { return nil }
    typealias GetFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    let f = unsafeBitCast(method_getImplementation(m), to: GetFn.self)
    var st = BlueLightStatus()
    let ok = withUnsafeMutablePointer(to: &st) { f(bl.client, sel, UnsafeMutableRawPointer($0)) }
    return ok ? st : nil
}

func setNightShift(_ on: Bool) {
    let sel = NSSelectorFromString("setEnabled:")
    guard let bl = blueLight, let m = class_getInstanceMethod(bl.cls, sel) else { return }
    typealias SetFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
    _ = unsafeBitCast(method_getImplementation(m), to: SetFn.self)(bl.client, sel, on)
}

// CoreBrightness keeps the block, so the block has to keep itself
var nightShiftBlock: (@convention(block) () -> Void)? = nil

func watchNightShift() {
    let sel = NSSelectorFromString("setStatusNotificationBlock:")
    guard let bl = blueLight, let m = class_getInstanceMethod(bl.cls, sel) else {
        tlog("night shift notifications unavailable — the row reads fresh on open only")
        return
    }
    let block: @convention(block) () -> Void = {
        DispatchQueue.main.async {
            guard let s = blueLightStatus() else { return }
            // which field a schedule boundary actually moves is worth
            // having in the log the morning after
            tlog("night shift changed: enabled=\(s.enabled.boolValue) "
                + "active=\(s.active.boolValue) mode=\(s.mode)")
            if openPopup == "brightness" { refreshPopup() }
        }
    }
    nightShiftBlock = block
    typealias SetFn = @convention(c) (AnyObject, Selector, Any) -> Void
    unsafeBitCast(method_getImplementation(m), to: SetFn.self)(bl.client, sel, block)
}

// --- wifi (SCDynamicStore publishes; SSID needs a subprocess, so it is
// fetched off-main and only when the network actually changed)
var wifiDevice = CWWiFiClient.shared().interface()?.interfaceName ?? "en0"

func updateWifi() {
    let powered = CWWiFiClient.shared().interface()?.powerOn() ?? false
    guard powered else {
        set("wifi") { $0.icon = "󰖪"; $0.iconColor = nil; $0.label = "off" }
        return
    }
    // The name lives in the POPUP, not the pill: a seventeen-character
    // SSID is ~150pt of bar, and the right cluster is right-aligned, so
    // on the notched display it pushed the far end under the notch. The
    // icon says connected; a click says to what.
    set("wifi") { $0.icon = "󰖩"; $0.iconColor = nil; $0.label = "" }
}

// --- bluetooth (IOBluetooth publishes connect/disconnect)
//
// IOBluetooth ABORTS the process outright — SIGABRT, no exception to
// catch — if it is touched without the Bluetooth privacy grant. Learnt
// here the same way watcher.swift learnt it: exit code 134 and an empty
// log. So the grant is gated on CBCentralManager.authorization (reading
// that never prompts), and the pill simply stays hidden when it is not
// held. The binary carries helper/bar-info.plist for the usage string,
// without which the prompt cannot even be raised.
func updateBluetooth() {
    guard CBCentralManager.authorization == .allowedAlways else { return }
    guard BTGetPower() != 0 else {
        set("bluetooth") { $0.drawing = true; $0.icon = "󰂲"; $0.iconColor = nil; $0.label = "off" }
        return
    }
    let connected = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [])
        .filter { $0.isConnected() }.count
    set("bluetooth") {
        $0.drawing = true
        $0.icon = connected > 0 ? "󰂱" : "󰂯"
        $0.iconColor = nil
        $0.label = connected > 0 ? "\(connected)" : ""
    }
}

// IOBluetooth's connect/disconnect notifications are ObjC target/action,
// so they need a real object to aim at; CoreBluetooth's delegate is what
// tells us the grant has landed.
final class BluetoothWatcher: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var classicStarted = false

    // Creating a CBCentralManager is itself an access, and TCC judges it
    // by the RESPONSIBLE process rather than this binary: started from a
    // shell the whole process is killed (SIGABRT, exit 134, no report),
    // embedded Info.plist and signature notwithstanding. Under launchd it
    // is responsible for itself and may prompt — which is the only reason
    // watcher.swift could. The plist sets OMACCHIATO_MANAGED so that running
    // this by hand for a test stays safe instead of dying.
    private var managed: Bool { ProcessInfo.processInfo.environment["OMACCHIATO_MANAGED"] != nil }

    func start() {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            startClassic()
            central = CBCentralManager(delegate: self, queue: .main)
        case .denied, .restricted:
            tlog("bluetooth: permission denied — pill hidden")
            set("bluetooth") { $0.drawing = false }
        default:
            guard managed else {
                tlog("bluetooth: not launchd-managed, so not prompting — pill hidden")
                set("bluetooth") { $0.drawing = false }
                return
            }
            set("bluetooth") { $0.drawing = false }
            central = CBCentralManager(delegate: self, queue: .main) // raises the prompt
        }
    }

    private func startClassic() {
        guard !classicStarted else { return }
        classicStarted = true
        IOBluetoothDevice.register(forConnectNotifications: self,
                                   selector: #selector(connected(_:device:)))
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        where device.isConnected() {
            device.register(forDisconnectNotification: self, selector: #selector(changed(_:device:)))
        }
        updateBluetooth()
    }

    @objc func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(changed(_:device:)))
        DispatchQueue.main.async { updateBluetooth() }
    }

    @objc func changed(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { updateBluetooth() }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        if status != kIOReturnSuccess { tlog("bluetooth: connect \(device.name ?? "?") failed \(status)") }
        DispatchQueue.main.async { updateBluetooth(); refreshPopup() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if CBCentralManager.authorization == .allowedAlways { startClassic() }
        DispatchQueue.main.async { updateBluetooth() }
    }
}
let bluetoothWatcher = BluetoothWatcher()

// --- weather (no publisher; wttr.in, refreshed on a long timer)
// One j1 fetch feeds both the pill and its popup — weather.sh does the
// same, via a cache file it writes atomically because a click can read it
// mid-write. In one process the struct IS the cache and that race cannot
// be expressed.

struct Weather {
    var emoji = ""
    var temp = ""
    var desc = ""
    var feels = ""
    var low = ""
    var high = ""
    var wind = ""
    var humidity = ""
    var rain = ""
    var sunrise = ""
    var sunset = ""
    var moon = ""
    var location = ""
}

var weather: Weather?

// WWO condition code -> glyph, night-aware for the clear/partly pair
func weatherEmoji(_ code: Int, night: Bool) -> String {
    switch code {
    case 113: return night ? "🌙" : "☀️"
    case 116: return night ? "☁️" : "⛅"
    case 119, 122: return "☁️"
    case 143, 248, 260: return "🌫️"
    case 176, 263, 266, 293, 296, 353: return "🌦️"
    case 299, 302, 305, 308, 356, 359: return "🌧️"
    case 200, 386, 389, 392, 395: return "⛈️"
    case 179, 182, 185, 227, 230, 281, 284, 311...338, 350, 362...368, 374...377: return "❄️"
    default: return "🌡️"
    }
}

func moonEmoji(_ phase: String) -> String {
    switch phase {
    case "New Moon": return "🌑"
    case "Waxing Crescent": return "🌒"
    case "First Quarter": return "🌓"
    case "Waxing Gibbous": return "🌔"
    case "Full Moon": return "🌕"
    case "Waning Gibbous": return "🌖"
    case "Last Quarter", "Third Quarter": return "🌗"
    case "Waning Crescent": return "🌘"
    default: return "🌙"
    }
}

func updateWeather() {
    guard let url = URL(string: "https://wttr.in/?format=j1") else { return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (root["current_condition"] as? [[String: Any]])?.first,
              let today = (root["weather"] as? [[String: Any]])?.first
        else { return }

        func text(_ d: [String: Any], _ key: String) -> String { d[key] as? String ?? "" }
        func nested(_ d: [String: Any], _ key: String) -> String {
            ((d[key] as? [[String: Any]])?.first?["value"] as? String) ?? ""
        }

        var w = Weather()
        let hour = Calendar.current.component(.hour, from: Date())
        w.emoji = weatherEmoji(Int(text(current, "weatherCode")) ?? 0, night: hour < 7 || hour >= 20)
        w.temp = text(current, "temp_C")
        w.desc = nested(current, "weatherDesc").lowercased()
        w.feels = text(current, "FeelsLikeC")
        w.low = text(today, "mintempC")
        w.high = text(today, "maxtempC")
        w.humidity = text(current, "humidity")

        let degrees = Int(text(current, "winddirDegree")) ?? 0
        let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
        w.wind = "\(arrows[((degrees + 180) / 45) % 8]) \(text(current, "windspeedKmph")) km/h"

        // rain earns a row only with real signal: falling now, or likely today
        let precip = Double(text(current, "precipMM")) ?? 0
        let chance = ((today["hourly"] as? [[String: Any]]) ?? [])
            .compactMap { Int(($0["chanceofrain"] as? String) ?? "0") }.max() ?? 0
        if precip > 0 {
            w.rain = "☔ \(text(current, "precipMM"))mm now"
            if chance >= 30 { w.rain += " · rain \(chance)% today" }
        } else if chance >= 30 {
            w.rain = "☔ rain \(chance)% today"
        }

        if let astro = (today["astronomy"] as? [[String: Any]])?.first {
            w.sunrise = text(astro, "sunrise")
            w.sunset = text(astro, "sunset")
            w.moon = "\(moonEmoji(text(astro, "moon_phase"))) \(text(astro, "moon_phase").lowercased())"
        }

        if let area = (root["nearest_area"] as? [[String: Any]])?.first {
            // wttr repeats the city as its region ("Porto, Porto"), so the
            // region is dropped whenever either name contains the other
            let city = nested(area, "areaName")
            let region = nested(area, "region")
            let country = nested(area, "country")
            var parts = [city]
            if !region.isEmpty,
               !city.lowercased().contains(region.lowercased()),
               !region.lowercased().contains(city.lowercased()) {
                parts.append(region)
            }
            if !country.isEmpty { parts.append(country) }
            w.location = parts.joined(separator: ", ")
        }

        DispatchQueue.main.async {
            weather = w
            set("weather") { $0.icon = ""; $0.label = "\(w.emoji) \(w.temp)°C" }
            if openPopup == "weather" { refreshPopup() }
        }
    }.resume()
}

// --- popups ----------------------------------------------------------------
// A popup is a list of rows in its own window. sketchybar has to model
// these as bar items with a naming convention (`clock.cal.3`) that a
// separate shell guard greps to clean up; here they are just views that
// go away when the window closes, so there is no convention to break and
// nothing to leak.

struct PopupRow {
    var icon = ""
    var image: NSImage? // 16pt leading icon — Recent Items entries
    var text = ""
    var detail = "" // right-aligned, dim — menu shortcuts live here
    var subtitle = "" // follows the text, small and quiet: a title's second half
    var separator = false // a thin rule instead of content
    var hero = false // accent, bold — the title row
    var dim = false // the quiet action footer
    var highlight = false // today's week, the active device
    var slider: Double? // 0...1 draws a track instead of text
    var marker: Double? // 0...1 draws a tick across the slider track
    var inlineBar: Double? // 0...1 draws a track between the text and the detail
    var onSlide: ((Double) -> Void)?
    var action: (() -> Void)?
    // fixed-width cells, calendar only — the font isn't monospaced, so
    // space-padded text drifts out of the header's columns
    var columns: [String]? = nil
    var columnAccent: Int? // the cell that carries the today circle
    var tint: NSColor? // overrides the hero/dim colour for one row
    var barTint: NSColor? // colours the inline bar alone, leaving the label
    var iconTint: NSColor? // overrides the accent colour of the icon
    var section: String? // plugin rows: "open" or "closed" starts a section, "end" ends one
}

let rowHeight: CGFloat = 26
let popupPad: CGFloat = 8
// A long row ends in "…" rather than widen the popup past this.
let popupMaxWidth: CGFloat = 520
let popupRadius: CGFloat = 8
// How much of the theme background the popup lays over its glass. The
// glass adapts system colours to the window behind it, not theme colours,
// and its tint only shades it. With no fill, a bright window behind a dark
// theme's popup took the text to 2:1.
let popupGlassFill: CGFloat = 0.85

final class PopupView: NSView {
    var rows: [PopupRow] = []
    private var rowRects: [(Int, NSRect)] = []
    // the row under the pointer, actionable rows only — menus read as
    // menus when they answer the hover
    private var hoveredRow: Int?

    // NOT flipped: CTLineDraw draws in the CONTEXT's coordinates, so a
    // flipped view renders every glyph mirrored. NSString.draw hid that
    // difference, which is why this only broke when the text layer moved to
    // CoreText — the bar is unflipped and looked fine. Rows are laid out
    // downward explicitly instead of flipping the view.
    func font(_ row: PopupRow) -> NSFont {
        if row.hero { return nerdFont("Bold", 13) }
        if row.dim { return nerdFont("Regular", 12) }
        return nerdFont("Regular", 13)
    }

    func color(_ row: PopupRow) -> NSColor {
        if row.hero { return palette.accent }
        // the dim footer is the label colour at 60%, the same relationship
        // the shell popups build with a 0x99 alpha prefix
        if row.dim { return palette.label.withAlphaComponent(0.6) }
        return row.tint ?? palette.label
    }

    // separators are hairlines, not rows: a full 26 pt of blank per
    // rule made long menus read bulky instead of sectioned
    func rowH(_ row: PopupRow) -> CGFloat { row.separator ? 10 : rowHeight }

    // one width for every column cell in the popup, wide enough for the
    // widest cell at its own row's font — a header letter and a two-digit
    // day share a column even though they render at different sizes
    func columnWidth() -> CGFloat {
        var w: CGFloat = 0
        for row in rows {
            guard let cells = row.columns else { continue }
            let f = font(row)
            for cell in cells { w = max(w, advance(cell, f)) }
        }
        return w + 10
    }

    // the label and the numbers each side of every inline bar, measured
    // over the unfolded rows so a section opening moves no bar
    func barColumns() -> (label: CGFloat, detail: CGFloat) {
        let source = popupBarSource.isEmpty ? rows : popupBarSource
        let barred = source.filter { $0.inlineBar != nil }
        return (barred.map { advance($0.text, font($0)) }.max() ?? 0,
                barred.map { advance($0.detail, nerdFont("Regular", 11)) }.max() ?? 0)
    }

    func measure() -> NSSize {
        var width: CGFloat = 0
        var height: CGFloat = popupPad * 2
        let colW = columnWidth()
        let bars = barColumns()
        for row in rows {
            var w = advance(row.text, font(row))
            if !row.detail.isEmpty { w += advance(row.detail, nerdFont("Regular", 11)) + 24 }
            if !row.subtitle.isEmpty { w += advance(row.subtitle, nerdFont("Regular", 11)) + 8 }
            if !row.icon.isEmpty { w += inkBox(row.icon, nerdFont("Bold", 13)).width + 8 }
            if row.image != nil { w += 22 }
            if row.slider != nil { w = max(w, 150) }
            // the same three parts the row draws: label, a track of at
            // least 100pt, and the numbers
            if row.inlineBar != nil { w = max(w, bars.label + 12 + 100 + 12 + bars.detail) }
            if let cells = row.columns { w = max(w, CGFloat(cells.count) * colW) }
            width = max(width, w)
            height += rowH(row)
        }
        return NSSize(width: min(width + popupPad * 2 + 20, popupMaxWidth), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        rowRects.removeAll()
        // plain fill: the scroll CONTAINER carries the rounded clip and
        // border, so corners stay put while tall content scrolls
        palette.barBG.withAlphaComponent(popupGlass ? popupGlassFill : 1).setFill()
        bounds.fill()

        let colW = columnWidth()
        // inline bars share one column, so every bar starts and ends together
        let (barLabelW, barDetailW) = barColumns()
        var y = bounds.height - popupPad
        for (index, row) in rows.enumerated() {
            let h = rowH(row)
            y -= h
            let rect = NSRect(x: popupPad, y: y, width: bounds.width - popupPad * 2, height: h)
            if row.separator {
                palette.label.withAlphaComponent(0.15).setFill()
                NSRect(x: rect.minX + 2, y: rect.midY - 0.5, width: rect.width - 4, height: 1).fill()
                rowRects.append((index, rect))
                continue
            }
            if row.highlight || index == hoveredRow {
                palette.rowBG.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: 2), xRadius: 4, yRadius: 4).fill()
            }
            var x = rect.minX + 4
            if let image = row.image {
                image.draw(in: NSRect(x: x, y: rect.midY - 8, width: 16, height: 16))
                x += 22
            }
            if !row.icon.isEmpty {
                // same strategy as the bar: glyphs centre on ink, text on
                // cap height — one way of placing things in this file
                let iconFont = nerdFont("Bold", 13)
                let w = inkBox(row.icon, iconFont).width
                drawIcon(row.icon, iconFont, row.iconTint ?? palette.accent,
                         centeredIn: NSRect(x: x, y: rect.minY, width: w, height: rect.height))
                x += w + 8
            }
            if let cells = row.columns {
                // one box per cell, all the same width — centring absorbs the
                // per-glyph advance differences a proportional font gives
                // digits vs. letters, so every row lines up on the same grid.
                // A wide row elsewhere in the popup, such as an event title,
                // would leave the grid on the left of an empty half.
                let spread = max(colW, (rect.maxX - 20 - x) / CGFloat(cells.count))
                for (i, cell) in cells.enumerated() {
                    let box = NSRect(x: x, y: rect.minY, width: spread, height: rect.height)
                    if i == row.columnAccent {
                        let d = min(colW, rect.height) - 2
                        palette.accent.setFill()
                        NSBezierPath(ovalIn: NSRect(x: box.midX - d / 2, y: box.midY - d / 2,
                                                    width: d, height: d)).fill()
                        drawText(cell, font(row), palette.barBG, centeredIn: box)
                    } else {
                        drawText(cell, font(row), color(row), centeredIn: box)
                    }
                    x += spread
                }
            } else if let value = row.slider {
                // track, then filled portion — the readout is the row's text
                let trackW = rect.width - (x - rect.minX) - 52
                let track = NSRect(x: x, y: rect.midY - 3, width: trackW, height: 6)
                palette.rowBG.setFill()
                NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
                (row.tint ?? palette.accent).setFill()
                NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY,
                                                 width: track.width * CGFloat(value), height: track.height),
                             xRadius: 3, yRadius: 3).fill()
                if let marker = row.marker {
                    let tickX = track.minX + track.width * CGFloat(max(0, min(1, marker)))
                    palette.label.setFill()
                    NSBezierPath(roundedRect: NSRect(x: tickX - 1, y: track.midY - 6, width: 2, height: 12),
                                 xRadius: 1, yRadius: 1).fill()
                }
                drawText(row.text, font(row), color(row),
                         leftAt: rect.maxX - advance(row.text, font(row)) - 4, midY: rect.midY)
            } else {
                let tint = index == hoveredRow && row.action != nil ? palette.accent : color(row)
                var room = rect.maxX - 4 - x
                if !row.detail.isEmpty { room -= advance(row.detail, nerdFont("Regular", 11)) + 24 }
                if !row.subtitle.isEmpty { room -= advance(row.subtitle, nerdFont("Regular", 11)) + 8 }
                // a bar row's label has its own column, which measure() keeps
                let text = row.inlineBar == nil ? fit(row.text, font(row), room) : row.text
                drawText(text, font(row), tint, leftAt: x, midY: rect.midY)
                if !row.subtitle.isEmpty {
                    drawText(row.subtitle, nerdFont("Regular", 11),
                             palette.label.withAlphaComponent(0.5),
                             leftAt: x + advance(text, font(row)) + 8, midY: rect.midY)
                }
                if !row.detail.isEmpty {
                    let df = nerdFont("Regular", 11)
                    drawText(row.detail, df, palette.label.withAlphaComponent(0.5),
                             leftAt: rect.maxX - advance(row.detail, df) - 4, midY: rect.midY)
                }
                if let share = row.inlineBar {
                    let left = x + barLabelW + 12
                    let track = NSRect(x: left, y: rect.midY - 3,
                                       width: max(0, rect.maxX - 4 - barDetailW - 12 - left), height: 6)
                    palette.rowBG.setFill()
                    NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
                    (row.barTint ?? row.tint ?? palette.accent).setFill()
                    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY,
                                                     width: track.width * CGFloat(max(0, min(1, share))),
                                                     height: track.height),
                                 xRadius: 3, yRadius: 3).fill()
                    // the same pace tick the slider rows carry
                    if let marker = row.marker {
                        let tickX = track.minX + track.width * CGFloat(max(0, min(1, marker)))
                        palette.label.setFill()
                        NSBezierPath(roundedRect: NSRect(x: tickX - 1, y: track.midY - 5,
                                                         width: 2, height: 10),
                                     xRadius: 1, yRadius: 1).fill()
                    }
                }
            }
            rowRects.append((index, rect))
        }
    }


    // Tracking areas, not a poll and not a global monitor: a global
    // monitor stops delivering once this app is itself active, which is
    // exactly what clicking the bar makes it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = rowRects.first(where: { $0.1.contains(p) && rows[$0.0].action != nil })?.0
        if hit != hoveredRow { hoveredRow = hit; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredRow != nil { hoveredRow = nil; needsDisplay = true }
        scheduleHullCheck()
    }

    private func slide(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (index, rect) = rowRects.first(where: { $0.1.contains(p) }),
              rows[index].slider != nil, let onSlide = rows[index].onSlide else { return }
        let trackX = rect.minX + 4
        let trackW = rect.width - 4 - 52
        onSlide(min(1, max(0, (p.x - trackX) / trackW)))
    }

    override func mouseDown(with event: NSEvent) { slide(event) }
    override func mouseDragged(with event: NSEvent) { slide(event) }

    // true when the key belongs to the popup
    func key(_ code: Int) -> Bool {
        switch code {
        case 53: // Esc
            closePopup()
        case 125, 126: // ↓, ↑
            let clickable = rowRects.map(\.0).filter { rows[$0].action != nil && rows[$0].slider == nil }
            hoveredRow = nextSelection(clickable, from: hoveredRow, by: code == 125 ? 1 : -1)
            if let row = hoveredRow, let rect = rowRects.first(where: { $0.0 == row })?.1 {
                scrollToVisible(rect)
            }
            needsDisplay = true
        case 36, 76: // Return, Enter
            // with no row selected, Return still reaches the front app
            guard let row = hoveredRow, rows.indices.contains(row), let action = rows[row].action else { return false }
            action()
        default:
            return false
        }
        return true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (index, _) = rowRects.first(where: { $0.1.contains(p) }),
              rows[index].slider == nil, let action = rows[index].action else { return }
        action()
    }
}

final class PopupWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

var popupWindow: PopupWindow?
var popupView: PopupView?
var openPopup: String? // which bar item owns it

func closePopup() {
    if openPopup == "wifi" { stopHotspotBrowse() }
    setPopupKeys(false)
    popupWindow?.orderOut(nil)
    popupWindow = nil
    popupView = nil
    openPopup = nil
}

// rows are rebuilt, not patched: the content is cheap to regenerate and a
// stale row is worse than a redrawn one
// exact-fit on every refresh: grow-only left the app-menu popup huge
// after backing out of a long menu. The window is bottom-anchored, so
// the frame is recomputed to keep the TOP edge pinned under the bar.
var popupTopY: CGFloat = 0
var popupAnchorX: CGFloat = 0
var popupAlignLeft = false

func refreshPopup() {
    guard let name = openPopup, let view = popupView, let window = popupWindow else { return }
    view.rows = popupRows(for: name)
    let size = view.measure()
    let screen = window.screen ?? NSScreen.main
    var winH = size.height
    var x = popupAlignLeft ? popupAnchorX : popupAnchorX - size.width
    if let screen {
        winH = min(size.height, popupTopY - screen.frame.minY - 20)
        x = min(max(screen.frame.minX + 6, x), screen.frame.maxX - size.width - 6)
    }
    window.setFrame(NSRect(x: x, y: popupTopY - winH,
                           width: size.width, height: winH), display: false)
    let box = NSRect(origin: .zero, size: NSSize(width: size.width, height: winH))
    window.contentView?.frame = box
    (window.contentView as? NSGlassEffectView)?.contentView?.frame = box
    view.frame = NSRect(origin: .zero, size: size)
    view.scroll(NSPoint(x: 0, y: max(0, size.height - winH))) // drilling resets to the top
    view.needsDisplay = true
    view.display()
}

func showPopup(_ name: String, under anchor: NSRect, on surface: BarSurface, alignLeft: Bool = false) {
    if openPopup == name { closePopup(); return }
    closePopup()
    let rows = popupRows(for: name)
    guard !rows.isEmpty else { return }

    let view = PopupView(frame: .zero)
    view.rows = rows
    let size = view.measure()
    view.frame = NSRect(origin: .zero, size: size)

    // right-aligned under the item, clamped to the screen it opened on;
    // taller-than-screen content (Recent Items) scrolls inside a capped
    // window instead of running off the display
    let screen = surface.screen
    let barBottom = surface.window.frame.minY
    popupTopY = barBottom - 4
    popupAnchorX = alignLeft ? anchor.minX : anchor.maxX
    popupAlignLeft = alignLeft
    let winH = min(size.height, popupTopY - screen.frame.minY - 20)
    var x = alignLeft ? anchor.minX : anchor.maxX - size.width
    x = min(max(screen.frame.minX + 6, x), screen.frame.maxX - size.width - 6)
    let window = PopupWindow(contentRect: NSRect(x: x, y: popupTopY - winH,
                                                 width: size.width, height: winH),
                             styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.acceptsMouseMovedEvents = true
    let scroll = NSScrollView(frame: NSRect(origin: .zero, size: NSSize(width: size.width, height: winH)))
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    scroll.documentView = view
    scroll.wantsLayer = true
    scroll.layer?.cornerRadius = popupRadius
    scroll.layer?.masksToBounds = true
    scroll.layer?.borderWidth = 1
    scroll.layer?.borderColor = palette.accent.cgColor
    if popupGlass {
        let glass = NSGlassEffectView(frame: scroll.frame)
        glass.cornerRadius = popupRadius
        glass.tintColor = palette.barBG.withAlphaComponent(0.5)
        glass.contentView = scroll
        window.contentView = glass
    } else {
        window.contentView = scroll
    }
    view.scroll(NSPoint(x: 0, y: max(0, size.height - winH))) // start at the top
    window.alphaValue = 0
    window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = dur(0.12)
        window.animator().alphaValue = 1
    }
    popupWindow = window
    popupView = view
    openPopup = name
    setPopupKeys(true)
}

// ↑ and ↓ move through the rows of an open popup, Return clicks the row and
// Esc closes the popup. A tap takes these keys only while a popup is open,
// so the front app keeps its focus. A key with a modifier passes through.
var popupKeyTap: CFMachPort?

func setPopupKeys(_ on: Bool) {
    if on, popupKeyTap == nil {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = popupKeyTap, popupView != nil { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                guard modifiers.isEmpty, let view = popupView,
                      view.key(Int(event.getIntegerValueField(.keyboardEventKeycode))) else {
                    return Unmanaged.passUnretained(event)
                }
                return nil
            }, userInfo: nil)
        else {
            tlog("popup keys: no event tap, so no Accessibility grant")
            return
        }
        popupKeyTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }
    if let tap = popupKeyTap { CGEvent.tapEnable(tap: tap, enable: on) }
}

// The next row to select among the rows that take a click, wrapping at the ends.
func nextSelection(_ rows: [Int], from current: Int?, by delta: Int) -> Int? {
    guard !rows.isEmpty else { return nil }
    guard let current, let at = rows.firstIndex(of: current) else {
        return delta > 0 ? rows.first : rows.last
    }
    return rows[(at + delta + rows.count) % rows.count]
}

// --- popup content ---------------------------------------------------------

// --- calendar --------------------------------------------------------------
// Calendar takes a date through AppleScript, and a date STRING parses in
// the app's locale. A whole-day offset does not, and midday keeps the
// offset on the right day across a change of daylight saving.
// Whole days, counted on the calendar: a day that changes the clocks is
// 23 or 25 hours long, so seconds / 86400 lands a day short.
func dayOffset(from now: Date, to date: Date) -> Int {
    let cal = Calendar(identifier: .gregorian)
    return cal.dateComponents([.day], from: cal.startOfDay(for: now),
                              to: cal.startOfDay(for: date)).day ?? 0
}

func openCalendarWeek(of date: Date) {
    let days = dayOffset(from: Date(), to: date)
    let script = """
    tell application "Calendar"
        activate
        switch view to week view
        view calendar at ((current date) - (time of (current date)) + 12 * hours + \(days) * days)
    end tell
    """
    closePopup()
    DispatchQueue.global(qos: .userInitiated).async { _ = shell("/usr/bin/osascript", ["-e", script]) }
}

var eventStore: EKEventStore?
var todayEvents: [EKEvent] = []
var eventsDay: Date?
var eventsAt: TimeInterval = 0
var eventsLoading = false

// Never touch EventKit before the grant is there: a launchd agent would
// raise the dialog with nothing on screen to explain it. The fetch costs
// enough to keep off the main thread, and one answer serves for a minute.
func loadTodayEvents() {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, !eventsLoading else { return }
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    if eventsDay == start, Date.timeIntervalSinceReferenceDate - eventsAt < 60 { return }
    eventsLoading = true
    let store = eventStore ?? EKEventStore()
    eventStore = store
    DispatchQueue.global(qos: .userInitiated).async {
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                    calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        DispatchQueue.main.async {
            todayEvents = found
            eventsDay = start
            eventsAt = Date.timeIntervalSinceReferenceDate
            eventsLoading = false
            updateClock()
            if openPopup == "clock" { refreshPopup() }
        }
    }
}

// How long you have, on the next event only: the clock time is already
// in the row, and a count on every row reads as noise.
func countdown(to event: EKEvent, now: Date) -> String {
    if event.isAllDay { return "" }
    let left = event.startDate.timeIntervalSince(now)
    if left <= 0 { return "now" }
    if left < 3600 { return "in \(Int(left / 60)) min" }
    if left < 12 * 3600 { return "in \(Int(left / 3600)) h" }
    return ""
}

func eventRows() -> [PopupRow] {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        return [PopupRow(separator: true),
                PopupRow(text: "see today's events…", dim: true, action: {
                    NSWorkspace.shared.open(URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    closePopup()
                })]
    }
    loadTodayEvents()
    let now = Date()
    let left = todayEvents.filter { $0.endDate > now }
    guard !left.isEmpty else {
        return [PopupRow(separator: true), PopupRow(text: "nothing left today", dim: true)]
    }
    let time = DateFormatter()
    time.dateFormat = "HH:mm"
    var rows = [PopupRow(separator: true), PopupRow(text: "today", dim: true)]
    // a long title would widen the whole popup: measure() takes the
    // widest row, and the month grid below it holds the useful width
    for (index, event) in left.prefix(6).enumerated() {
        let title = event.title ?? "event"
        let cut = title.count > 20 ? String(title.prefix(19)) + "…" : title
        rows.append(PopupRow(icon: "\u{F111}",
                             text: event.isAllDay ? cut : time.string(from: event.startDate) + "  " + cut,
                             detail: event.isAllDay ? "all day" : countdown(to: event, now: now),
                             highlight: index == 0,
                             action: calendarLink(id: event.calendarItemIdentifier, start: event.startDate,
                                                  repeats: event.hasRecurrenceRules)
                                 .map { link in { closePopup(); NSWorkspace.shared.open(link) } },
                             iconTint: event.calendar.cgColor.flatMap { NSColor(cgColor: $0) }))
    }
    return rows
}

func calendarRows() -> [PopupRow] { monthRows(Date()) + eventRows() }

func monthRows(_ now: Date) -> [PopupRow] {
    var rows: [PopupRow] = []
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // Monday, like the shell version
    let title = DateFormatter()
    title.dateFormat = "MMMM yyyy"
    rows.append(PopupRow(text: title.string(from: now).lowercased(),
                         detail: "week \(cal.component(.weekOfYear, from: now))", hero: true))
    rows.append(PopupRow(dim: true, columns: ["mo", "tu", "we", "th", "fr", "sa", "su"]))

    guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
          let range = cal.range(of: .day, in: .month, for: now) else { return rows }
    let today = cal.component(.day, from: now)
    // weekday index with Monday = 0
    let leading = (cal.component(.weekday, from: monthStart) + 5) % 7
    let prevDays = cal.range(of: .day, in: .month,
                             for: cal.date(byAdding: .month, value: -1, to: monthStart)!)!.count

    var cells: [(Int, Bool)] = [] // day, in-month
    for i in 0..<leading { cells.append((prevDays - leading + 1 + i, false)) }
    for d in range { cells.append((d, true)) }
    var next = 1
    while cells.count % 7 != 0 { cells.append((next, false)); next += 1 }

    for week in stride(from: 0, to: cells.count, by: 7) {
        let slice = cells[week..<min(week + 7, cells.count)]
        let monday = cal.date(byAdding: .day, value: week - leading, to: monthStart) ?? monthStart
        rows.append(PopupRow(action: { openCalendarWeek(of: monday) },
                             columns: slice.map { $0.1 ? String($0.0) : "" },
                             columnAccent: slice.firstIndex { $0.0 == today && $0.1 }
                                 .map { $0 - slice.startIndex }))
    }
    return rows
}

func brightnessRows() -> [PopupRow] {
    var value: Float = 0
    guard DSGetBrightness(builtinDisplayID(), &value) == 0 else { return [] }
    var rows = [
        PopupRow(icon: "󰃟", text: "\(Int((value * 100).rounded()))%",
                 slider: Double(value),
                 onSlide: { fraction in
                     _ = DSSetBrightness(builtinDisplayID(), Float(fraction))
                     updateBrightness()
                 }),
        PopupRow(icon: "\u{F0594}", text: "\(Int((shade * 100).rounded()))%",
                 slider: shade,
                 onSlide: { setShade($0) }),
    ]
    // read in process, every time the rows are built: the row says what
    // CoreBrightness says now, and a Mac without night shift gets no row
    // rather than a lying one
    if let ns = blueLightStatus(), ns.available.boolValue {
        let on = ns.enabled.boolValue
        rows.append(PopupRow(text: "night shift \(on ? "on" : "off")", action: {
            setNightShift(!on)
            refreshPopup()
        }))
    }
    rows.append(PopupRow(text: "display settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
        closePopup()
    }))
    return rows
}

func volumeRows() -> [PopupRow] {
    guard let v = readVolume() else { return [] }
    var rows: [PopupRow] = [
        PopupRow(icon: v.muted ? "󰝟" : "󰕾", text: v.muted ? "mute" : "\(v.percent)%",
                 slider: Double(v.percent) / 100,
                 onSlide: { fraction in
                     writeVolume(Int((fraction * 100).rounded()))
                     updateVolume()
                 }),
    ]
    // output devices, current one marked — the same list `omacchiato-helper
    // audio` offers, read here without the round trip
    let current = defaultOutputDevice()
    for device in audioOutputDevices() {
        rows.append(PopupRow(icon: device.id == current ? "󰄬" : " ", text: device.name,
                             highlight: device.id == current,
                             action: {
                                 setDefaultOutputDevice(device.id)
                                 updateVolume()
                                 refreshPopup()
                             }))
    }
    rows.append(PopupRow(text: "sound settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        closePopup()
    }))
    return rows
}

// SCDynamicStore answers both in process. The popup used to fork
// ipconfig on the click path just for the address — and the router,
// the one number you actually want when the network misbehaves, was
// never shown at all.
func wifiIPv4() -> (ip: String, router: String) {
    guard let store = SCDynamicStoreCreate(nil, "omacchiato-bar-ipv4" as CFString, nil, nil)
    else { return ("", "") }
    let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
        as? [String: Any]
    let iface = SCDynamicStoreCopyValue(store,
        "State:/Network/Interface/\(wifiDevice)/IPv4" as CFString) as? [String: Any]
    return ((iface?["Addresses"] as? [String])?.first ?? "",
            global?["Router"] as? String ?? "")
}

// Name only what is certain — the generic personal/enterprise cases
// cover several generations and guessing one would be a lie.
func securityName(_ s: CWSecurity) -> String? {
    switch s {
    case .none: return "open"
    case .WEP, .dynamicWEP: return "WEP"
    case .wpaPersonal, .wpaPersonalMixed, .wpaEnterprise, .wpaEnterpriseMixed: return "WPA"
    case .wpa2Personal, .wpa2Enterprise: return "WPA2"
    case .wpa3Personal, .wpa3Enterprise, .wpa3Transition: return "WPA3"
    case .OWE, .oweTransition: return "OWE"
    default: return nil
    }
}

func batteryRows() -> [PopupRow] {
    var rows: [PopupRow] = []
    let raw = smartBattery()
    let data = raw["BatteryData"] as? [String: Any] ?? [:]

    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
       let source = list.first,
       let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] {
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
        let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        // this key arrives as a number, not a boolean, so a Bool cast alone
        // reads every charging battery as charged
        let charging = (d[kIOPSIsChargingKey] as? Bool)
            ?? ((d[kIOPSIsChargingKey] as? Int) == 1)
        rows.append(PopupRow(text: "battery", detail: "\(pct)%", hero: true,
                             inlineBar: Double(pct) / 100,
                             tint: pct <= 20 && !onAC ? .systemRed : nil))
        // 65535 is the "not known yet" answer, which arrives whenever the
        // rate has just changed
        let minutes = onAC ? (d[kIOPSTimeToFullChargeKey] as? Int ?? -1)
                           : (d[kIOPSTimeToEmptyKey] as? Int ?? -1)
        let left = minutes > 0 && minutes < 65535
            ? "\(minutes / 60)h \(minutes % 60)m " + (onAC ? "to full" : "left") : ""
        rows.append(PopupRow(text: charging ? "charging"
                                            : (onAC ? "charged, on AC" : "on battery"),
                             detail: left))
    }

    rows.append(PopupRow(separator: true))
    applyHighPowerMode(readHighPowerMode())
    if let mode = powerModeName() {
        rows.append(PopupRow(text: "mode", detail: mode))
    }
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: break // the ordinary state is not worth a row
    case .fair: rows.append(PopupRow(text: "thermal", detail: "fair"))
    case .serious: rows.append(PopupRow(text: "thermal", detail: "serious"))
    case .critical: rows.append(PopupRow(text: "thermal", detail: "critical"))
    @unknown default: break
    }
    // amperage is negative while discharging: the sign is the direction,
    // and the pill only wants the size
    if let mv = raw["Voltage"] as? Int, let ma = raw["Amperage"] as? Int, ma != 0 {
        let watts = Double(mv) * Double(abs(ma)) / 1_000_000
        rows.append(PopupRow(text: ma < 0 ? "draw" : "charging at",
                             detail: String(format: "%.1f W", watts)))
    }
    if let adapter = raw["AdapterDetails"] as? [String: Any],
       let watts = adapter["Watts"] as? Int {
        rows.append(PopupRow(text: "adapter", detail: "\(watts) W"))
    }

    rows.append(PopupRow(separator: true))
    if let design = data["DesignCapacity"] as? Int,
       let full = data["FullChargeCapacity"] as? Int, design > 0 {
        // Apple rounds this to a whole 100% for a long while; the ratio is
        // the number that actually moves
        let health = Int((Double(full) / Double(design) * 100).rounded())
        let verdict = health >= 90 ? "" : (health >= 80 ? "  fair" : "  worn")
        rows.append(PopupRow(text: "health", detail: "\(health)%\(verdict)"))
    }
    if let cycles = raw["CycleCount"] as? Int {
        rows.append(PopupRow(text: "cycles", detail: "\(cycles)"))
    }

    rows.append(PopupRow(separator: true))
    rows.append(PopupRow(text: "Battery Settings…", dim: true, action: {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        closePopup()
    }))
    return rows
}

// --- personal hotspot ------------------------------------------------------
// The phone list in the macOS wi-fi menu does not come from CoreWLAN:
// airportd gates its tether calls behind entitlements that only Apple's
// own wi-fi agent carries. sharingd answers the same question over XPC,
// and it asks for no grant at all. Private API, so every step gives up
// quietly: a macOS that renames the class leaves the popup as it was.
final class HotspotWatcher: NSObject {
    @objc func session(_ session: AnyObject, updatedFoundDevices devices: [AnyObject]) {
        DispatchQueue.main.async {
            hotspotDevices = devices.compactMap { $0 as? NSObject }
            if openPopup == "wifi" { refreshPopup() }
        }
    }
}

let hotspotWatcher = HotspotWatcher()
var hotspotSession: NSObject?
var hotspotDevices: [NSObject] = []

func startHotspotBrowse() {
    if hotspotSession == nil {
        guard dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY) != nil,
              let type = NSClassFromString("SFRemoteHotspotSession") as? NSObject.Type else {
            tlog("hotspot: no SFRemoteHotspotSession")
            return
        }
        let session = type.init()
        session.perform(NSSelectorFromString("setDelegate:"), with: hotspotWatcher)
        hotspotSession = session
    }
    hotspotSession?.perform(NSSelectorFromString("startBrowsing"))
}

func stopHotspotBrowse() {
    hotspotSession?.perform(NSSelectorFromString("stopBrowsing"))
}

// The phone turns its hotspot on and answers with the name and the
// password of the network it raised. Joining it is still this Mac's
// job. The two arguments are plain strings, whatever the type encoding
// of the block says, so nothing here sends them a message.
func startHotspot(_ device: NSObject) {
    let name = device.value(forKey: "deviceName") as? String ?? "phone"
    typealias Done = @convention(block) (AnyObject?, AnyObject?) -> Void
    let done: Done = { first, second in
        let ssid = first as? String ?? ""
        let secret = second as? String ?? ""
        tlog("hotspot \(name): ssid \(ssid.isEmpty ? "none" : ssid), password \(secret.isEmpty ? "no" : "yes")")
        guard !ssid.isEmpty else { return }
        // the network takes a few seconds to come up after the phone agrees
        DispatchQueue.global(qos: .userInitiated).async {
            for attempt in 1...6 {
                let out = shell("/usr/sbin/networksetup",
                                ["-setairportnetwork", wifiDevice, ssid]
                                    + (secret.isEmpty ? [] : [secret]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if out.isEmpty {
                    tlog("hotspot \(name): joined \(ssid)")
                    return
                }
                tlog("hotspot \(name): join \(attempt) \(out)")
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }
    closePopup()
    hotspotSession?.perform(NSSelectorFromString("enableHotspotForDevice:withCompletionHandler:"),
                            with: device, with: unsafeBitCast(done, to: AnyObject.self))
}

// --- wifi networks in range ------------------------------------------------
// A scan blocks for seconds, so it runs off the main thread and the
// popup redraws when the answer lands. macOS also throttles scans, and
// the popup opens often, so one answer serves for 20 s.
var wifiNetworks: [CWNetwork] = []
var wifiScanAt: TimeInterval = 0
var wifiScanning = false

func scanWifi() {
    guard !wifiScanning, Date.timeIntervalSinceReferenceDate - wifiScanAt > 20,
          let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return }
    wifiScanning = true
    DispatchQueue.global(qos: .userInitiated).async {
        let found = (try? interface.scanForNetworks(withSSID: nil)) ?? []
        // one row per name: a network on two radios answers twice
        var best: [String: CWNetwork] = [:]
        for network in found {
            guard let ssid = network.ssid, !ssid.isEmpty else { continue }
            if let seen = best[ssid], seen.rssiValue >= network.rssiValue { continue }
            best[ssid] = network
        }
        let list = best.values.sorted { $0.rssiValue > $1.rssiValue }
        DispatchQueue.main.async {
            wifiNetworks = list
            wifiScanAt = Date.timeIntervalSinceReferenceDate
            wifiScanning = false
            if openPopup == "wifi" { refreshPopup() }
        }
    }
}

func wifiStrengthGlyph(_ rssi: Int) -> String {
    if rssi >= -60 { return "\u{F0928}" }
    if rssi >= -70 { return "\u{F0925}" }
    if rssi >= -80 { return "\u{F0922}" }
    return "\u{F091F}"
}

// networksetup takes the password from the system keychain, so a network
// this Mac knows joins in one click. It prints a line for every other
// case, and macOS asks for the password better than a popup row can.
func joinWifi(_ ssid: String) {
    closePopup()
    DispatchQueue.global(qos: .userInitiated).async {
        let out = shell("/usr/sbin/networksetup", ["-setairportnetwork", wifiDevice, ssid])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        tlog("wifi join \(ssid): \(out.isEmpty ? "joined" : out)")
        guard !out.isEmpty else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        }
    }
}

func wifiRows() -> [PopupRow] {
    let interface = CWWiFiClient.shared().interface()
    var rows: [PopupRow] = [
        // the SSID is location-sensitive data: it needs the Location
        // grant AND a bundled binary (measured on macOS 26.3 — an
        // unbundled build reads nil however it is authorised), which
        // is why the bar ships inside a .app. See install.sh.
        PopupRow(text: interface?.ssid() ?? "wi-fi", hero: true),
    ]
    let net = wifiIPv4()
    rows.append(PopupRow(text: "ip \(net.ip.ifEmpty("none"))"))
    if !net.router.isEmpty { rows.append(PopupRow(text: "router \(net.router)")) }
    if let rssi = interface?.rssiValue(), rssi != 0 {
        let verdict = rssi >= -55 ? "excellent" : (rssi >= -67 ? "good" : (rssi >= -75 ? "fair" : "weak"))
        rows.append(PopupRow(text: "signal \(rssi) dBm  \(verdict)"))
    }
    // how fast, and how safe — the two questions the old rows left open
    var link: [String] = []
    if let rate = interface?.transmitRate(), rate > 0 { link.append("\(Int(rate)) Mbps") }
    if let sec = interface?.security(), let name = securityName(sec) { link.append(name) }
    if !link.isEmpty { rows.append(PopupRow(text: "link " + link.joined(separator: "  "))) }
    if let channel = interface?.wlanChannel() {
        // a bare channel number means nothing to most people; the band
        // is what says "you are on the fast radio"
        var parts = ["channel \(channel.channelNumber)"]
        switch channel.channelBand {
        case .band2GHz: parts.append("2.4 GHz")
        case .band5GHz: parts.append("5 GHz")
        case .band6GHz: parts.append("6 GHz")
        default: break
        }
        switch channel.channelWidth {
        case .width20MHz: parts.append("20 MHz")
        case .width40MHz: parts.append("40 MHz")
        case .width80MHz: parts.append("80 MHz")
        case .width160MHz: parts.append("160 MHz")
        default: break
        }
        rows.append(PopupRow(text: parts.joined(separator: "  ")))
    }
    scanWifi()
    let current = interface?.ssid()
    let others = wifiNetworks.filter { $0.ssid != current }.prefix(6)
    rows.append(PopupRow(separator: true))
    rows.append(PopupRow(text: "networks", dim: true))
    // the one you are on leads the list with a tick, the way the macOS
    // menu marks it. A lock on every row says nothing, so only the rare
    // open network carries a word.
    if let current, !current.isEmpty {
        rows.append(PopupRow(icon: "\u{F012C}", text: current, highlight: true,
                             iconTint: palette.accent))
    }
    for network in others {
        guard let ssid = network.ssid else { continue }
        rows.append(PopupRow(icon: wifiStrengthGlyph(network.rssiValue), text: ssid,
                             detail: network.supportsSecurity(.none) ? "open" : "",
                             action: { joinWifi(ssid) }))
    }
    if others.isEmpty, wifiScanning {
        rows.append(PopupRow(text: "looking…", dim: true))
    }
    startHotspotBrowse()
    if !hotspotDevices.isEmpty {
        rows.append(PopupRow(separator: true))
        rows.append(PopupRow(text: "phones", dim: true))
        for device in hotspotDevices {
            let name = device.value(forKey: "deviceName") as? String ?? "phone"
            let battery = device.value(forKey: "batteryLife") as? Double
            // an iPhone hotspot takes the name of the phone
            let sharing = name == current
            rows.append(PopupRow(icon: "\u{F011C}", text: name,
                                 detail: sharing ? "connected" : battery.map { "\(Int($0))%" } ?? "",
                                 highlight: sharing,
                                 action: sharing ? nil : { startHotspot(device) }))
        }
    }
    rows.append(PopupRow(text: "network settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        closePopup()
    }))
    return rows
}

func bluetoothRows() -> [PopupRow] {
    var rows: [PopupRow] = [PopupRow(text: "bluetooth", hero: true)]
    guard CBCentralManager.authorization == .allowedAlways else {
        rows.append(PopupRow(text: "no permission in this launch context", dim: true))
        return rows
    }
    for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
        let name = device.name ?? device.addressString ?? "device"
        rows.append(PopupRow(icon: device.isConnected() ? "󰂱" : "󰂯", text: name,
                             highlight: device.isConnected(),
                             action: {
                                 // with a target, the connect runs async: a device out of range blocks for seconds
                                 if device.isConnected() { device.closeConnection() } else { device.openConnection(bluetoothWatcher) }
                                 updateBluetooth()
                                 refreshPopup()
                             }))
    }
    rows.append(PopupRow(text: "bluetooth settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        closePopup()
    }))
    return rows
}

func weatherRows() -> [PopupRow] {
    guard let w = weather else { return [] }
    var rows: [PopupRow] = [PopupRow(text: "\(w.emoji) \(w.temp)°C \(w.desc)", hero: true)]

    // feels-like earns a mention only when it differs from the real temp
    var today = "today \(w.low)° → \(w.high)°C"
    if w.feels != w.temp { today = "feels \(w.feels)°C · " + today }
    rows.append(PopupRow(text: today))
    rows.append(PopupRow(text: "wind \(w.wind) · humidity \(w.humidity)%"))
    if !w.rain.isEmpty { rows.append(PopupRow(text: w.rain)) }
    if !w.sunrise.isEmpty {
        rows.append(PopupRow(text: "sun \(w.sunrise) → \(w.sunset) · \(w.moon)"))
    }
    if !w.location.isEmpty { rows.append(PopupRow(text: w.location, dim: true)) }
    return rows
}

// The system menu the hidden native menu bar used to carry, plus the two
// omacchiato actions. "Reload Bar" has no counterpart here on purpose: there
// is no config to re-read, the theme is watched, and a row that did
// nothing would be worse than a row that is absent.
func appleRows() -> [PopupRow] {
    func settings(_ pane: String) -> () -> Void {
        { NSWorkspace.shared.open(URL(string: pane)!); closePopup() }
    }
    func run(_ launch: String, _ args: [String]) -> () -> Void {
        {
            closePopup()
            DispatchQueue.global(qos: .userInitiated).async { _ = shell(launch, args) }
        }
    }
    func systemEvents(_ verb: String) -> () -> Void {
        run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to \(verb)"])
    }
    return [
        PopupRow(text: "About This Mac", hero: true,
                 action: settings("x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension")),
        PopupRow(text: "System Settings…", action: run("/usr/bin/open", ["-a", "System Settings"])),
        // pmset displaysleepnow only darkens the panel — whether that
        // locks depends on the screenLock delay, so it usually did not
        PopupRow(text: "Lock Screen",
                 action: run("\(NSHomeDirectory())/.local/bin/omacchiato-helper", ["lock"])),
        PopupRow(text: "Sleep", action: run("/usr/bin/pmset", ["sleepnow"])),
        PopupRow(text: "Restart…", action: systemEvents("restart")),
        PopupRow(text: "Shut Down…", action: systemEvents("shut down")),
        PopupRow(text: "theme", detail: currentThemeName(), dim: true,
                 action: run("\(NSHomeDirectory())/.local/bin/theme-next", [])),
    ]
}

func popupRows(for name: String) -> [PopupRow] {
    popupBarSource = []
    switch name {
    case "apple": return appleMenuRows()
    case "clock": return calendarRows()
    case "battery": return batteryRows()
    case "weather": return weatherRows()
    case "brightness": return brightnessRows()
    case "volume": return volumeRows()
    case "wifi": return wifiRows()
    case "bluetooth": return bluetoothRows()
    case "appmenu": return appMenuRows()
    case "menubar": return menuBarAppRows()
    default:
        popupBarSource = pluginRows[name] ?? []
        return foldSections(name, popupBarSource)
    }
}

// The focused app's menu bar, read over Accessibility and rendered
// INSIDE our popup: top level lists File/Edit/…, clicking drills into
// that menu's actual items, and clicking a leaf performs its AXPress —
// the command runs with no native menu ever appearing. A navigation
// stack lives for the popup's lifetime; "‹" walks back up.
var appMenuStack: [(title: String, element: AXUIElement)] = []

// --- menu bar apps -------------------------------------------------------
// Third-party menu bar icons, read from each app's AXExtrasMenuBar. OmniWM's
// MenuBarExtrasScanner reads the same attribute on macOS 27.
struct MenuBarItem {
    let app: NSRunningApplication
    let element: AXUIElement
    let label: String
    let parked: Bool // the notch hides it: macOS parks such an icon at x = -1
}

// Call off the main thread: each app costs an Accessibility round trip.
// A hung app answers no AX call. The default wait is 6 s per call, and the
// app menu reads the front app on the main thread.
let axTimeout: Float = 0.25

func menuBarItems() -> [MenuBarItem] {
    let own = ProcessInfo.processInfo.processIdentifier
    var items: [MenuBarItem] = []
    for app in NSWorkspace.shared.runningApplications {
        guard app.processIdentifier != own,
              let id = app.bundleIdentifier, !id.hasPrefix("com.apple.") else { continue }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, axTimeout)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &ref) == .success,
              let extras = ref, CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
        for element in axChildren(extras as! AXUIElement) {
            let title = axString(element, "AXTitle")
            items.append(MenuBarItem(app: app, element: element,
                                     label: title.isEmpty ? axString(element, "AXDescription") : title,
                                     parked: (axFrame(element)?.minX ?? -1) < 0))
        }
    }
    return items
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    var pos: CFTypeRef?, size: CFTypeRef?
    var origin = CGPoint.zero, extent = CGSize.zero
    // the cast to AXValue is unchecked, so check the type ID before it
    guard AXUIElementCopyAttributeValue(element, "AXPosition" as CFString, &pos) == .success,
          AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &size) == .success,
          let pos, let size,
          CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
          AXValueGetValue(pos as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
    return CGRect(origin: origin, size: extent)
}

// True when a menu bar point is on a display's top strip and not behind the
// notch. The notch hides icons that do not fit, and a click there hits
// nothing.
func menuBarPointIsClickable(_ point: CGPoint) -> Bool {
    for screen in NSScreen.screens {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
        let bounds = CGDisplayBounds(id) // global, top-left origin, like AX
        guard bounds.contains(point), point.y - bounds.minY < 60 else { continue }
        let left = screen.auxiliaryTopLeftArea, right = screen.auxiliaryTopRightArea
        if left == nil && right == nil { return true } // no notch
        let x = point.x - bounds.minX + screen.frame.minX
        return [left, right].compactMap { $0 }.contains { x >= $0.minX && x <= $0.maxX }
    }
    return false
}

// macOS parks the hidden menu bar window just above its display (y = -39 on
// the main one) and slides it down to show it. True once it is fully in place
// over the given x.
func menuBarIsShown(overX x: CGFloat) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    for w in list where (w[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)) {
        guard let bounds = w[kCGWindowBounds as String],
              let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
              frame.minX <= x, x < frame.maxX else { continue }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: x, y: frame.maxY - 1), 1, &display, &count)
        if count > 0, abs(frame.minY - CGDisplayBounds(display).minY) < 1 { return true }
    }
    return false
}

// A real click on a menu bar icon, as OmniWM's HiddenBarClickForwarder clicks
// one. The pointer first moves to the top edge above the icon so the hidden
// menu bar slides in, then it clicks the icon's centre and moves back.
// Returns false, and clicks nothing, when the icon has no clickable position.
// Call off the main thread: it waits for the menu bar to appear.
func clickMenuBarItem(_ item: MenuBarItem) -> Bool {
    guard let before = axFrame(item.element),
          let source = CGEventSource(stateID: .hidSystemState),
          let start = CGEvent(source: nil)?.location else { return false }
    func post(_ type: CGEventType, _ at: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: .left)
        if type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        event?.post(tap: .cghidEventTap)
    }
    defer { CGWarpMouseCursorPosition(start) }
    let t0 = DispatchTime.now().uptimeNanoseconds
    post(.mouseMoved, CGPoint(x: before.midX, y: 0))
    let deadline = t0 + 600_000_000
    while !menuBarIsShown(overX: before.midX), DispatchTime.now().uptimeNanoseconds < deadline {
        usleep(15_000)
    }
    tlog(String(format: "menubar click %@: menu bar ready after %.0f ms", item.app.localizedName ?? "?",
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
    guard let frame = axFrame(item.element) else { return false }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    guard menuBarPointIsClickable(point) else { return false }
    post(.mouseMoved, point)
    usleep(10_000)
    post(.leftMouseDown, point)
    post(.leftMouseUp, point)
    usleep(50_000)
    return true
}

// The popup shows the last scan at once, and a new scan refreshes it.
var menuBarCache: [MenuBarItem]?
var menuBarScanning = false
var menuBarScannedAt = Date.distantPast

// The first line of an icon's label, without the app's name in front:
// "OneDrive — TinaCMS" becomes "TinaCMS".
func menuBarLabel(_ raw: String, app: String) -> String {
    var label = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    for sep in [" — ", " - ", ": "] where label.hasPrefix(app + sep) {
        label = String(label.dropFirst(app.count + sep.count))
    }
    return label.trimmingCharacters(in: .whitespaces)
}

// macOS's "Move focus to status menus" shortcut, Ctrl+F8: it shows the
// hidden menu bar with keyboard focus on its icons.
func showMenuBar() {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let key = CGEvent(keyboardEventSource: source, virtualKey: 100, keyDown: down)
        key?.flags = [.maskControl, .maskSecondaryFn] // a function key carries Fn
        key?.post(tap: .cghidEventTap)
    }
}

func menuBarAppRows() -> [PopupRow] {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else {
        return [PopupRow(text: "grant Accessibility to omacchiato-bar", hero: true),
                PopupRow(text: "System Settings opened the pane — toggle the bar on,", dim: true),
                PopupRow(text: "then click the pill again", dim: true)]
    }
    // refreshPopup() calls back in here, so a finished scan must not start another
    if !menuBarScanning, Date().timeIntervalSince(menuBarScannedAt) > 2 {
        menuBarScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let items = menuBarItems()
            DispatchQueue.main.async {
                let keys = { (list: [MenuBarItem]) in list.map { "\($0.app.processIdentifier)|\($0.label)" } }
                let changed = menuBarCache.map(keys) != keys(items)
                menuBarCache = items
                menuBarScanning = false
                menuBarScannedAt = Date()
                if changed, openPopup == "menubar" { refreshPopup() }
            }
        }
    }
    var rows: [PopupRow] = []
    if let items = menuBarCache {
        let appName = { (item: MenuBarItem) in
            item.app.localizedName ?? item.app.bundleIdentifier ?? "?"
        }
        for (index, text) in menuBarTitles(items.map { (appName($0), $0.label) }) {
            let item = items[index]
            let name = appName(item)
            rows.append(PopupRow(image: item.app.icon, text: text, detail: item.parked ? "opens app" : "", action: {
                closePopup()
                // A real click, as a hand gives one: AXPress on an icon behind
                // the notch leaves the menu bar stuck on screen until that app
                // quits. An icon with nowhere to click opens its app instead.
                DispatchQueue.global(qos: .userInitiated).async {
                    guard item.parked || !clickMenuBarItem(item) else { return }
                    tlog("menubar: \(name) has no clickable icon, opening the app")
                    DispatchQueue.main.async {
                        guard let url = item.app.bundleURL else { return }
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }))
        }
        if items.isEmpty { rows.append(PopupRow(text: "No menu bar apps running", dim: true)) }
    } else {
        rows.append(PopupRow(text: "Looking…", dim: true))
    }
    rows.append(PopupRow(separator: true))
    rows.append(PopupRow(text: "Show menu bar", detail: "⌃F8", dim: true, action: {
        closePopup()
        showMenuBar()
    }))
    return rows
}

// By name, not by process: an app can run two of them, and two rows of
// one name still choose nothing. The scan follows launch order, so the
// rows moved between openings. Sort by name, and keep one app's own icons
// in the order the menu bar holds them. Alone, most labels are empty or a
// symbol name, so a label only tells two icons of one app apart. Some
// apps label neither, and those get a number.
func menuBarTitles(_ entries: [(name: String, label: String)]) -> [(index: Int, text: String)] {
    let perApp = Dictionary(grouping: entries, by: \.name).mapValues(\.count)
    var nth: [String: Int] = [:]
    return entries.enumerated().sorted { a, b in
        let order = a.element.name.localizedCaseInsensitiveCompare(b.element.name)
        return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
    }.map { index, entry in
        guard perApp[entry.name, default: 0] > 1 else { return (index, entry.name) }
        nth[entry.name, default: 0] += 1
        let label = menuBarLabel(entry.label, app: entry.name)
        return (index, entry.name + (label.isEmpty ? " \(nth[entry.name]!)" : " · " + label))
    }
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &ref) == .success,
          let children = ref as? [AXUIElement] else { return [] }
    // A timeout holds for one element only, so each child needs its own.
    for child in children { AXUIElementSetMessagingTimeout(child, axTimeout) }
    return children
}

private func axString(_ element: AXUIElement, _ attr: String) -> String {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return "" }
    return ref as? String ?? ""
}

private func axInt(_ element: AXUIElement, _ attr: String) -> Int {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return 0 }
    return (ref as? NSNumber)?.intValue ?? 0
}

// AXMenuItemCmdModifiers is a mask, and bit 3 means the shortcut carries
// NO command key. Without it, Lock Screen and Log Out both read ⌘Q.
func menuShortcut(_ item: AXUIElement) -> String {
    shortcutText(axString(item, "AXMenuItemCmdChar"), axInt(item, "AXMenuItemCmdModifiers"))
}

func shortcutText(_ key: String, _ mods: Int) -> String {
    guard !key.isEmpty else { return "" }
    var out = ""
    if mods & 4 != 0 { out += "⌃" }
    if mods & 2 != 0 { out += "⌥" }
    if mods & 1 != 0 { out += "⇧" }
    if mods & 8 == 0 { out += "⌘" }
    return out + key
}

// one menu's items as popup rows — shared by the app drill-down and the
// apple pill. A menu bar item wraps one AXMenu; the items live inside.
// AXEnabled is a lie for closed menus: apps validate items lazily when
// a menu OPENS, so unopened menus read mostly disabled (Arc's whole
// Tabs menu greyed out). Render all leaves live; a truly disabled
// item's AXPress just no-ops.
// Recent Items: AX exposes no menu-item images, but its entries are
// apps and documents whose icons Launch Services can resolve by name —
// the section headers ("Applications"/"Documents"/"Servers") say which
// strategy applies. Headers render dim, entries get real icons.
func recentItemIcon(_ title: String, section: String) -> NSImage? {
    if section == "Applications" {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == title }),
           let icon = app.icon { return icon }
        // no current API finds an app by name, so look in the usual folders
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        if let path = dirs.map({ "\($0)/\(title).app" }).first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
    if section == "Documents" {
        let ext = (title as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
    return nil
}

func rowsForMenu(_ element: AXUIElement, context: String = "",
                 collapseAlternates: Bool = false) -> [PopupRow] {
    let container = axChildren(element).first ?? element
    var rows: [PopupRow] = []
    var section = ""
    var prevTitle = ""
    let recents = context == "Recent Items"
    for item in axChildren(container) {
        let title = axString(item, "AXTitle")
        if title.isEmpty {
            if rows.last?.separator != true { rows.append(PopupRow(separator: true)) }
            prevTitle = ""
            continue
        }
        // the Apple menu carries hold-Option ALTERNATES ("Restart…" then
        // "Restart", "Force Quit…" then "Force Quit Arc") that the native
        // menu hides — AX enumerates them flat. An item whose title
        // extends its predecessor's (ellipsis stripped) is the alternate.
        if collapseAlternates, !prevTitle.isEmpty {
            let base = prevTitle.replacingOccurrences(of: "…", with: "")
            if title.hasPrefix(base) { continue }
        }
        prevTitle = title
        // Recent Items' own hold-Option alternates ("Show X in Finder")
        // carry a different title shape than the root menu's (English UI;
        // the pattern is locale-bound, worst case they reappear)
        if recents, title.hasPrefix("Show “"), title.hasSuffix("” in Finder") { continue }
        if recents, ["Applications", "Documents", "Servers"].contains(title) {
            section = title
            rows.append(PopupRow(text: title, dim: true))
            continue
        }
        if !axChildren(item).isEmpty {
            rows.append(PopupRow(icon: "›", text: title, action: {
                appMenuStack.append((title, item))
                refreshPopup()
            }))
        } else {
            rows.append(PopupRow(image: recents ? recentItemIcon(title, section: section) : nil,
                                 text: title, detail: menuShortcut(item), action: {
                closePopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    AXUIElementPerformAction(item, "AXPress" as CFString)
                }
            }))
        }
    }
    return rows
}

// the frontmost app's AX menu bar, resolved the popup-safe way
func frontAppAXMenuBar() -> AXUIElement? {
    guard !model.frontApp.isEmpty,
          let app = NSWorkspace.shared.runningApplications.first(where: {
              $0.localizedName == model.frontApp
                  && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
          })
    else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, axTimeout)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, "AXMenuBar" as CFString, &ref) == .success,
          let bar = ref, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    AXUIElementSetMessagingTimeout(bar as! AXUIElement, axTimeout)
    return (bar as! AXUIElement)
}

// The REAL Apple menu — child 0 of the front app's menu bar, the item
// the app drill-down skips — through the same drill machinery, with
// omacchiato's own extras appended. Falls back to the hand-rolled rows
// when Accessibility is not granted or AX has nothing.
func appleMenuRows() -> [PopupRow] {
    guard AXIsProcessTrusted(),
          let menubar = frontAppAXMenuBar(),
          let apple = axChildren(menubar).first
    else { return appleRows() }
    if !appMenuStack.isEmpty {
        return appMenuRows()
    }
    var rows = rowsForMenu(apple, collapseAlternates: true)
    guard !rows.isEmpty else { return appleRows() }
    if rows.last?.separator != true { rows.append(PopupRow(separator: true)) }
    rows.append(PopupRow(text: "theme", detail: currentThemeName(), dim: true, action: {
        closePopup()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell("\(NSHomeDirectory())/.local/bin/theme-next", [])
        }
    }))
    return rows
}

func appMenuRows() -> [PopupRow] {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(opts) else {
        return [PopupRow(text: "grant Accessibility to omacchiato-bar", hero: true),
                PopupRow(text: "System Settings opened the pane — toggle the bar on,", dim: true),
                PopupRow(text: "then click the app name again", dim: true)]
    }
    // drilled into a menu: its items, behind a back row
    if let top = appMenuStack.last {
        var rows = [PopupRow(icon: "‹", text: top.title, highlight: true, action: {
            appMenuStack.removeLast()
            refreshPopup()
        })]
        rows.append(contentsOf: rowsForMenu(top.element, context: top.title))
        return rows
    }
    // NOT frontmostApplication: the click that opens this popup makes
    // the bar itself frontmost for a beat, and the popup bailed empty.
    // model.frontApp tracks the real app and ignores our own pid.
    guard let menubar = frontAppAXMenuBar() else {
        tlog("appmenu: no menu bar for '\(model.frontApp)'")
        return []
    }
    // no hero title: the app's name is literally the pill this popup
    // hangs from. Index 0 is the Apple menu — our apple pill's ground.
    var rows: [PopupRow] = []
    for item in axChildren(menubar).dropFirst() {
        let title = axString(item, "AXTitle")
        guard !title.isEmpty else { continue }
        rows.append(PopupRow(icon: "›", text: title, action: {
            appMenuStack.append((title, item))
            refreshPopup()
        }))
    }
    if !rows.isEmpty { rows[0].highlight = true }
    return rows
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// --- cheatsheet (Super+K) --------------------------------------------------
// Rendered from the LIVE config — OmniWM's settings.toml and omacchiato's
// Karabiner rules — never from a list kept here: a cheatsheet that can
// disagree with the keys is worse than no cheatsheet. The config's own
// section comments become the headings, so the grouping is the author's
// rather than a second opinion about it.

struct CheatEntry {
    let group: String
    let key: String
    let action: String
}

// "Control+Option+Command+Shift+1" -> "Super+Shift+1". Super IS
// Control+Option+Command here (Caps Lock sends it), so it is collapsed
// back into the one key the user actually presses. The key names arrive
// already capitalised; only " Arrow" is dropped, so the arrows read "Left".
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

// "switchWorkspace.0" -> "switch workspace 1": the raw catalog ids were
// printed verbatim once, on the theory that the config's truth beats a
// pretty lie — and read as a mess (0-based suffixes beside 1-based
// keycaps, camelCase runs). The id's meaning survives; only the casing
// and indexing are translated to match the keycap next to it.
func humanizeOmniId(_ id: String) -> String {
    func words(_ s: String) -> String {
        var out = ""
        for ch in s { out.append(ch.isUppercase ? " " + String(ch).lowercased() : String(ch)) }
        return out.trimmingCharacters(in: .whitespaces)
    }
    let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
    // dwindle reality beats the catalog's niri-flavored names: moveColumn
    // is a tile SWAP there (the binding people reach for daily), and
    // plain move STACKS into the neighbor as a group
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

// with the comment headings stripped by the strict-decoder rewrite, the
// sheet gets its sections from the id families instead
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
        // the canonical settings file carries EVERY catalog id — most
        // Unassigned. A cheatsheet's job is what you CAN press, so the
        // ~90 unassigned rows stay out (they made the sheet a wall).
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
            // a comment between tables starts the NEXT group: a complete
            // pending entry belongs to the heading it was written under,
            // not the one about to be read (a half-read table keeps its
            // keys — TOML allows comments between them)
            if !binding.isEmpty, !id.isEmpty { flush() }
            // only the FIRST line of a comment block is a heading; the
            // rest is prose, and the "---" ruler decoration is trimmed off
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
    // derived groups arrive interleaved (switch/move alternate per
    // workspace) — order them section by section, keeping in-group
    // order (index tiebreak kept explicit rather than leaning on
    // sort stability)
    let sectionOrder = ["Workspaces", "Focus", "Move", "Layout & columns", "Size", "System"]
    let indexed = entries.enumerated().map { ($0.offset, $0.element) }
    entries = indexed.sorted { a, b in
        let ga = sectionOrder.firstIndex(of: a.1.group) ?? 99
        let gb = sectionOrder.firstIndex(of: b.1.group) ?? 99
        return ga != gb ? ga < gb : a.0 < b.0
    }.map { $0.1 }
    // the exec chords live in Karabiner, because OmniWM's hotkeys cannot
    // exec — the sheet must show them or half the muscle-memory map is
    // invisible. Read our own injected rules back by their description
    // prefix.
    entries.append(contentsOf: karabinerExecCheatEntries())
    return entries
}

// "omacchiato-omniwm: terminal" rules out of karabiner.json — description
// carries the action, from.key_code + modifiers carry the chord
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

// the sheet takes key focus while open (the overview's pattern) so it
// can be typed into; hideCheatsheet hands focus back to the app that
// had it, so the search never costs the user their window
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
                                xRadius: popupRadius, yRadius: popupRadius)
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
            hideCheatsheet() // Super+K toggles closed even while we hold key
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
    // take key so typing filters — remember the app that had focus, the
    // close path activates it again
    cheatPrevApp = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    cheatWindow = window
    tlog("cheatsheet: \(entries.count) bindings")
}

// --- view -----------------------------------------------------------------

// Text positioning, done properly.
//
// `NSString.size(withAttributes:)` returns the TYPOGRAPHIC box — advance
// width and line height — which is what you want to flow a paragraph and
// exactly wrong for centring one glyph in a pill. A glyph's ink does not
// fill its advance (Nerd Font icons carry lopsided side bearings), and a
// line box reserves descender room that digits never use. Measured on the
// live bar, that put the wifi glyph 4 px right of centre and every label
// about 1 px high.
//
// So: icons centre on their INK box, text centres on CAP HEIGHT. Cap
// height rather than ink for text because it does not move when the
// content changes — "28°C" and "8:05 PM" sit on the same baseline.
func inkBox(_ s: String, _ font: NSFont) -> CGRect {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font]))
    return CTLineGetImageBounds(line, nil) // baseline at y = 0
}

func advance(_ s: String, _ font: NSFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

func fit(_ s: String, _ font: NSFont, _ width: CGFloat) -> String {
    guard advance(s, font) > width else { return s }
    var cut = s
    while !cut.isEmpty, advance(cut + "…", font) > width { cut.removeLast() }
    return cut.trimmingCharacters(in: .whitespaces) + "…"
}

// draws with `origin` as the BASELINE origin, which is the only anchor
// that means the same thing for every string
func drawLine(_ s: String, _ font: NSFont, _ color: NSColor, baseline origin: CGPoint) {
    guard !s.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: s, attributes: [.font: font, .foregroundColor: color]))
    ctx.textPosition = origin
    CTLineDraw(line, ctx)
}

// one glyph, centred on its ink in both axes
func drawIcon(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    let ink = inkBox(s, font)
    drawLine(s, font, color,
             baseline: CGPoint(x: box.midX - ink.midX, y: box.midY - ink.midY))
}

// a text run: advance-centred across, cap-height-centred down
func drawText(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    drawLine(s, font, color,
             baseline: CGPoint(x: box.midX - advance(s, font) / 2,
                               y: box.midY - font.capHeight / 2))
}

func drawText(_ s: String, _ font: NSFont, _ color: NSColor, leftAt x: CGFloat, midY: CGFloat) {
    drawLine(s, font, color, baseline: CGPoint(x: x, y: midY - font.capHeight / 2))
}

// Icons come from the running app and are cached by name: a redraw must
// not walk the process list.
var iconCache: [String: NSImage] = [:]
func appIcon(_ name: String) -> NSImage? {
    if let cached = iconCache[name] { return cached }
    guard let icon = NSWorkspace.shared.runningApplications
        .first(where: { $0.localizedName == name })?.icon else { return nil }
    iconCache[name] = icon
    return icon
}

// The first three distinct apps: the cards a workspace chip fans out.
func handOf(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return Array(names.filter { seen.insert($0).inserted }.prefix(3))
}

// Up to three app icons fanned like a hand of cards: the first in front,
// tilted left, and the others behind it to the right.
func drawHand(_ icons: [NSImage], ring: Int?, centeredIn box: NSRect) {
    guard icons.count > 1 else {
        let only = NSRect(x: box.midX - 9, y: barHeight / 2 - 9, width: 18, height: 18)
        icons.first?.draw(in: only)
        if ring == 0 { drawRing(only) }
        return
    }
    // Smaller cards keep the fan clear of the next chip's icon.
    let card = NSRect(x: box.midX - 7.5, y: barHeight / 2 - 7.5, width: 15, height: 15)
    let fan: [(shift: CGFloat, tilt: CGFloat)] = icons.count == 2
        ? [(-3.5, 10), (3.5, -10)]
        : [(-5, 12), (0, 0), (5, -12)]

    func posed(_ pose: (shift: CGFloat, tilt: CGFloat), _ paint: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        // tilt about the card's own bottom centre, then slide it by the shift
        let turn = NSAffineTransform()
        turn.translateX(by: card.midX + pose.shift, yBy: card.minY)
        turn.rotate(byDegrees: pose.tilt)
        turn.translateX(by: -card.midX, yBy: -card.minY)
        turn.concat()
        paint()
        NSGraphicsContext.restoreGraphicsState()
    }

    for (icon, pose) in zip(icons, fan).reversed() { posed(pose) { icon.draw(in: card) } }
    // the ring goes on last: the cards in front cover most of its own card
    if let ring, ring < min(icons.count, fan.count) { posed(fan[ring]) { drawRing(card) } }
}

// The ring around the focused app's icon. It hugs the icon art, which sits
// inside a transparent margin of about a tenth of the card.
func drawRing(_ card: NSRect) {
    let art = card.insetBy(dx: card.width * 0.06, dy: card.width * 0.06)
    let path = NSBezierPath(roundedRect: art, xRadius: art.width * 0.26, yRadius: art.width * 0.26)
    path.lineWidth = 1.2
    palette.accent.withAlphaComponent(0.8).setStroke()
    path.stroke()
}

let barHeight: CGFloat = 34
let padLeft: CGFloat = 10
let chipBox: CGFloat = 20
let chipPad: CGFloat = 2
let pillHeight: CGFloat = 26
let radius: CGFloat = 4
let gap: CGFloat = 10
// horizontal breathing room inside a pill, each side
let pillPad: CGFloat = 6

// The terminal the activity pill opens btop in. install.sh writes the
// RESOLVED choice (apps.local.conf overrides already applied) next to the
// other daemon configs, because a launchd agent cannot read the repo when
// the clone sits under ~/Documents — which is exactly where this one is.
// login(1) execs the command with the system PATH, which has no Homebrew
// prefix on it, so `btop` by name is "No such file or directory".
// The absolute path goes to Ghostty as --command, NOT -e: -e raises a
// confirmation dialog every time, by design, because letting any process
// tell a terminal what to run is the hole GHSA-q9fg-cpmh-c78x closed.
let btopBin = ["/opt/homebrew/bin/btop", "/usr/local/bin/btop"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "btop"

let terminalApp: String = {
    let config = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/omacchiato/apps.conf")
    guard let text = try? String(contentsOf: config, encoding: .utf8) else { return "Ghostty" }
    for line in text.split(separator: "\n") where line.hasPrefix("TERMINAL=") {
        return line.dropFirst("TERMINAL=".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
    return "Ghostty"
}()

// The media title, drawn once into a layer with the bar's own text routine.
// A title wider than its box scrolls: Core Animation moves the layer in the
// render server, so the bar redraws nothing while it scrolls.
// Slides a pill's label up to a second line and back, holding each for
// 4 s. The pill keeps the label's width, so the second line is cut to fit.
final class Ticker: NSView {
    private let strip = CALayer()
    private var content = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        strip.anchorPoint = .zero
        layer?.addSublayer(strip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // clicks belong to the bar underneath
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func hide() {
        isHidden = true
        content = ""
    }

    func show(_ label: String, _ text: String, _ tail: String, font: NSFont,
              colors: (NSColor, NSColor), in box: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isHidden = false
        frame = box
        let second = fit(text, font, box.width - advance(" " + tail, font)) + " " + tail
        let key = "\(label)|\(second)|\(font)|\(colors)|\(box.size)"
        guard key != content else { return }
        content = key
        // three lines from the top: label, second, label again, so the loop
        // ends where it starts
        let h = box.height
        let size = NSSize(width: box.width, height: h * 3)
        strip.contents = NSImage(size: size, flipped: false) { _ in
            for (index, (line, color)) in [(label, colors.0), (second, colors.1), (label, colors.0)].enumerated() {
                let midY = h * CGFloat(2 - index) + h / 2
                drawLine(line, font, color, baseline: CGPoint(x: 0, y: midY - font.capHeight / 2))
            }
            return true
        }
        strip.contentsScale = window?.backingScaleFactor ?? 2
        strip.frame = NSRect(x: 0, y: -2 * h, width: size.width, height: size.height)
        strip.removeAllAnimations()
        let hold: CFTimeInterval = 4
        let slide = CFTimeInterval(dur(0.4))
        let total = 2 * (hold + slide)
        let cycle = CAKeyframeAnimation(keyPath: "transform.translation.y")
        cycle.values = [0, 0, h, h, 2 * h]
        cycle.keyTimes = [0, hold, hold + slide, 2 * hold + slide, total].map { NSNumber(value: $0 / total) }
        if slide == 0 {
            // Reduce motion: swap the lines with no slide. Discrete takes one more key time than values.
            cycle.calculationMode = .discrete
            cycle.values = [0, h]
            cycle.keyTimes = [0, 0.5, 1]
        }
        cycle.duration = total
        cycle.repeatCount = .infinity
        strip.add(cycle, forKey: "tick")
    }
}

final class Marquee: NSView {
    private let strip = CALayer()
    private var content = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        strip.anchorPoint = .zero
        layer?.addSublayer(strip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // clicks belong to the bar underneath
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func hide() {
        isHidden = true
        content = ""
    }

    func show(_ title: String, font: NSFont, color: NSColor, in box: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isHidden = false
        frame = box
        let fits = advance(title, font) <= box.width + 0.5
        let spacer = "      "
        let text = fits ? title : title + spacer + title
        let key = "\(text)|\(font)|\(color)|\(box.size)"
        guard key != content else { return }
        content = key
        let size = NSSize(width: ceil(advance(text, font)) + 2, height: box.height)
        strip.contents = NSImage(size: size, flipped: false) { rect in
            drawLine(text, font, color, baseline: CGPoint(x: 0, y: rect.midY - font.capHeight / 2))
            return true
        }
        strip.contentsScale = window?.backingScaleFactor ?? 2
        strip.frame = NSRect(origin: .zero, size: size)
        strip.removeAllAnimations()
        guard !fits else { return }
        // hold at the start, then travel one title and gap at 30 pt a second
        let distance = advance(title + spacer, font)
        let hold: CFTimeInterval = 2
        let travel = CFTimeInterval(distance / 30)
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -distance]
        scroll.keyTimes = [0, NSNumber(value: hold / (hold + travel)), 1]
        scroll.duration = hold + travel
        scroll.repeatCount = .infinity
        strip.add(scroll, forKey: "scroll")
    }
}

final class BarView: NSView {
    weak var surface: BarSurface?
    let marquee = Marquee()
    let ticker = Ticker()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(marquee)
        addSubview(ticker)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    var chipRects: [(String, NSRect)] = []
    // the pill a popup hangs under, and the larger area that takes its clicks
    var itemRects: [(String, pill: NSRect, hit: NSRect)] = []
    var mediaRects: [(String, NSRect)] = []
    var appleRect: NSRect = .zero

    override var isFlipped: Bool { false }

    // the media capsule: artwork, then the title. The title box keeps the
    // old character cap, and a longer title scrolls inside it. The art slot
    // is always there, so the title does not move while the art loads.
    private func mediaLayout(_ titleFont: NSFont) -> (width: CGFloat, art: NSRect, title: NSRect) {
        // 8 pt makes the gap before the art match the gap before the app name
        let inset = (pillHeight - mediaArtSide) / 2
        let art = NSRect(x: 8, y: inset, width: mediaArtSide, height: mediaArtSide)
        let x = 8 + mediaArtSide + 8
        // `media = <characters>` in bar-pills.conf; a notch leaves the left
        // cluster less room, so a notched display takes five sevenths of it
        let chars = Int(pillModes["media"] ?? "") ?? 28
        let limit = (surface?.notched ?? false) ? chars * 5 / 7 : chars
        let cap = advance(String(repeating: "0", count: limit), titleFont)
        let w = min(ceil(advance(model.media.title, titleFont)), cap)
        return (x + w + 10, art, NSRect(x: x, y: 0, width: w, height: pillHeight))
    }

    private func mediaSize(_ titleFont: NSFont) -> CGFloat {
        guard model.media.running, !model.media.title.isEmpty else { return 0 }
        return mediaLayout(titleFont).width
    }

    private func drawMedia(at origin: CGFloat, _ titleFont: NSFont) {
        let layout = mediaLayout(titleFont)
        let pill = NSRect(x: origin, y: (barHeight - pillHeight) / 2, width: layout.width, height: pillHeight)
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
        let r = layout.art.offsetBy(dx: pill.minX, dy: pill.minY)
        if let image = mediaArt {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).addClip()
            image.draw(in: r)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // placeholder while the art loads, or for a track with no art
            palette.muted.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            draw("\u{F075A}", nerdFont("Bold", 12), palette.muted, centeredIn: r)
        }
        marquee.show(model.media.title, font: titleFont, color: palette.label,
                     in: layout.title.offsetBy(dx: pill.minX, dy: pill.minY))
        mediaRects.append(("title", NSRect(x: pill.minX, y: 0, width: pill.width, height: barHeight)))
    }

    private func draw(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: NSRect) {
        drawText(s, font, color, centeredIn: box)
    }

    override func draw(_ dirtyRect: NSRect) {
        chipRects.removeAll()
        itemRects.removeAll()
        mediaRects.removeAll()
        let chipFont = nerdFont("SemiBold", 13)
        let appFont = nerdFont("Bold", 13)
        let iconFont = nerdFont("Bold", 14)
        guard let surface else { return }

        // workspace chips, in one bracket — this display's set only.
        // Undocked, force-assignment parks the GUEST set (11-19) on the
        // single display, where its empty slots would render as
        // duplicate digits — so they are hidden and an empty primary
        // keeps its slot to hold the row at 1..9. Docked, this
        // surface's list IS its own set: every slot belongs on the row,
        // and filtering left the laptop showing two lonely icons.
        let shown = surfaces.count > 1 ? surface.workspaces
            : surface.workspaces.filter {
                $0.count == 1 || model.occupied.contains($0) || $0 == model.focused
            }
        // apple pill: the system menu the hidden native menu bar carried
        let appleGlyph = "\u{f179}"
        let appleFont = nerdFont("Bold", 15)
        let appleW = inkBox(appleGlyph, appleFont).width + 20
        let apple = NSRect(x: padLeft, y: (barHeight - pillHeight) / 2, width: appleW, height: pillHeight)
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: apple, xRadius: radius, yRadius: radius).fill()
        drawIcon(appleGlyph, appleFont, palette.accent, centeredIn: apple)
        appleRect = NSRect(x: apple.minX, y: 0, width: appleW, height: barHeight)

        let bracketW = CGFloat(shown.count) * (chipBox + chipPad * 2)
        let bracket = NSRect(x: apple.maxX + 10, y: (barHeight - pillHeight) / 2,
                             width: bracketW, height: pillHeight)
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: bracket, xRadius: radius, yRadius: radius).fill()

        var x = bracket.minX
        for ws in shown {
            let slot = NSRect(x: x, y: 0, width: chipBox + chipPad * 2, height: barHeight)
            let box = slot.insetBy(dx: chipPad, dy: 0)
            // each display marks the workspace IT is showing. The
            // globally focused workspace is not a useful answer on the
            // other screen's bar: docked, it never matched there and
            // the laptop had no "you are here" at all.
            if ws == surface.visible {
                palette.accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: box.midX - 2, y: 2, width: 4, height: 4)).fill()
            }
            // the accent marks keyboard focus; the dot alone marks what this display shows
            let tint: NSColor = ws == model.focused ? palette.accent : palette.muted
            switch workspaceIconConfig.icon(for: ws) {
            case .some(.glyph(let glyph)):
                drawIcon(glyph, iconFont, tint, centeredIn: box)
            case .some(.image(let icon)):
                icon.draw(in: NSRect(x: box.midX - 9, y: barHeight / 2 - 9, width: 18, height: 18))
            case .some(.unavailable), .none:
                let cards = (model.wsApps[ws] ?? []).compactMap { name in appIcon(name).map { (name, $0) } }
                if cards.isEmpty {
                    draw(String(ws.suffix(1)), chipFont, tint, centeredIn: box)
                } else {
                    let ring = ws == model.focused
                        ? cards.firstIndex { $0.0 == model.focusedApp } : nil
                    drawHand(cards.map { $0.1 }, ring: ring, centeredIn: box)
                }
            }
            chipRects.append((ws, slot))
            x += chipBox + chipPad * 2
        }

        // front-app pill — clickable: it drops the app's real menus
        var leftEdge = bracket.maxX
        appPillRect = .zero
        if !model.frontApp.isEmpty {
            let textW = advance(model.frontApp, appFont)
            let pill = NSRect(x: bracket.maxX + gap, y: (barHeight - pillHeight) / 2,
                              width: textW + 20, height: pillHeight)
            palette.itemBG.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            draw(model.frontApp, appFont, palette.accent, centeredIn: pill)
            appPillRect = pill
            leftEdge = pill.maxX
        }

        // media: centred where there is room, in the left cluster where a
        // notch owns the middle
        let mediaW = mediaSize(chipFont)
        if mediaW > 0 {
            drawMedia(at: surface.notched ? leftEdge + gap : (bounds.width - mediaW) / 2, chipFont)
        } else {
            marquee.hide()
        }

        // right cluster: laid out from the right edge inwards, so a pill
        // changing width never shifts the ones outside it
        var cursor = bounds.maxX - padLeft
        var tickerShown = false
        for name in rightOrder.reversed() {
            guard let item = rightItems[name], item.drawing else { continue }
            let parts = ([BarPart(icon: item.icon, iconColor: item.iconColor, label: item.label)] + item.parts)
                .filter { !($0.icon.isEmpty && $0.label.isEmpty) }
            guard !parts.isEmpty else { continue }
            let labelFont = chipFont
            // An icon-only pill is sized and centred on the glyph's INK, so
            // a lopsided side bearing cannot push it off centre. A pill with
            // a label flows icon-then-text, and the gap between them exists
            // only when both do — the weather pill has no icon (its glyph
            // lives in the label) and inherited the gap anyway, which is the
            // 7 px it sat right of centre by.
            let sizes = parts.map { part -> (icon: CGFloat, gap: CGFloat, label: CGFloat) in
                let hasIcon = !part.icon.isEmpty
                // icon-only is ignored where there is no icon: the weather pill
                // keeps its glyph in the label, so suppressing it draws nothing
                let hasLabel = !part.label.isEmpty && !(hasIcon && iconOnly.contains(name))
                return (hasIcon ? inkBox(part.icon, iconFont).width : 0,
                        hasIcon && hasLabel ? 7 : 0,
                        hasLabel ? advance(part.label, labelFont) : 0)
            }
            let partGap: CGFloat = 10
            let width = pillPad * 2 + partGap * CGFloat(parts.count - 1)
                + sizes.reduce(0) { $0 + $1.icon + $1.gap + $1.label }
            let pill = NSRect(x: cursor - width, y: (barHeight - pillHeight) / 2,
                              width: width, height: pillHeight)
            // The window takes a click only where it has ink, so a near-miss
            // in a gap or above a pill went to the window below. The hit
            // area runs from the screen's top edge to the bar's bottom, takes
            // half of each gap, and the last pill runs to the screen edge.
            let hitMaxX = cursor == bounds.maxX - padLeft ? bounds.maxX : pill.maxX + gap / 2
            let hitArea = NSRect(x: pill.minX - gap / 2, y: 0,
                                 width: hitMaxX - pill.minX + gap / 2, height: bounds.height)
            NSColor.clear.clickable.setFill()
            hitArea.fill()
            palette.itemBG.setFill()
            NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
            var x = pill.minX + pillPad
            for (part, size) in zip(parts, sizes) {
                if size.icon > 0 {
                    drawIcon(part.icon, iconFont, part.iconColor ?? palette.label,
                             centeredIn: NSRect(x: x, y: pill.minY, width: size.icon, height: pill.height))
                }
                let labelX = x + size.icon + size.gap
                if size.label > 0, part.label == item.label, !item.tickerText.isEmpty, !tickerShown {
                    ticker.show(item.label, item.tickerText, item.tickerTail, font: labelFont,
                                colors: (item.labelColor ?? palette.label, palette.yellow),
                                in: NSRect(x: labelX, y: pill.minY, width: size.label, height: pill.height))
                    tickerShown = true
                } else if size.label > 0 {
                    drawText(part.label, labelFont, item.labelColor ?? palette.label,
                             leftAt: labelX, midY: pill.midY)
                }
                x += size.icon + size.gap + size.label + partGap
            }
            itemRects.append((name, pill, hitArea))
            cursor = pill.minX - gap
        }
        if !tickerShown { ticker.hide() }
    }


    // Tracking areas, not a poll and not a global monitor: a global
    // monitor stops delivering once this app is itself active, which is
    // exactly what clicking the bar makes it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseExited(with event: NSEvent) { scheduleHullCheck() }

    private func hit(_ event: NSEvent) -> String? {
        let p = convert(event.locationInWindow, from: nil)
        return itemRects.first(where: { $0.hit.contains(p) })?.0
    }

    var appPillRect = NSRect.zero

    // A click on an item and omacchiato-popup both open its popup through here.
    func showItemPopup(_ name: String) {
        guard let surface else { return }
        switch name {
        case "apple", "appmenu":
            let rect = name == "apple" ? appleRect : appPillRect
            guard rect != .zero else { return }
            appMenuStack.removeAll()
            // clicking the bar deactivated the app, which makes its menu
            // items read disabled and presses land nowhere — hand focus
            // straight back while our popup (never key) stays up
            NSWorkspace.shared.runningApplications
                .first { $0.localizedName == model.frontApp }?
                .activate()
            // both sit at the left edge, so a right-aligned popup would hang off the screen
            showPopup(name, under: window?.convertToScreen(convert(rect, to: nil)) ?? rect,
                      on: surface, alignLeft: true)
        default:
            guard let rect = itemRects.first(where: { $0.0 == name })?.pill else { return }
            showPopup(name, under: window?.convertToScreen(convert(rect, to: nil)) ?? rect, on: surface)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if appPillRect != .zero, appPillRect.contains(p), surface != nil {
            showItemPopup("appmenu")
            return
        }
        if appleRect.contains(p), surface != nil {
            showItemPopup("apple")
            return
        }
        if let ws = chipRects.first(where: { $0.1.contains(p) })?.0 {
            DispatchQueue.global(qos: .userInitiated).async { focusWorkspace(ws) }
            return
        }
        if let part = mediaRects.first(where: { $0.1.contains(p) })?.0 {
            closePopup()
            if part == "title", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        guard let name = hit(event) else {
            closePopup()
            return
        }
        if name == "clock", let link = soonMeetingLink {
            closePopup()
            NSWorkspace.shared.open(link)
            return
        }
        // an item with a popup toggles it; the rest still act directly
        if !popupRows(for: name).isEmpty, surface != nil {
            showItemPopup(name)
            return
        }
        closePopup()
        switch name {
        case "activity":
            DispatchQueue.global(qos: .userInitiated).async {
                _ = shell("/usr/bin/open", ["-na", terminalApp, "--args", "--title=omacchiato-activity", "--command=\(btopBin)"])
            }
        default:
            // a plugin pill: clicking asks for a fresh value now
            if let plugin = barPlugins.first(where: { $0.name == name }) { runPlugin(plugin) }
        }
    }

    // Middle click: the quick toggle of a pill, with no popup.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if mediaRects.contains(where: { $0.1.contains(p) }) {
            musicCommand("playpause")
            return
        }
        switch hit(event) {
        case "volume":
            toggleMute() // the CoreAudio listener repaints
        case "wifi":
            guard let interface = CWWiFiClient.shared().interface() else { return }
            try? interface.setPower(!interface.powerOn())
            updateWifi()
        default: break
        }
    }

    // A trackpad flick delivers dozens of precise events plus a momentum
    // tail; stepping 5% on each raced through the whole range. Momentum is
    // dropped and precise deltas accumulate until a notch's worth of finger
    // travel has passed — a clicky wheel already arrives one notch at a time.
    private var scrollAccum: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let onChips = chipRects.contains { $0.1.contains(p) }
        let onMedia = mediaRects.contains { $0.1.contains(p) }
        guard let name = onChips ? "workspaces" : onMedia ? "media" : hit(event) else { return }
        if !event.momentumPhase.isEmpty { return }
        if event.phase == .began { scrollAccum = 0 }
        scrollAccum += event.scrollingDeltaY
        let notch: CGFloat = event.hasPreciseScrollingDeltas ? 20 : 1
        if abs(scrollAccum) < notch { return }
        let step = scrollAccum > 0 ? 5 : -5
        scrollAccum = 0
        switch name {
        case "workspaces":
            let op = step > 0 ? "next" : "prev"
            DispatchQueue.global(qos: .userInitiated).async {
                _ = shell("\(NSHomeDirectory())/.local/bin/omacchiato-ws", [op], timeout: omniTimeout)
            }
        case "media":
            musicCommand(step > 0 ? "next track" : "previous track")
        case "volume":
            guard let v = readVolume() else { return }
            writeVolume(v.percent + step) // the CoreAudio listener repaints
        case "brightness":
            var value: Float = 0
            guard DSGetBrightness(builtinDisplayID(), &value) == 0 else { return }
            // one continuous scale: the backlight down to 0, then shade
            if step < 0, value <= 0.001 {
                setShade(shade + 0.08)
            } else if step > 0, shade > 0.001 {
                setShade(shade - 0.08) // come out of shade before raising the backlight
            } else {
                _ = DSSetBrightness(builtinDisplayID(), min(1, max(0, value + Float(step) / 100)))
                updateBrightness()
            }
        default: break
        }
    }
}
