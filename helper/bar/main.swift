// The bar's startup code, run in order. Declarations live in bar.swift; a
// global there starts on first read, so tests can import it without
// starting the bar. A global here starts when its line runs, so it
// cannot read a later global in this file.

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
#if canImport(BarPills)
import BarPills
#endif

if CommandLine.arguments.contains("--request-permissions") { requestPermissions() }

// --- window ---------------------------------------------------------------

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// AppKit pushes an ordinary window down out of the menu bar strip, 32 px
// lower than asked, which is exactly where a bar belongs. Opting out of
// the constraint is the supported way to sit there.
final class BarWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// The bar owns the top strip. OMACCHIATO_BAR_STACK=1 drops it by one bar
// height, to run alongside another bar for comparison.
// Breathing room above the pills. The window grows downward by this much
// while its top edge stays on the screen edge. Every pill is placed from
// the bottom of the view, so the extra height lands above them and no
// drawing constant changes.
let barTopPad: CGFloat = 3

let stackOffset: CGFloat = ProcessInfo.processInfo.environment["OMACCHIATO_BAR_STACK"] == nil ? 0 : barHeight

// One surface per display. Each owns its screen's workspace set and its
// own window; everything else it reads from the shared model.
final class BarSurface {
    var screen: NSScreen
    var monitorID: String
    var workspaces: [String] = []
    var mine: Set<String> = []
    var visible = ""
    let window: BarWindow
    let view: BarView

    // A notched display has no usable centre, so the media capsule joins
    // the left cluster there.
    var notched: Bool { screen.safeAreaInsets.top > 0 }

    init(screen: NSScreen, monitorID: String) {
        self.screen = screen
        self.monitorID = monitorID
        let frame = NSRect(x: screen.frame.minX,
                           y: screen.frame.maxY - barHeight - barTopPad - stackOffset,
                           width: screen.frame.width, height: barHeight + barTopPad)
        window = BarWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // AppKit honours a negative window level: the bar still renders
        // and receives clicks below normal windows. OmniWM's top outer
        // gap keeps tiled windows off the strip (measured: a tiled
        // window sits at y=42, the bar at 0..34).
        //
        // This does not replace the fullscreen check. On a notched
        // display a fullscreen window starts below the notch, at y=32,
        // so z-order alone cannot hide the bar there. Being below
        // windows still helps: the bar never floats over an app, and on
        // a flat display fullscreen covers it for free.
        window.level = NSWindow.Level(rawValue: -20)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true // tracking areas need the moves
        view = BarView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = view
        view.surface = self
        window.orderFrontRegardless()
    }

    func place() {
        let frame = NSRect(x: screen.frame.minX,
                           y: screen.frame.maxY - barHeight - barTopPad - stackOffset,
                           width: screen.frame.width, height: barHeight + barTopPad)
        window.setFrame(frame, display: true)
        view.frame = NSRect(origin: .zero, size: frame.size)
    }
}

var surfaces: [BarSurface] = []

func screenID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

// Monitor ids are resolved by display name every time the screens change,
// never cached. A stale id returns an empty snapshot, which renders as
// the last known set, stale and silent. OmniWM names monitors with
// NSScreen.localizedName (Monitor.current() in its source), so the name
// join works; its ids stay opaque and meet only the query payloads they
// came from.
func monitorIDs(active: Bool = omniwmActive()) -> [String: String] { // display name -> OmniWM display id
    guard active else { return [:] }
    var map: [String: String] = [:]
    if let list = omniQuery("displays", ["--fields", "id,name"])?["displays"]
        as? [[String: Any]] {
        for d in list {
            if let id = d["id"] as? String, let name = d["name"] as? String { map[name] = id }
        }
    }
    return map
}

// The OmniWM query runs on rebuildQueue, because a hung OmniWM blocks it
// for up to two timeouts. One query runs at a time: a call during a query
// asks for one more after it. New surfaces need a snapshot of their own.
var surfacesFetching = false
var surfacesAgain = false
func rebuildSurfaces() {
    guard !surfacesFetching else { surfacesAgain = true; return }
    surfacesFetching = true
    let active = omniwmActive()
    rebuildQueue.async {
        let ids = monitorIDs(active: active)
        DispatchQueue.main.async {
            surfacesFetching = false
            applySurfaces(ids)
            kickRebuild()
            if surfacesAgain {
                surfacesAgain = false
                rebuildSurfaces()
            }
        }
    }
}

