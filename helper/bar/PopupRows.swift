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
import BluetoothPanel
import BarPills
import DisplayPanel
import SoundPanel
import AIUsagePanel
import CalendarPanel
import MenuBarPanel
import PRPanel
import RowsPanel
import StatusPanel
import ThemePanel
import WeatherPanel
#endif

// --- built-in popups: the reports behind their panels ----------------------

func displayReport() -> DisplayReport {
    var value: Float = 0
    let brightness = DSGetBrightness(builtinDisplayID(), &value) == 0 ? Double(value) : nil
    // Read fresh on each build: the tile shows what CoreBrightness says now.
    // A Mac without Night Shift gets no tile, not a wrong one.
    let ns = blueLightStatus()
    return DisplayReport(brightness: brightness, shade: shade,
                         nightShift: ns?.available.boolValue == true ? ns?.enabled.boolValue : nil)
}

let displayActions: DisplayActions = {
    var actions = DisplayActions()
    actions.setBrightness = { fraction in
        _ = DSSetBrightness(builtinDisplayID(), Float(fraction))
        updateBrightness()
    }
    actions.setShade = { setShade($0) }
    actions.toggleNightShift = {
        setNightShift(!(blueLightStatus()?.enabled.boolValue ?? false))
        refreshPopup()
    }
    actions.openSettings = {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
        closePopup()
    }
    return actions
}()

func audioTransport(_ id: AudioDeviceID) -> SoundReport.Transport {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var kind: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &kind) == noErr else { return .other }
    switch kind {
    case kAudioDeviceTransportTypeBuiltIn: return .builtIn
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
    case kAudioDeviceTransportTypeAirPlay: return .airPlay
    case kAudioDeviceTransportTypeUSB: return .usb
    case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
    default: return .other
    }
}

func soundReport() -> SoundReport? {
    guard let v = readVolume() else { return nil }
    let current = defaultOutputDevice()
    return SoundReport(volume: Double(v.percent) / 100, muted: v.muted,
                       outputs: audioOutputDevices().map {
                           .init(id: $0.id, name: $0.name, transport: audioTransport($0.id), current: $0.id == current)
                       })
}

let soundActions: SoundActions = {
    var actions = SoundActions()
    actions.setVolume = { fraction in
        writeVolume(Int((fraction * 100).rounded()))
        updateVolume()
    }
    actions.toggleMute = { toggleMute(); updateVolume(); refreshPopup() }
    actions.selectOutput = { id in
        setDefaultOutputDevice(id)
        updateVolume()
        refreshPopup()
    }
    actions.openSettings = {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        closePopup()
    }
    return actions
}()

func bluetoothKind(_ device: IOBluetoothDevice) -> BluetoothReport.Kind {
    let minor = device.deviceClassMinor
    switch device.deviceClassMajor {
    case 0x01: return .computer
    case 0x02: return .phone
    case 0x04: return .audio
    case 0x05:
        // Peripheral minor class: 0x10 keyboard, 0x20 pointing, low bits 0x01 joystick, 0x02 gamepad.
        if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return .gamepad }
        if minor & 0x10 != 0 { return .keyboard }
        if minor & 0x20 != 0 { return (device.name ?? "").contains("Trackpad") ? .trackpad : .mouse }
        return .other
    default: return .other
    }
}

func bluetoothReport() -> BluetoothReport {
    guard CBCentralManager.authorization == .allowedAlways else { return BluetoothReport(allowed: false) }
    let devices = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).map { d in
        BluetoothReport.Device(id: d.addressString ?? "", name: d.name ?? d.addressString ?? "Device",
                               kind: bluetoothKind(d), connected: d.isConnected())
    }
    return BluetoothReport(devices: devices)
}

let bluetoothActions: BluetoothActions = {
    var actions = BluetoothActions()
    actions.toggle = { address in
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        // Connecting is async; a device out of range can block for seconds.
        if device.isConnected() { device.closeConnection() } else { device.openConnection(bluetoothWatcher) }
        updateBluetooth()
        refreshPopup()
    }
    actions.openSettings = {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        closePopup()
    }
    return actions
}()

func batteryInfo() -> StatusReport.Battery? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
          let source = list.first,
          let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
    else { return nil }
    let raw = smartBattery()
    let data = raw["BatteryData"] as? [String: Any] ?? [:]
    let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
    let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
    let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    // this key arrives as a number, not a boolean, so a Bool cast alone
    // reads every charging battery as charged
    let charging = (d[kIOPSIsChargingKey] as? Bool) ?? ((d[kIOPSIsChargingKey] as? Int) == 1)
    var b = StatusReport.Battery(percent: max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur,
                                 charging: charging, onAC: onAC)
    // 65535 is the "not known yet" answer, which arrives whenever the
    // rate has just changed
    let minutes = onAC ? (d[kIOPSTimeToFullChargeKey] as? Int ?? -1) : (d[kIOPSTimeToEmptyKey] as? Int ?? -1)
    if minutes > 0 && minutes < 65535 { b.minutesLeft = minutes }
    applyHighPowerMode(readHighPowerMode())
    b.mode = powerModeName()
    switch ProcessInfo.processInfo.thermalState {
    case .fair: b.thermal = "fair"
    case .serious: b.thermal = "serious"
    case .critical: b.thermal = "critical"
    default: break // the ordinary state is not worth a row
    }
    // amperage is negative while discharging: the sign is the direction,
    // and the pill only wants the size
    if let mv = raw["Voltage"] as? Int, let ma = raw["Amperage"] as? Int, ma != 0 {
        b.watts = Double(mv) * Double(abs(ma)) / 1_000_000
    }
    b.adapterWatts = (raw["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
    // Apple rounds this to a whole 100% for a long while; the ratio is
    // the number that actually moves
    if let design = data["DesignCapacity"] as? Int, let full = data["FullChargeCapacity"] as? Int, design > 0 {
        b.health = Int((Double(full) / Double(design) * 100).rounded())
    }
    b.cycles = raw["CycleCount"] as? Int
    return b
}

func openBatterySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
    closePopup()
}

// The system menu that the hidden native menu bar carries, plus the two
// omacchiato actions. "Reload Bar" has no counterpart on purpose: there
// is no config to reread, the theme is watched, and a row that does
// nothing is worse than no row.
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
        // pmset displaysleepnow only darkens the screen. Whether that locks
        // it depends on the screenLock delay, so it usually does not lock.
        PopupRow(text: "Lock Screen",
                 action: run("\(NSHomeDirectory())/.local/bin/omacchiato-helper", ["lock"])),
        PopupRow(text: "Sleep", action: run("/usr/bin/pmset", ["sleepnow"])),
        PopupRow(text: "Restart…", action: systemEvents("restart")),
        PopupRow(text: "Shut Down…", action: systemEvents("shut down")),
        PopupRow(text: "Omacchiato Settings…", dim: true, action: showSettings),
    ]
}

func popupRows(for name: String) -> [PopupRow] {
    switch name {
    case "apple": return appleMenuRows()
    case "appmenu": return appMenuRows()
    default:
        return foldSections(name, pluginRows[name] ?? [])
    }
}
