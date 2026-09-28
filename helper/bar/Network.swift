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

// --- personal hotspot ------------------------------------------------------
// The macOS wi-fi menu's phone list does not come from CoreWLAN: airportd
// gates tether calls behind entitlements only Apple's wi-fi agent holds.
// sharingd answers the same question over XPC and needs no grant. This is
// a private API, so every step fails quietly; a renamed class just leaves
// the popup as it was.
final class HotspotWatcher: NSObject {
    @objc func session(_ session: AnyObject, updatedFoundDevices devices: [AnyObject]) {
        DispatchQueue.main.async {
            hotspotDevices = devices.compactMap { $0 as? NSObject }
            if openPopup == "wifi" || openPopup == "status" { refreshPopup() }
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

// The phone turns on its hotspot, then answers with the network's name
// and password. Joining it is still this Mac's job. Both arguments are
// plain strings, whatever the block's type encoding claims, so this
// never sends them a message.
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
// A scan blocks for seconds, so it runs off the main thread. The popup
// redraws when the answer lands. macOS also throttles scans, and the
// popup opens often, so one answer serves for 20 s.
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
            if openPopup == "wifi" || openPopup == "status" { refreshPopup() }
        }
    }
}

func wifiStrengthGlyph(_ rssi: Int) -> String {
    if rssi >= -60 { return "\u{F0928}" }
    if rssi >= -70 { return "\u{F0925}" }
    if rssi >= -80 { return "\u{F0922}" }
    return "\u{F091F}"
}

// networksetup takes the password from the system keychain, so a known
// network joins in one click. Any other case prints a line. macOS asks
// for the password better than a popup row can.
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

// Reading this also starts a wi-fi scan and the hotspot browse. Their
// answers refresh the open popup.
func wifiInfo() -> StatusReport.WiFi {
    let interface = CWWiFiClient.shared().interface()
    var w = StatusReport.WiFi(on: interface?.powerOn() ?? false)
    // The SSID is location-sensitive: reading it needs the Location grant
    // and a bundled binary. Measured on macOS 26.3: an unbundled build
    // reads nil even when authorised. This is why the bar ships inside a
    // .app; see install.sh.
    w.ssid = interface?.ssid()
    let net = wifiIPv4()
    w.ip = net.ip.isEmpty ? nil : net.ip
    w.router = net.router.isEmpty ? nil : net.router
    if let rssi = interface?.rssiValue(), rssi != 0 { w.rssi = rssi }
    if let rate = interface?.transmitRate(), rate > 0 { w.rate = Int(rate) }
    if let sec = interface?.security() { w.security = securityName(sec) }
    if let channel = interface?.wlanChannel() {
        // a bare channel number means nothing to most people; the band
        // is what says "you are on the fast radio"
        w.channel = channel.channelNumber
        switch channel.channelBand {
        case .band2GHz: w.band = "2.4 GHz"
        case .band5GHz: w.band = "5 GHz"
        case .band6GHz: w.band = "6 GHz"
        default: break
        }
        switch channel.channelWidth {
        case .width20MHz: w.width = "20 MHz"
        case .width40MHz: w.width = "40 MHz"
        case .width80MHz: w.width = "80 MHz"
        case .width160MHz: w.width = "160 MHz"
        default: break
        }
    }
    scanWifi()
    w.scanning = wifiScanning
    w.networks = wifiNetworks.filter { $0.ssid != w.ssid }.prefix(6).compactMap { network in
        network.ssid.map { .init(ssid: $0, rssi: network.rssiValue, open: network.supportsSecurity(.none)) }
    }
    startHotspotBrowse()
    w.phones = hotspotDevices.map { device in
        let name = device.value(forKey: "deviceName") as? String ?? "phone"
        // an iPhone hotspot takes the name of the phone
        return .init(name: name, battery: (device.value(forKey: "batteryLife") as? Double).map { Int($0) },
                     connected: name == w.ssid)
    }
    return w
}

func openNetworkSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
    closePopup()
}

func toggleWifiPower() {
    guard let interface = CWWiFiClient.shared().interface() else { return }
    try? interface.setPower(!interface.powerOn())
    updateWifi()
}

func startHotspot(named name: String) {
    if let device = hotspotDevices.first(where: { $0.value(forKey: "deviceName") as? String == name }) {
        startHotspot(device)
    }
}

// SCDynamicStore answers both address and router in process, with no
// ipconfig fork on the click path. The router matters most when the
// network misbehaves.
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

// The cable the Mac's traffic goes over, if any. A cable counts when
// it is the primary interface, or when it has an address and wi-fi has
// none, because a VPN can take the primary slot.
func ethernetInfo() -> StatusReport.Ethernet? {
    guard let store = SCDynamicStoreCreate(nil, "omacchiato-bar-ethernet" as CFString, nil, nil),
          let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
    let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
    let primary = global?["PrimaryInterface"] as? String
    func address(_ bsd: String) -> String? {
        let v = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(bsd)/IPv4" as CFString) as? [String: Any]
        return (v?["Addresses"] as? [String])?.first { !$0.hasPrefix("169.254.") }
    }
    let wifiUp = address(wifiDevice) != nil
    for interface in all where SCNetworkInterfaceGetInterfaceType(interface) == kSCNetworkInterfaceTypeEthernet {
        guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?, bsd != wifiDevice,
              let ip = address(bsd), primary == bsd || !wifiUp else { continue }
        let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? "Ethernet"
        return .init(name: name, ip: ip, router: primary == bsd ? global?["Router"] as? String : nil)
    }
    return nil
}

// Name only what is certain: the generic personal/enterprise cases cover
// several generations, and guessing one would be a lie.
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