func applySurfaces(_ ids: [String: String]) {
    var kept: [BarSurface] = []
    for screen in NSScreen.screens {
        // With no window manager, draw on every screen anyway: the pills
        // work, and the chips return when a manager answers.
        guard let id = ids.isEmpty ? "" : ids[screen.localizedName] else { continue }
        if let existing = surfaces.first(where: { screenID($0.screen) == screenID(screen) }) {
            if existing.monitorID != id {
                tlog("monitor: \(screen.localizedName) is now monitor \(id) (was \(existing.monitorID))")
                existing.monitorID = id
            }
            existing.screen = screen
            existing.place()
            kept.append(existing)
        } else {
            tlog("surface: \(screen.localizedName) -> monitor \(id)\(screen.safeAreaInsets.top > 0 ? " (notched)" : "")")
            kept.append(BarSurface(screen: screen, monitorID: id))
        }
    }
    for gone in surfaces where !kept.contains(where: { $0 === gone }) {
        tlog("surface: \(gone.screen.localizedName) went away")
        gone.window.orderOut(nil)
    }
    surfaces = kept
}

func repaint() {
    // every caller is already on the main queue; display() is synchronous
    // so the timings below cover real drawing, not just invalidation
    MainActor.assumeIsolated {
        for surface in surfaces {
            surface.view.needsDisplay = true
            surface.view.display()
        }
    }
}

// --- fullscreen ------------------------------------------------------------
// A window manager's fullscreen and native macOS fullscreen look the same
// from here, and both should take the strip. A managed window never
// starts at the display's top edge, so a window that does is fullscreen.

func safeTop(for display: CGRect) -> CGFloat {
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    for screen in NSScreen.screens {
        let cgY = primaryH - screen.frame.maxY
        if abs(screen.frame.origin.x - display.origin.x) < 2, abs(cgY - display.origin.y) < 2 {
            return screen.safeAreaInsets.top
        }
    }
    return 0
}

func fullscreenDisplays() -> Set<CGDirectDisplayID> {
    var covered: Set<CGDirectDisplayID> = []
    // Under OmniWM the width test below cannot tell a tiled window from
    // a fullscreen one. Its 0.6.3 dwindle applies no outer gaps (an
    // upstream bug: resolved settings say 42, layout applies 0; see
    // docs/omniwm-port.md), so an ordinary tile takes the side gaps too
    // and reads as fullscreen. Skip the check under OmniWM until that
    // bug is fixed, and accept that the bar can overlap a real
    // fullscreen window instead of ducking away.
    if omniwmActive() { return covered }
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    else { return covered }
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(8, &ids, &count) == .success else { return covered }

    for window in list {
        guard (window[kCGWindowLayer as String] as? Int) == 0,
              let b = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        for i in 0..<Int(count) {
            let display = CGDisplayBounds(ids[i])
            guard display.intersects(rect) else { continue }
            let inset = safeTop(for: display)
            // Height and top edge alone are not enough. On a notched
            // display, the notch inset (32) and the gap a tiled window
            // leaves for the bar (33) sit at the same edge, so an
            // ordinary tiled window can read as fullscreen. Width
            // separates them: a fullscreen window takes the side gaps
            // too, a tiled one never does.
            if rect.origin.y - display.origin.y < inset + 3,
               rect.height >= display.height - inset - 6,
               rect.width >= display.width - 2 {
                covered.insert(ids[i])
            }
        }
    }
    return covered
}

// Hidden by fullscreen but reachable: putting the pointer at the very top
// of the screen brings the bar back, like the native menu bar. While
// revealed, the bar climbs above the fullscreen window (its resting
// level of -20 is what hides it), and drops back when the pointer leaves.
let barBaseLevel = NSWindow.Level(rawValue: -20)
// above .screenSaver (1000), so an overlay at that level cannot cover it
let barRevealLevel = NSWindow.Level(rawValue: 1002)
let revealEdge: CGFloat = 2 // how close to the top edge counts as asking
var revealed = false

