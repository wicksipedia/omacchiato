import SwiftUI

extension StatusReport {
    public static let networks: [Network] = [
        Network(ssid: "Home-5G", rssi: -48),
        Network(ssid: "Telstra2A4F", rssi: -63),
        Network(ssid: "NETGEAR-Guest-Extender-Upstairs-Long-Name", rssi: -71),
        Network(ssid: "Cafe Free WiFi", rssi: -77, open: true),
        Network(ssid: "DIRECT-HP-LaserJet", rssi: -82),
    ]

    public static let onBattery = StatusReport(
        battery: Battery(percent: 64, minutesLeft: 3 * 60 + 12, watts: 9.4, health: 91, cycles: 212),
        wifi: WiFi(ssid: "Home-5G", ip: "192.168.1.24", router: "192.168.1.1", rssi: -48, rate: 1201,
                   security: "WPA3", channel: 44, band: "5 GHz", width: "80 MHz", networks: networks,
                   phones: [Phone(name: "Alex's iPhone", battery: 82)]))

    public static let charging = StatusReport(
        battery: Battery(percent: 41, charging: true, onAC: true, minutesLeft: 58, watts: 61.2,
                         adapterWatts: 96, health: 91, cycles: 212),
        wifi: onBattery.wifi)

    public static let lowPower = StatusReport(
        battery: Battery(percent: 12, minutesLeft: 34, mode: "low power", thermal: "fair", watts: 5.1,
                         health: 78, cycles: 1043),
        wifi: WiFi(ssid: "Alex's iPhone", ip: "172.20.10.3", router: "172.20.10.1", rssi: -69, rate: 286,
                   security: "WPA2", channel: 6, band: "2.4 GHz", width: "20 MHz", networks: networks,
                   phones: [Phone(name: "Alex's iPhone", connected: true)]))

    public static let wifiOff = StatusReport(
        battery: Battery(percent: 100, onAC: true, adapterWatts: 96, health: 100, cycles: 3),
        wifi: WiFi(on: false))

    public static let wired = StatusReport(
        battery: Battery(percent: 88, charging: true, onAC: true, minutesLeft: 25, watts: 32.5,
                         adapterWatts: 96, health: 91, cycles: 212),
        wifi: onBattery.wifi,
        ethernet: Ethernet(name: "USB 10/100/1000 LAN", ip: "192.168.1.31", router: "192.168.1.1"))

    public static let hotspot = StatusReport(
        battery: Battery(percent: 57, minutesLeft: 2 * 60 + 40, watts: 8.2, health: 91, cycles: 212),
        wifi: WiFi(ssid: "Alex's iPhone", ip: "172.20.10.4", router: "172.20.10.1", rssi: -58, rate: 573,
                   security: "WPA3", channel: 149, band: "5 GHz", width: "80 MHz", networks: networks,
                   phones: [Phone(name: "Alex's iPhone", battery: 71, connected: true)]))

    // A Mac mini: no battery, and a scan that has not answered yet.
    public static let desktop = StatusReport(battery: nil, wifi: WiFi(scanning: true))
}

// The desktop behind a panel in a preview, so the glass has something to show.
public struct Desk<Content: View>: View {
    var colors: [Color]
    var content: Content

    public init(colors: [Color] = [.teal, .blue, .indigo], @ViewBuilder content: () -> Content) {
        self.colors = colors
        self.content = content()
    }

    public var body: some View {
        content
            .padding(24)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
