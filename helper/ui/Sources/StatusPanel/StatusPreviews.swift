#if DEBUG
import SwiftUI

// Sample data for the previews: a working day on battery, and the states
// that break a layout.
extension StatusReport {
    static let networks: [Network] = [
        Network(ssid: "Home-5G", rssi: -48),
        Network(ssid: "Telstra2A4F", rssi: -63),
        Network(ssid: "NETGEAR-Guest-Extender-Upstairs-Long-Name", rssi: -71),
        Network(ssid: "Cafe Free WiFi", rssi: -77, open: true),
        Network(ssid: "DIRECT-HP-LaserJet", rssi: -82),
    ]

    static let onBattery = StatusReport(
        battery: Battery(percent: 64, minutesLeft: 3 * 60 + 12, watts: 9.4, health: 91, cycles: 212),
        wifi: WiFi(ssid: "Home-5G", ip: "192.168.1.24", router: "192.168.1.1", rssi: -48, rate: 1201,
                   security: "WPA3", channel: 44, band: "5 GHz", width: "80 MHz", networks: networks,
                   phones: [Phone(name: "Alex's iPhone", battery: 82)]))

    static let charging = StatusReport(
        battery: Battery(percent: 41, charging: true, onAC: true, minutesLeft: 58, watts: 61.2,
                         adapterWatts: 96, health: 91, cycles: 212),
        wifi: onBattery.wifi)

    static let lowPower = StatusReport(
        battery: Battery(percent: 12, minutesLeft: 34, mode: "low power", thermal: "fair", watts: 5.1,
                         health: 78, cycles: 1043),
        wifi: WiFi(ssid: "Alex's iPhone", ip: "172.20.10.3", router: "172.20.10.1", rssi: -69, rate: 286,
                   security: "WPA2", channel: 6, band: "2.4 GHz", width: "20 MHz", networks: networks,
                   phones: [Phone(name: "Alex's iPhone", connected: true)]))

    static let wifiOff = StatusReport(
        battery: Battery(percent: 100, onAC: true, adapterWatts: 96, health: 100, cycles: 3),
        wifi: WiFi(on: false))

    // At a desk: a cable to a dock, with wi-fi on and joined as well.
    static let wired = StatusReport(
        battery: Battery(percent: 88, charging: true, onAC: true, minutesLeft: 25, watts: 32.5,
                         adapterWatts: 96, health: 91, cycles: 212),
        wifi: onBattery.wifi,
        ethernet: Ethernet(name: "USB 10/100/1000 LAN", ip: "192.168.1.31", router: "192.168.1.1"))

    // On the road, joined to a phone's hotspot.
    static let hotspot = StatusReport(
        battery: Battery(percent: 57, minutesLeft: 2 * 60 + 40, watts: 8.2, health: 91, cycles: 212),
        wifi: WiFi(ssid: "Alex's iPhone", ip: "172.20.10.4", router: "172.20.10.1", rssi: -58, rate: 573,
                   security: "WPA3", channel: 149, band: "5 GHz", width: "80 MHz", networks: networks,
                   phones: [Phone(name: "Alex's iPhone", battery: 71, connected: true)]))

    // A Mac mini: no battery, and a scan that has not answered yet.
    static let desktop = StatusReport(battery: nil, wifi: WiFi(scanning: true))
}

// A busy desktop behind the panel, so the glass has something to show.
private struct Desk<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .background(LinearGradient(colors: [.orange, .pink, .purple, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

private let samples: [StatusReport] = [.onBattery, .charging, .lowPower, .wifiOff, .wired, .hotspot, .desktop]

#Preview("Gauge") { Desk { GaugeStatusPanel(report: .onBattery) } }
#Preview("Control Center") { Desk { ControlCenterStatusPanel(report: .onBattery) } }
#Preview("Settings") { Desk { SettingsStatusPanel(report: .onBattery) } }
#Preview("Gauge: Ethernet") { Desk { GaugeStatusPanel(report: .wired) } }
#Preview("Gauge: hotspot") { Desk { GaugeStatusPanel(report: .hotspot) } }

#Preview("Gauge: every state") {
    Desk {
        HStack(alignment: .top, spacing: 16) {
            ForEach(samples.indices, id: \.self) { GaugeStatusPanel(report: samples[$0]) }
        }
    }
}

#Preview("Control Center: every state") {
    Desk {
        HStack(alignment: .top, spacing: 16) {
            ForEach(samples.indices, id: \.self) { ControlCenterStatusPanel(report: samples[$0]) }
        }
    }
}

#Preview("Settings: every state") {
    Desk {
        HStack(alignment: .top, spacing: 16) {
            ForEach(samples.indices, id: \.self) { SettingsStatusPanel(report: samples[$0]) }
        }
    }
}

#Preview("Gauge, dark") { Desk { GaugeStatusPanel(report: .onBattery) }.preferredColorScheme(.dark) }
#endif