func setRevealed(_ show: Bool) {
    guard show != revealed else { return }
    revealed = show
    for surface in surfaces {
        surface.window.level = show ? barRevealLevel : barBaseLevel
    }
    updateBarVisibility()
}

// Called on every pointer move, so it stays a coordinate comparison and
// nothing more.
func pointerAtScreenTop() {
    let p = NSEvent.mouseLocation
    // Grow the rect before testing. CGRect.contains treats maxY as
    // exclusive, so a pointer on the top row of pixels, which is the
    // gesture this listens for, would otherwise count as being on no
    // screen.
    guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: 0, dy: -2).contains(p) })
    else { return }
    let fromTop = screen.frame.maxY - p.y
    if fromTop <= revealEdge {
        // Climb only when fullscreen actually hides the bar. Otherwise
        // stay at the -20 resting level, so the auto-hidden native menu
        // bar can slide in above the bar and stay clickable. Without
        // this, app menus are unreachable by mouse.
        if fullscreenDisplays().contains(screenID(screen)) {
            setRevealed(true)
        }
    } else if revealed, openPopup == nil, fromTop > barHeight + 12 {
        // a popup keeps it up: its anchor must not vanish under the pointer
        setRevealed(false)
    }
}

func updateBarVisibility() {
    let covered = fullscreenDisplays()
    for surface in surfaces {
        let hide = covered.contains(screenID(surface.screen)) && !revealed
        // unconditional either way: isVisible can desync from the window
        // server
        if hide {
            surface.window.orderOut(nil)
            if openPopup != nil { closePopup() }
        } else {
            surface.window.orderFrontRegardless()
        }
    }
}

// --- signals --------------------------------------------------------------

// Pokes arrive as writes to a regular file, not a FIFO: a FIFO with no
// reader would block the writer if this daemon died. Watching .attrib
// catches a symlink swap that .write alone misses. Watching delete and
// rename lets it re-arm, instead of going deaf for the rest of the
// daemon's life.
func watch(_ path: String, create: Bool, handler: @escaping () -> Void) {
    if create, !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let fd = open(path, O_EVTONLY)
    guard fd >= 0 else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { watch(path, create: create, handler: handler) }
        return
    }
    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
        eventMask: [.write, .attrib, .delete, .rename], queue: .main)
    src.setEventHandler {
        let ev = src.data
        handler()
        if ev.contains(.delete) || ev.contains(.rename) { src.cancel() }
    }
    src.setCancelHandler {
        close(fd)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { watch(path, create: create, handler: handler) }
    }
    src.resume()
}

// A window sent from one hidden workspace to another moves nothing on
// screen, so SkyLight reports no event at all, measured with a probe. No
// publisher exists for this, so the commands that move windows announce
// it themselves (omacchiato-ws, and the overview's drag-reorder).
// Super+K writes this file. The bar has no key tap, and should not grow one.
let cheatPath = "/tmp/omacchiato-bar-cheatsheet"
watch(cheatPath, create: true) { toggleCheatsheet() }

