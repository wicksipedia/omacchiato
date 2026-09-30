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

var keepAwakeAssertions: [IOPMAssertionID] = []
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
