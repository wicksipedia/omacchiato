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

// --- row popups: the menus drawn by RowsPanel ------------------------------

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
    // Read fresh on each build: the row shows what CoreBrightness says now.
    // A Mac without Night Shift gets no row, not a wrong one.
    if let ns = blueLightStatus(), ns.available.boolValue {
        let on = ns.enabled.boolValue
        rows.append(PopupRow(text: "Night Shift \(on ? "On" : "Off")", action: {
            setNightShift(!on)
            refreshPopup()
        }))
    }
    rows.append(PopupRow(text: "Display Settings…", dim: true, action: {
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
    // Lists output devices with the current one marked. `omacchiato-helper
    // audio` offers the same list; this reads it in process instead.
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
    rows.append(PopupRow(text: "Sound Settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        closePopup()
    }))
    return rows
}

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

func batteryRows() -> [PopupRow] {
    var rows: [PopupRow] = []
    let b = batteryInfo()
    if let b {
        rows.append(PopupRow(text: "Battery", detail: "\(b.percent)%", hero: true,
                             inlineBar: Double(b.percent) / 100, tint: b.low ? .systemRed : nil))
        rows.append(PopupRow(text: b.charging ? "charging" : (b.onAC ? "charged, on AC" : "on battery"),
                             detail: b.timeText ?? ""))
    }
    rows.append(PopupRow(separator: true))
    if let mode = b?.mode { rows.append(PopupRow(text: "Mode", detail: mode)) }
    if let thermal = b?.thermal { rows.append(PopupRow(text: "Thermal", detail: thermal)) }
    if let watts = b?.watts {
        rows.append(PopupRow(text: b?.charging == true ? "charging at" : "draw", detail: String(format: "%.1f W", watts)))
    }
    if let adapter = b?.adapterWatts { rows.append(PopupRow(text: "Adapter", detail: "\(adapter) W")) }
    rows.append(PopupRow(separator: true))
    if let health = b?.health {
        let verdict = health >= 90 ? "" : (health >= 80 ? "  fair" : "  worn")
        rows.append(PopupRow(text: "Health", detail: "\(health)%\(verdict)"))
    }
    if let cycles = b?.cycles { rows.append(PopupRow(text: "Cycles", detail: "\(cycles)")) }
    rows.append(PopupRow(separator: true))
    rows.append(PopupRow(text: "Battery Settings…", dim: true, action: openBatterySettings))
    return rows
}

func wifiRows() -> [PopupRow] {
    let w = wifiInfo()
    var rows: [PopupRow] = [PopupRow(text: w.ssid ?? "wi-fi", hero: true)]
    rows.append(PopupRow(text: "IP \(w.ip ?? "none")"))
    if let router = w.router { rows.append(PopupRow(text: "Router \(router)")) }
    if let rssi = w.rssi {
        let verdict = rssi >= -55 ? "excellent" : (rssi >= -67 ? "good" : (rssi >= -75 ? "fair" : "weak"))
        rows.append(PopupRow(text: "Signal \(rssi) dBm  \(verdict)"))
    }
    // The Link row answers two questions: how fast, and how safe.
    let link = [w.rate.map { "\($0) Mbps" }, w.security].compactMap { $0 }
    if !link.isEmpty { rows.append(PopupRow(text: "Link " + link.joined(separator: "  "))) }
    if let channel = w.channel {
        rows.append(PopupRow(text: (["channel \(channel)"] + [w.band, w.width].compactMap { $0 }).joined(separator: "  ")))
    }
    rows.append(PopupRow(separator: true))
    rows.append(PopupRow(text: "Networks", dim: true))
    // The current network leads the list with a tick, matching the macOS
    // menu. A lock on every row would say nothing, so only an open
    // network gets a label.
    if let current = w.ssid, !current.isEmpty {
        rows.append(PopupRow(icon: "\u{F012C}", text: current, highlight: true, iconTint: palette.accent))
    }
    for network in w.networks {
        rows.append(PopupRow(icon: wifiStrengthGlyph(network.rssi), text: network.ssid,
                             detail: network.open ? "open" : "", action: { joinWifi(network.ssid) }))
    }
    if w.networks.isEmpty, w.scanning { rows.append(PopupRow(text: "Looking…", dim: true)) }
    if !w.phones.isEmpty {
        rows.append(PopupRow(separator: true))
        rows.append(PopupRow(text: "Phones", dim: true))
        for phone in w.phones {
            rows.append(PopupRow(icon: "\u{F011C}", text: phone.name,
                                 detail: phone.connected ? "connected" : phone.battery.map { "\($0)%" } ?? "",
                                 highlight: phone.connected,
                                 action: phone.connected ? nil : { startHotspot(named: phone.name) }))
        }
    }
    rows.append(PopupRow(text: "Network Settings…", dim: true, action: openNetworkSettings))
    return rows
}

func bluetoothRows() -> [PopupRow] {
    var rows: [PopupRow] = [PopupRow(text: "Bluetooth", hero: true)]
    guard CBCentralManager.authorization == .allowedAlways else {
        rows.append(PopupRow(text: "No permission in this launch context", dim: true))
        return rows
    }
    for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] {
        let name = device.name ?? device.addressString ?? "device"
        rows.append(PopupRow(icon: device.isConnected() ? "󰂱" : "󰂯", text: name,
                             highlight: device.isConnected(),
                             action: {
                                 // Connecting is async; a device out of range can block for seconds.
                                 if device.isConnected() { device.closeConnection() } else { device.openConnection(bluetoothWatcher) }
                                 updateBluetooth()
                                 refreshPopup()
                             }))
    }
    rows.append(PopupRow(text: "Bluetooth Settings…", dim: true, action: {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        closePopup()
    }))
    return rows
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
        PopupRow(text: "Theme", detail: currentThemeName(), dim: true,
                 action: run("\(NSHomeDirectory())/.local/bin/theme-next", [])),
    ]
}

func popupRows(for name: String) -> [PopupRow] {
    switch name {
    case "apple": return appleMenuRows()
    case "battery": return batteryRows()
    case "brightness": return brightnessRows()
    case "volume": return volumeRows()
    case "wifi": return wifiRows()
    case "bluetooth": return bluetoothRows()
    case "appmenu": return appMenuRows()
    default:
        return foldSections(name, pluginRows[name] ?? [])
    }
}