// omacchiato-popup writes "<item> [display name]" here; an empty line closes the popup
let popupPath = "/tmp/omacchiato-bar-popup"
var popupPoke: DispatchWorkItem?
watch(popupPath, create: true) {
    // a shell redirect empties the file before it writes, and each step can
    // wake the watcher; read once, after the write has landed
    popupPoke?.cancel()
    let poke = DispatchWorkItem {
        let line = ((try? String(contentsOfFile: popupPath, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let item = words.first else { closePopup(); return }
        let pointer = NSEvent.mouseLocation
        let surface = words.count > 1
            ? surfaces.first { $0.screen.localizedName == words[1] }
            : surfaces.first { NSMouseInRect(pointer, $0.screen.frame, false) }
        tlog("popup command \(line): \(surface == nil ? "no such display" : "opening")")
        surface?.view.showItemPopup(item)
    }
    popupPoke = poke
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poke)
}

let movedPath = "/tmp/omacchiato-bar-moved"
watch(movedPath, create: true) {
    tlog("moved poke")
    kickRebuild()
}

// --- omniwm fast path -------------------------------------------------------
// A switch between two empty workspaces moves no windows, so SkyLight
// says nothing. OmniWM publishes instead: its active-workspace channel
// emits one event per change. Use `watch … --exec /bin/cat`, not
// `subscribe`: subscribe pretty-prints multi-line JSON, while watch hands
// its child one NDJSON line per event over an inherited pipe (OmniWM
// docs/IPC-CLI.md, watch). The stream arrives line-delimited, and the bar
// forks nothing.

var omniWatch: Process?
var omniWatchBuffer = Data()

func omniWorkspaceBarEvent(_ line: Data) {
    // Use the workspace-bar channel, not active-workspace. Measured
    // 2026-08-29: active-workspace and focus fire only when the focused
    // window changes, so a switch to or from an empty workspace stays
    // silent. workspace-bar fires on every switch and carries each
    // workspace's windows, so occupancy and app icons come free, with no
    // windows query.
    guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          root["channel"] as? String == "workspace-bar",
          let payload = (root["result"] as? [String: Any])?["payload"] as? [String: Any],
          let monitors = payload["monitors"] as? [[String: Any]]
    else { return }
    let current = payload["interactionMonitorId"] as? String ?? ""
    let t0 = DispatchTime.now().uptimeNanoseconds
    var changed = false
    var occupied = Set<String>()
    var hands: [String: [String]] = [:]
    var focusedNow = ""
    var focusedAppNow = ""
    for m in monitors {
        guard let id = m["id"] as? String,
              let list = m["workspaces"] as? [[String: Any]] else { continue }
        var active = ""
        for w in list {
            guard let name = w["rawName"] as? String else { continue }
            if (w["isFocused"] as? Bool) == true { active = name }
            // no floating filter here: OmniWM leaves floating windows out of
            // this payload unless its showFloatingWindows is on
            let wins = ((w["windows"] as? [[String: Any]]) ?? [])
                .filter { ($0["appName"] as? String)?.hasPrefix("omacchiato") != true }
            if !wins.isEmpty {
                occupied.insert(name)
                hands[name] = handOf(wins.compactMap { $0["appName"] as? String })
                if let app = wins.first(where: { ($0["isFocused"] as? Bool) == true })?["appName"] {
                    focusedAppNow = app as? String ?? ""
                }
            }
        }
        guard !active.isEmpty else { continue }
        if id == current { focusedNow = active }
        for surface in surfaces where surface.monitorID == id && surface.visible != active {
            surface.visible = active
            changed = true
        }
    }
    if !focusedNow.isEmpty, model.focused != focusedNow { model.focused = focusedNow; changed = true }
    if model.occupied != occupied { model.occupied = occupied; changed = true }
    if model.wsApps != hands { model.wsApps = hands; changed = true }
    if model.focusedApp != focusedAppNow { model.focusedApp = focusedAppNow; changed = true }
    guard changed else { return }
    repaint()
    kickVisibility()
    tlog(String(format: "switch %@ %.2f ms (omniwm)", focusedNow,
                Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000))
}

func startOmniWatch() {
    guard omniWatch == nil, omniwmActive() else { return }
    // A bar killed by launchd (kickstart -k sends SIGKILL) leaves its
    // stream child alive under pid 1, one per restart. Reap orphans
    // before spawning a new one; -P 1 cannot touch a living bar's own
    // child.
    let reap = Process()
    reap.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    reap.arguments = ["-P", "1", "-f", "omniwmctl watch workspace-bar"]
    try? reap.run()
    reap.waitUntilExit()
    let p = Process()
    p.executableURL = URL(fileURLWithPath: omniwmctlBin)
    p.arguments = ["watch", "workspace-bar", "--exec", "/bin/cat"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        DispatchQueue.main.async {
            omniWatchBuffer.append(chunk)
            while let nl = omniWatchBuffer.firstIndex(of: 0x0A) {
                let line = Data(omniWatchBuffer[omniWatchBuffer.startIndex..<nl])
                omniWatchBuffer = Data(omniWatchBuffer[omniWatchBuffer.index(after: nl)...])
                omniWorkspaceBarEvent(line)
            }
        }
    }
    p.terminationHandler = { proc in
        DispatchQueue.main.async {
            pipe.fileHandleForReading.readabilityHandler = nil
            guard omniWatch === proc else { return } // a newer watch took over
            omniWatch = nil
            // OmniWM restarting, or its IPC server not up yet, drops the
            // stream: keep knocking while OmniWM is the one running
            guard omniwmActive() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { startOmniWatch() }
        }
    }
    guard (try? p.run()) != nil else { return }
    omniWatch = p
    tlog("omniwm: watching workspace-bar")
}

func stopOmniWatch() {
    guard let p = omniWatch else { return }
    omniWatch = nil // before terminate, so the handler cannot restart it
    p.terminate()
}

// OmniWM can start or quit under the bar, and OmniWM.app appearing or
// vanishing is the signal. Monitor ids have to be re-resolved, and the
// retries cover OmniWM still booting when the first attempt asks.
for event in [NSWorkspace.didLaunchApplicationNotification,
              NSWorkspace.didTerminateApplicationNotification] {
    NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              isOmniWM(app.bundleIdentifier) else { return }
        let launched = event == NSWorkspace.didLaunchApplicationNotification
        tlog("wm: OmniWM \(launched ? "launched" : "quit")")
        if launched { startOmniWatch() } else { stopOmniWatch() }
        for delay in [1.0, 3.0, 8.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                rebuildSurfaces()
                kickRebuild()
            }
        }
    }
}

