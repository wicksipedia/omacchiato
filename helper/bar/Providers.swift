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

// --- clock (no publisher, so poll every minute)
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

// The clock names the next event from 10 minutes before it until 5
// minutes after it starts. A click opens its meeting link.
var soonMeetingLink: URL?

func soonLabel(start: Date, allDay: Bool, now: Date) -> String? {
    guard !allDay else { return nil }
    let left = start.timeIntervalSince(now)
    guard left > -5 * 60, left <= 10 * 60 else { return nil }
    return left <= 0 ? "now" : "in \(Int((left / 60).rounded(.up)))m"
}

// A link that opens the event in Calendar. A repeating event shares one
// identifier, so the link also names this occurrence's start time, in UTC.
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

// The event's own URL if it has one, else the first video call link found
// in the location or the notes.
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
// IOPS carries the charge and time left. Health, cycles, and the live
// power draw exist only in the registry entry.
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

// High power mode has no public API. pmset costs about 13ms: fine for a
// notification, too slow for a timer, so cache the value.
var highPowerMode = false

func readHighPowerMode() -> Bool {
    shell("/usr/bin/pmset", ["-g"])
        .split(separator: "\n")
        .first { $0.contains("powermode") }?
        .split(separator: " ").last == "2"
}

// Only low power mode publishes a change, so leaving high power for
// automatic is a silent transition. The minute tick catches that case;
// the notification just makes low power immediate.
// Never assign highPowerMode directly. The icon redraws only when this
// function sees a change, so a direct write leaves the pill stale.
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
    defer { updateStatus() }
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
    else { return }
    for source in list {
        guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int else { continue }
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        // Same steps and glyphs as macOS's own battery icon.
        var icon = "󰂃", color = palette.red
        switch pct {
        case 90...: icon = "󰁹"; color = palette.green
        case 60..<90: icon = "󰂀"; color = palette.label
        case 30..<60: icon = "󰁾"; color = palette.label
        case 10..<30: icon = "󰁻"; color = palette.yellow
        default: break
        }
        if charging { icon = "󰂄"; color = palette.green }
        // A leaf or a speedometer beside the cell shows the power mode
        // without opening anything.
        let mode = ProcessInfo.processInfo.isLowPowerModeEnabled ? "\u{F032A}"
            : (highPowerMode ? "\u{F04C5}" : "")
        // `battery = time`: the icon alone on AC power. On battery, show
        // whole hours, or minutes under an hour. 65535 means the estimate
        // is not ready yet.
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
func defaultOutputDevice() -> AudioDeviceID { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
func defaultInputDevice() -> AudioDeviceID { defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

// A device with no mute switch is muted by its input volume being taken to
// zero instead. Reading only the switch would miss that.
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

// The pill exists only to flag a muted mic, so it draws only then.
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
        // No master channel on this device, so average the stereo pair.
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

// The output devices the volume popup lists. Matches the enumeration
// helper/main.swift does for `omacchiato-helper audio`, without the round trip.
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
        // Output-capable only. A device with no output streams is a mic.
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
    // `volume = muted` makes it the mic pill's twin: draw only while the
    // output is silent.
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

// --- shade (dims below the hardware minimum, with no overlay window) -----
// Scales display gamma instead of floating a translucent window like
// QuickShade: no window in the z-order, it still works over fullscreen
// apps, and screenshots come out normal.
// Gamma set by a process resets when that process exits, so a crash or an
// uninstall cannot leave the screen stuck dark.
// Unlike DisplayServices, this also dims external displays, which have no
// backlight API without DDC.
let shadeFile = "\(NSHomeDirectory())/.local/state/omacchiato/shade"
let shadeFloor: Double = 0.15 // never dims below this fraction of output

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
        set("brightness") { $0.drawing = false } // hide it rather than show a wrong value
        return
    }
    let pct = Int((value * 100).rounded())
    // Shade drops the reading below zero: past what the backlight can
    // reach. The moon icon shows which side of zero it is on.
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
// macOS treats the SSID as location data. It needs both this grant and a
// bundled binary: an unbundled build reads nil even with authorization
// held, services on, and updates running. A bundled build reads the name
// as soon as the answer lands. Nothing here reads a coordinate; the
// authorization itself is the API, and the manager exists only to request it.
// Gated like Bluetooth: TCC checks the responsible process, so only the
// launchd-started bar may prompt. Running it by hand stays quiet.
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var managed: Bool { ProcessInfo.processInfo.environment["OMACCHIATO_MANAGED"] != nil }

    func start() {
        manager.delegate = self
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            updateWifi() // the name is readable now, though the pill may predate it
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

    // The name appears as soon as the answer lands: no restart, and no
    // polling a permission that already publishes.
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        tlog("location: authorization now \(m.authorizationStatus.rawValue)")
        updateWifi()
        if rightOrder.contains("weather") { updateWeather() }
    }

    private var located: [(CLLocationCoordinate2D?) -> Void] = []

    // One position for the weather. Without the grant, or on failure, the
    // answer is nil, and wttr.in guesses the place from the IP address.
    func locate(_ done: @escaping (CLLocationCoordinate2D?) -> Void) {
        guard [.authorizedAlways, .authorized].contains(manager.authorizationStatus) else { return done(nil) }
        located.append(done)
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestLocation()
    }

    private func answer(_ coordinate: CLLocationCoordinate2D?) {
        let waiting = located
        located = []
        waiting.forEach { $0(coordinate) }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        answer(locations.last?.coordinate)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        tlog("location: \(error.localizedDescription)")
        answer(nil)
    }
}
let locationGate = LocationGate()

// --- night shift (CBBlueLightClient publishes) ---------------------------
// Reaches private CoreBrightness by reflection, the same way
// omacchiato-helper does. It has a publisher: setStatusNotificationBlock
// fires on every change, whoever made it: the schedule, Control Center,
// System Settings, or us.
struct BlueLightStatus {
    // `active` measured true in every state tested: on, off, inside and
    // outside the schedule window. The row reads `enabled` instead, since
    // that is the field setEnabled: actually changes.
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

// CoreBrightness does not retain the block, so this must, or it is freed.
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
            // Log which field a schedule boundary changes. Useful when
            // checking the morning after.
            tlog("night shift changed: enabled=\(s.enabled.boolValue) "
                + "active=\(s.active.boolValue) mode=\(s.mode)")
            if openPopup == "brightness" { refreshPopup() }
        }
    }
    nightShiftBlock = block
    typealias SetFn = @convention(c) (AnyObject, Selector, Any) -> Void
    unsafeBitCast(method_getImplementation(m), to: SetFn.self)(bl.client, sel, block)
}

