import AppKit
import IOKit.pwr_mgt
// swiftc builds helper/ui into this module, and SwiftPM builds it as its own.
import SwiftUI
#if canImport(StatusGauge)
import KeepAwakePanel
#endif

// --- keep awake ---------------------------------------------------------------
// `omacchiato-keep-awake on | off | toggle | for <minutes>` writes the state
// file, and the bar holds the Mac awake while the file reads on. The bar
// holds the assertion, so a crash of the bar ends keep awake.

enum KeepAwake: Equatable {
    case off
    case on(until: Date?)
}

// Keep in sync with STATE in bin/omacchiato-keep-awake.
let keepAwakeStateFile = NSString(string: "~/.local/state/omacchiato/keep-awake").expandingTildeInPath

// Keep in sync with read_state() in bin/omacchiato-keep-awake.
func keepAwakeNow(state: String, now: Date) -> KeepAwake {
    let text = state.trimmingCharacters(in: .whitespacesAndNewlines)
    if text == "on" { return .on(until: nil) }
    guard let seconds = Double(text) else { return .off }
    let until = Date(timeIntervalSince1970: seconds)
    return until > now ? .on(until: until) : .off
}

func keepAwakeDetail(_ state: KeepAwake, reason: String?, timeZone: TimeZone = .current,
                     locale: Locale = .current) -> String {
    switch state {
    case .off: return reason ?? "Turned off"
    case .on(nil): return "Until turned off"
    case .on(let until?):
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.timeStyle = .short
        return "Until " + f.string(from: until)
    }
}

// Seconds between jiggles, from `keep_awake_jiggle` in minutes. nil is off.
func jiggleInterval(_ mode: String?) -> TimeInterval? {
    guard let mode else { return 60 }
    if mode == "off" { return nil }
    guard let minutes = Double(mode) else { return 60 }
    return minutes > 0 ? minutes * 60 : nil
}

// A mouse-moved event at the pointer's own position resets the idle time
// that Teams and Slack read, and the pointer does not move. It posts only
// after 30 s idle, so it never lands in the middle of a drag.
func jiggle() {
    guard !screenLocked,
          CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) >= 30,
          let at = CGEvent(source: nil)?.location else { return }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

// `keep_awake_battery` is the lowest percent on battery, 20 by default.
func batteryEndsKeepAwake(percent: Int, onAC: Bool, mode: String?) -> Bool {
    guard !onAC, mode != "off" else { return false }
    return percent <= (mode.flatMap { Int($0) } ?? 20)
}

// The battery pill calls this on each power source change.
func checkKeepAwakeBattery(percent: Int, onAC: Bool) {
    guard keepAwakeShown != nil, keepAwakeShown != .off,
          batteryEndsKeepAwake(percent: percent, onAC: onAC, mode: pillModes["keep_awake_battery"]) else { return }
    writeKeepAwake("off")
    applyKeepAwake(reason: "Battery at \(percent)%")
}

// Lid closed: `pmset -a disablesleep 1` through the rule that
// omacchiato-lid-rule installs. A marker file says the bar set it, so the
// bar undoes only its own setting, also after a crash.
let lidMarker = NSString(string: "~/.local/state/omacchiato/keep-awake-lid").expandingTildeInPath

// true sets disablesleep 1, false sets 0, nil leaves it.
func lidAction(on: Bool, mode: String?, setByBar: Bool) -> Bool? {
    let want = on && mode != "off"
    if want && !setByBar { return true }
    if !want && setByBar { return false }
    return nil
}

func applyLid(on: Bool) {
    let setByBar = FileManager.default.fileExists(atPath: lidMarker)
    guard let disable = lidAction(on: on, mode: pillModes["keep_awake_lid"], setByBar: setByBar) else { return }
    if disable { FileManager.default.createFile(atPath: lidMarker, contents: nil) }
    DispatchQueue.global(qos: .userInitiated).async {
        let result = execute("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disable ? "1" : "0"], timeout: 10)
        DispatchQueue.main.async {
            if result.status != 0 {
                tlog("keep awake: pmset disablesleep failed, so no lid rule? Run omacchiato-lid-rule install")
                if disable { try? FileManager.default.removeItem(atPath: lidMarker) }
            } else if !disable {
                try? FileManager.default.removeItem(atPath: lidMarker)
            }
        }
    }
}

var keepAwakeAssertions: [IOPMAssertionID] = []
var keepAwakeJiggle: Timer?
var keepAwakeShown: KeepAwake?
var keepAwakeHeldDisplay = false
var keepAwakeEnd: Timer?

func readKeepAwake() -> KeepAwake {
    keepAwakeNow(state: (try? String(contentsOfFile: keepAwakeStateFile, encoding: .utf8)) ?? "", now: Date())
}

func writeKeepAwake(_ text: String) {
    try? (text + "\n").write(toFile: keepAwakeStateFile, atomically: true, encoding: .utf8)
}

func applyKeepAwake(reason: String? = nil) {
    let state = readKeepAwake()
    // no HUD for the state the bar finds at startup
    if let shown = keepAwakeShown, shown != state, pillModes["keep_awake_hud"] != "off" {
        showHUD(AnyView(KeepAwakeOSD(on: state != .off, detail: keepAwakeDetail(state, reason: reason))))
    }
    keepAwakeShown = state
    let display = pillModes["keep_awake_display"] == "on"
    if state == .off || display != keepAwakeHeldDisplay {
        keepAwakeAssertions.forEach { IOPMAssertionRelease($0) }
        keepAwakeAssertions = []
    }
    if state != .off, keepAwakeAssertions.isEmpty {
        let name = "Omacchiato: keep the Mac awake" as CFString
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep]
        if display { types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep) }
        for type in types {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name, &id)
                == kIOReturnSuccess {
                keepAwakeAssertions.append(id)
            } else {
                tlog("keep awake: no \(type) assertion")
            }
        }
        keepAwakeHeldDisplay = display
    }
    applyLid(on: state != .off)
    keepAwakeJiggle?.invalidate()
    keepAwakeJiggle = nil
    if state != .off, let every = jiggleInterval(pillModes["keep_awake_jiggle"]) {
        keepAwakeJiggle = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in jiggle() }
    }
    keepAwakeEnd?.invalidate()
    keepAwakeEnd = nil
    if case .on(let until?) = state {
        keepAwakeEnd = Timer.scheduledTimer(withTimeInterval: max(0, until.timeIntervalSinceNow), repeats: false) { _ in
            writeKeepAwake("off")
            applyKeepAwake(reason: "Timer ended")
        }
    }
    // the pill reads the same file, so it can show the change now
    for plugin in barPlugins where (plugin.command.split(separator: " ").first.map(String.init) ?? "")
        .hasSuffix("omacchiato-keep-awake") {
        refreshPlugin(plugin.name)
    }
}

func startKeepAwake() {
    let folder = (keepAwakeStateFile as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    var last = try? String(contentsOfFile: keepAwakeStateFile, encoding: .utf8)
    // The script writes a temp file and renames it, which only the folder
    // sees. Other files in the folder change too, so compare the text.
    watch(folder, create: false) {
        let text = try? String(contentsOfFile: keepAwakeStateFile, encoding: .utf8)
        guard text != last else { return }
        last = text
        applyKeepAwake()
    }
    applyKeepAwake()
}