// The retries above stop at 15 s, and OmniWM's socket can take longer to
// answer after a settings migration. So while a surface has no monitor,
// look for OmniWM again every 5 s.
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    guard surfaces.contains(where: { $0.monitorID.isEmpty }) else { return }
    rebuildSurfaces()
    kickRebuild()
}

// front app: a notification, not a poll and not a script
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { note in
    let t0 = DispatchTime.now().uptimeNanoseconds
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let name = app.localizedName, name != model.frontApp,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    model.frontApp = name
    repaint()
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    tlog(String(format: "frontapp %@ %.2f ms", name, ms))
}

// Displays come and go. Re-resolve which OmniWM display this screen is
// now, move the window onto it, and rebuild. Give screen parameters a
// beat to settle before reading them.
//
// This is also where a second display's set folds and unfolds. Undocked,
// OmniWM moves that set's workspaces to the one display, but their
// windows stay on two-digit workspaces that Super+N cannot reach from
// there. omacchiato-ws-collapse moves those windows into the empty 1-9
// slots and remembers where they came from. The bar is the only
// long-lived process already watching for this, so it owns folding.
//
// Guard on the count changing: this notification also fires for
// resolution and arrangement changes, and re-folding on those would
// shuffle windows for no reason.
var monitorCount = NSScreen.screens.count
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
) { _ in
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        closePopup() // its anchor may not exist any more
        rebuildSurfaces()
        applyShade() // a new display arrives at full output
        kickRebuild()
        // The 1 s grace can still lose the race with the WM adopting the
        // new display: its monitor id resolves to nothing and the
        // screen stays barless (measured on a Dell, on replug). Use the
        // same retry ladder as the OmniWM launch observer.
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                rebuildSurfaces()
                applyShade()
                kickRebuild()
            }
        }
        let now = NSScreen.screens.count
        guard now != monitorCount else { return }
        let wasSingle = monitorCount == 1
        monitorCount = now
        let op = now == 1 ? "collapse" : (wasSingle ? "restore" : "")
        guard !op.isEmpty else { return }
        tlog("displays: \(now) — running ws-collapse \(op)")
        // off-main: it makes IPC calls per window, and sleeps between
        // moves while OmniWM settles
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell("\(NSHomeDirectory())/.local/bin/omacchiato-ws-collapse", [op])
            DispatchQueue.main.async { kickRebuild() }
        }
    }
}