// --- wifi (SCDynamicStore publishes; SSID needs a subprocess, so fetch
// off-main and only when the network actually changed)
var wifiDevice = CWWiFiClient.shared().interface()?.interfaceName ?? "en0"

func updateWifi() {
    defer { updateStatus() }
    let powered = CWWiFiClient.shared().interface()?.powerOn() ?? false
    guard powered else {
        set("wifi") { $0.icon = "󰖪"; $0.iconColor = nil; $0.label = "off" }
        return
    }
    // The network name lives in the popup, not the pill. A 17-character
    // SSID is about 150pt wide, and the right cluster is right-aligned, so
    // it would push the far end under the notch on a notched display. The
    // icon just says connected; click it to see to what.
    set("wifi") { $0.icon = "󰖩"; $0.iconColor = nil; $0.label = "" }
}

// --- bluetooth (IOBluetooth publishes connect/disconnect)
// IOBluetooth aborts the process outright (SIGABRT, no exception to
// catch) if touched without the Bluetooth privacy grant, exit code 134
// with an empty log, as watcher.swift also found. So the grant is gated
// on CBCentralManager.authorization, which never itself prompts, and the
// pill stays hidden until it is held. The binary needs helper/bar-info.plist
// for the usage string, or the prompt cannot even appear.
func updateBluetooth() {
    defer { updateStatus() }
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
// so they need a real object to aim at. CoreBluetooth's delegate tells
// this class when the grant has landed.
final class BluetoothWatcher: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var classicStarted = false

    // TCC judges CBCentralManager creation by the responsible process, not
    // this binary. Only the launchd-started process is responsible for
    // itself and may prompt; started from a shell, it just aborts. The
    // plist sets OMACCHIATO_MANAGED so a manual test run stays safe instead
    // of crashing.
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

// --- status (battery and wi-fi in one gauge)

func updateStatus() {
    guard rightOrder.contains("status") else { return }
    var battery = 0.0, charging = false
    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let source = (IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef])?.first,
       let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] {
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        battery = max > 0 ? Double(cur) / Double(max) : 0
        charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    }
    let interface = CWWiFiClient.shared().interface()
    let wifi = interface?.powerOn() == true ? wifiLevel(rssi: interface?.rssiValue() ?? 0) : nil
    let hotspot = wifi != nil && (wifiIPv4().router == "172.20.10.1" || hotspotDevices.contains {
        $0.value(forKey: "deviceName") as? String == interface?.ssid()
    })
    let link: StatusGauge.Link = ethernetInfo() != nil ? .ethernet : (hotspot ? .hotspot : .wifi)
    set("status") { $0.gauge = StatusGauge(battery: battery, charging: charging, wifi: wifi, link: link) }
}

func statusReport() -> StatusReport {
    StatusReport(battery: batteryInfo(), wifi: wifiInfo(), ethernet: ethernetInfo())
}

let statusActions: StatusActions = {
    var actions = StatusActions()
    actions.join = joinWifi
    actions.hotspot = startHotspot(named:)
    actions.toggleWifi = { toggleWifiPower(); refreshPopup() }
    actions.batterySettings = openBatterySettings
    actions.networkSettings = openNetworkSettings
    return actions
}()

// --- weather (no publisher; wttr.in, refreshed on a long timer)
// One j1 fetch feeds both the pill and its popup.

var weatherReport: WeatherReport?

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

// Two decimals put the place within about a kilometre, all a forecast
// needs, so the exact position never leaves the Mac.
func weatherURL(_ coordinate: CLLocationCoordinate2D?) -> URL {
    guard let c = coordinate else { return URL(string: "https://wttr.in/?format=j1")! }
    return URL(string: String(format: "https://wttr.in/%.2f,%.2f?format=j1", c.latitude, c.longitude))!
}

func updateWeather() {
    locationGate.locate(fetchWeather)
}

func fetchWeather(_ coordinate: CLLocationCoordinate2D?) {
    var request = URLRequest(url: weatherURL(coordinate))
    request.timeoutInterval = 15
    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data, let report = WeatherReport(j1: data) else { return }
        DispatchQueue.main.async {
            weatherReport = report
            set("weather") {
                $0.icon = weatherEmoji(report.code, night: report.night)
                $0.label = "\(report.temp)°C"
            }
            if openPopup == "weather" { refreshPopup() }
        }
    }.resume()
}