// window create/destroy: the only thing that needs the slow path, and it
// is debounced off the critical path
var pending: DispatchWorkItem?
func kickRebuild() {
    pending?.cancel()
    let w = DispatchWorkItem {
        rebuildQueue.async {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let snapshot = fetchSnapshot()
            let fetched = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            DispatchQueue.main.async {
                let t1 = DispatchTime.now().uptimeNanoseconds
                guard apply(snapshot) else { return } // nothing moved
                repaint()
                let drawn = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1_000_000
                tlog(String(format: "rebuild fetch %.2f ms (off-main) + paint %.2f ms", fetched, drawn))
            }
        }
    }
    pending = w
    // This delay was sized for a snapshot that cost four subprocesses.
    // Now that a snapshot is cheaper, this delay itself can be what a
    // person notices most.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
}

let cid = SLSMainConnectionID()
// Move and resize events fire only for subscribed windows, and going
// fullscreen is a resize. Keep the subscription set equal to every
// normal window, refreshed on create or destroy.
var subscribed: Set<UInt32> = []
func rebuildSubscriptions() {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
    else { return }
    var wids: [UInt32] = []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
        if let n = w[kCGWindowNumber as String] as? Int { wids.append(UInt32(n)) }
    }
    let set = Set(wids)
    guard set != subscribed, !wids.isEmpty else { return }
    subscribed = set
    _ = wids.withUnsafeBufferPointer {
        SLSRequestNotificationsForWindows(cid, $0.baseAddress!, Int32(wids.count))
    }
}

// a fullscreen check is a window-list read, not a subprocess: cheap
// enough to run on a short debounce after any window event
var visibilityPending: DispatchWorkItem?
func kickVisibility() {
    visibilityPending?.cancel()
    let work = DispatchWorkItem { updateBarVisibility() }
    visibilityPending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
}

let notify: NotifyProc = { event, _, _, _ in
    DispatchQueue.main.async {
        if event == EVENT_WINDOW_CREATE || event == EVENT_WINDOW_DESTROY {
            kickRebuild()
            rebuildSubscriptions()
        } else if event == EVENT_WINDOW_ORDER || event == EVENT_WINDOW_VISIBILITY {
            // the chips are only as fresh as this: a window changing
            // workspace shows up here and nowhere else. A plain
            // workspace switch lands here too and fetches a snapshot
            // that changed nothing, which apply() reports so the
            // repaint is skipped.
            kickRebuild()
        }
        kickVisibility()
    }
}
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_CREATE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_DESTROY, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_MOVE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_RESIZE, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_ORDER, nil)
_ = SLSRegisterNotifyProc(notify, EVENT_WINDOW_VISIBILITY, nil)
rebuildSubscriptions()
var eventPort: mach_port_t = 0
if SLSGetEventPort(cid, &eventPort).rawValue == 0, eventPort != 0 {
    let drain = DispatchSource.makeMachReceiveSource(port: eventPort, queue: .main)
    drain.setEventHandler { while let e = SLEventCreateNextEvent(SLSMainConnectionID()) { e.release() } }
    drain.resume()
}

// theme switches: repaint, never rebuild. theme-set swaps the symlink
// inside this directory; the file behind the old one never changes itself.
watch(FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/omarchy/current").path, create: false) {
    let t0 = DispatchTime.now().uptimeNanoseconds
    palette = loadPalette()
    applyPanelColors()
    iconCache.removeAll()
    repaint()
    if cheatWindow != nil { hideCheatsheet(); toggleCheatsheet() } // repaint in the new palette
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    tlog(String(format: "theme %.2f ms", ms))
}

// Follow the macOS light/dark switch when theme.conf holds a Ghostty-style
// pair, `theme = light:<name>,dark:<name>`. theme-set picks the half.
var appearanceDark: Bool?   // the appearance last handled, so a repeated change notice runs theme-set once
func followAppearance() {
    let dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    guard dark != appearanceDark, let spec = readConf("theme.conf")["theme"],
          spec.contains(":") else { return }
    appearanceDark = dark
    var env = ProcessInfo.processInfo.environment
    env["OMACCHIATO_APPEARANCE"] = dark ? "dark" : "light"
    DispatchQueue.global(qos: .utility).async {
        _ = shell(NSHomeDirectory() + "/.local/bin/theme-set", [spec], env: env)
    }
}
followAppearance()
applyPanelColors()
let appearanceWatch = app.observe(\.effectiveAppearance) { _, _ in
    followAppearance()
    applyPanelColors()
}

// --- popup guard -----------------------------------------------------------
// A popup closes when the pointer sits in neither the bar nor the popup:
// that is what "don't close it while I'm still in the bar" means. The
// cursor is a published event and the geometry is already known, so the
// rule can be exact.
// The check runs a beat after the pointer leaves either surface, because
// moving from the bar to its popup crosses the gap between them, which
// must not read as leaving.
func scheduleHullCheck() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        if popupWindow != nil, pointerLeftTheHull() { closePopup() }
    }
}

func pointerLeftTheHull() -> Bool {
    guard let popup = popupWindow else { return false }
    let p = NSEvent.mouseLocation
    let slack: CGFloat = 6 // the gap between a bar and its popup
    if popup.frame.insetBy(dx: -slack, dy: -slack).contains(p) { return false }
    for surface in surfaces where surface.window.frame.insetBy(dx: 0, dy: -slack).contains(p) {
        return false
    }
    return true
}

// The monitor must be retained. Dropping the returned token deregisters
// it at once, and the popup then never closes on its own.
var popupGuardToken: Any?
var revealToken: Any?
revealToken = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in pointerAtScreenTop() }
var revealLocalToken: Any?
revealLocalToken = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in
    pointerAtScreenTop()
    return e
}

popupGuardToken = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
    // a click that lands in another app dismisses the popup; hover-exit
    // is the tracking areas' job
    if popupWindow != nil, pointerLeftTheHull() { closePopup() }
}

// --- right-cluster publishers ---------------------------------------------

// battery: IOPS fires on capacity ticks too
let powerCallback: IOPowerSourceCallbackType = { _ in DispatchQueue.main.async { updateBattery() } }
if let src = IOPSNotificationCreateRunLoopSource(powerCallback, nil)?.takeRetainedValue() {
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
} else {
    tlog("IOPSNotificationCreateRunLoopSource failed — battery pill will not update")
}

// volume: listen on the current default output device, and re-attach when
// the default changes (plugging in headphones is a different device)
var volumeListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

func attachVolumeListeners() {
    for (object, address, block) in volumeListeners {
        var a = address
        AudioObjectRemovePropertyListenerBlock(object, &a, DispatchQueue.main, block)
    }
    volumeListeners.removeAll()

    let dev = defaultOutputDevice()
    guard dev != 0 else { return }
    let block: AudioObjectPropertyListenerBlock = { _, _ in updateVolume() }
    for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(dev, &addr, DispatchQueue.main, block) == noErr {
            volumeListeners.append((dev, addr, block))
        }
    }
    updateVolume()
}

// the microphone: same shape, on the default input device
var micListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

func attachMicListeners() {
    for (object, address, block) in micListeners {
        var a = address
        AudioObjectRemovePropertyListenerBlock(object, &a, DispatchQueue.main, block)
    }
    micListeners.removeAll()

    let dev = defaultInputDevice()
    guard dev != 0 else { return }
    let block: AudioObjectPropertyListenerBlock = { _, _ in updateMic() }
    for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListenerBlock(dev, &addr, DispatchQueue.main, block) == noErr {
            micListeners.append((dev, addr, block))
        }
    }
    updateMic()
}

func startMicWatch() {
    var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                        &defaultInputAddress, DispatchQueue.main) { _, _ in
        attachMicListeners()
    }
    attachMicListeners()
}

var defaultDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                    &defaultDeviceAddress, DispatchQueue.main) { _, _ in
    attachVolumeListeners()
}
attachVolumeListeners()
startVolumeKeys()
// Not gated on the mic pill: the mic HUD shows with the pill hidden.
startMicWatch()
startKeepAwake()
quitWatch.start()
startMemoryLog()

// brightness: DisplayServices publishes, so the keyboard keys land here
// without the bar being told about them by anyone else
let brightnessProc: DSBrightnessProc = { _, _, _, _ in
    DispatchQueue.main.async { updateBrightness() }
}
if DSRegisterBrightnessNotifications(builtinDisplayID(), nil, brightnessProc) != 0 {
    tlog("brightness notifications unavailable — pill updates on scroll only")
}

// night shift: same idea, one layer up. The schedule flipping it is a
// change nobody else would tell an open popup about.
watchNightShift()

// network: the same SCDynamicStore keys the watcher uses
var storeContext = SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
if let store = SCDynamicStoreCreate(nil, "omacchiato-bar" as CFString,
                                    { _, _, _ in DispatchQueue.main.async { updateWifi() } }, &storeContext) {
    SCDynamicStoreSetNotificationKeys(store, nil, [
        "State:/Network/Global/IPv4",
        "State:/Network/Interface/en.*/Link",
        "State:/Network/Interface/en.*/AirPort",
    ] as CFArray)
    if let src = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
    }
} else {
    tlog("SCDynamicStoreCreate failed — wifi pill will not update")
}

// location: the network name's price, same responsible-process rules
locationGate.start()


// waking clears the gamma table, so the shade has to be reasserted
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
) { _ in applyShade() }

// media: Music broadcasts every state change, and the payload carries
// the track, so the pill repaints without asking. Launch and quit are
// the one pair it cannot announce.
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(musicNotification), object: nil, queue: .main
) { note in updateMedia(from: note.userInfo) }

for event in [NSWorkspace.didLaunchApplicationNotification,
              NSWorkspace.didTerminateApplicationNotification] {
    NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == musicBundleID else { return }
        if event == NSWorkspace.didLaunchApplicationNotification { primeMedia() } else { updateMedia() }
    }
}

// clock and weather have no publisher to listen to. The clock ticks on
// the minute boundary rather than every 60 s from launch, so it never
// shows a stale minute.
func scheduleClock() {
    updateClock()
    refreshPowerMode()
    let now = Date()
    let nextMinute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0),
                                               matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
    DispatchQueue.main.asyncAfter(deadline: .now() + max(1, nextMinute.timeIntervalSinceNow)) { scheduleClock() }
}
scheduleClock()

// Some providers run only while their pill is on the bar. A reload starts
// the provider of a pill that comes back. A provider is never stopped:
// one that runs for a hidden pill costs little.
var startedProviders: Set<String> = []

func startProviders() {
    func once(_ pill: String, _ start: () -> Void) {
        if rightOrder.contains(pill), startedProviders.insert(pill).inserted { start() }
    }
    // bluetooth: gated on the privacy grant, which the watcher also needs
    once("bluetooth") { bluetoothWatcher.start() }
    // signal strength publishes no change
    once("status") { Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in updateStatus() } }
    once("weather") {
        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in if !screenLocked { updateWeather() } }
        updateWeather()
    }
}

// --- go -------------------------------------------------------------------

model.frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
// startup only: from here the workspace-bar stream keeps it
model.focused = omniwmActive()
    ? ((omniQuery("workspaces", ["--focused", "--fields", "raw-name"])?["workspaces"]
        as? [[String: Any]])?.first?["rawName"] as? String ?? "")
    : ""
applySurfaces(monitorIDs())
guard !surfaces.isEmpty else {
    FileHandle.standardError.write("omacchiato-bar: no screen to draw on\n".data(using: .utf8)!)
    exit(1)
}
apply(fetchSnapshot()) // blocking is fine here: the run loop has not started
rightItems["activity"] = BarItem(icon: "󰍛", iconColor: palette.accent)
applyShade() // restore the level this machine was left at
updateBattery()
// low power mode publishes a change; high power mode does not, so it is
// re-read on the same signal rather than on a timer
for name in [NSNotification.Name.NSProcessInfoPowerStateDidChange,
             ProcessInfo.thermalStateDidChangeNotification] {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        refreshPowerMode()
        updateStatus()
    }
}
refreshPowerMode()
updateBrightness()
updateWifi()
set("menubar") { $0.icon = "\u{F003B}" }
startProviders()
startPlugins()
watchConfig()
repaint()
primeMedia()
startOmniWatch() // a no-op until OmniWM runs; the WM observer starts it then
tlog("omacchiato-bar up on " + surfaces.map { "\($0.screen.localizedName)=m\($0.monitorID)\($0.notched ? " (notched)" : "")" }.joined(separator: ", "))
app.run()
