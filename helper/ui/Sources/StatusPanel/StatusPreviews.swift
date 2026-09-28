#if DEBUG
import SwiftUI

private let samples: [StatusReport] = [.onBattery, .charging, .lowPower, .wifiOff, .wired, .hotspot, .desktop]

#Preview("Gauge") { Desk(colors: [.orange, .pink, .purple, .blue]) { GaugeStatusPanel(report: .onBattery) } }
#Preview("Control Center") { Desk(colors: [.orange, .pink, .purple, .blue]) { ControlCenterStatusPanel(report: .onBattery) } }
#Preview("Settings") { Desk(colors: [.orange, .pink, .purple, .blue]) { SettingsStatusPanel(report: .onBattery) } }
#Preview("Gauge: Ethernet") { Desk(colors: [.orange, .pink, .purple, .blue]) { GaugeStatusPanel(report: .wired) } }
#Preview("Gauge: hotspot") { Desk(colors: [.orange, .pink, .purple, .blue]) { GaugeStatusPanel(report: .hotspot) } }

#Preview("Gauge: every state") {
    Desk(colors: [.orange, .pink, .purple, .blue]) {
        HStack(alignment: .top, spacing: 16) {
            ForEach(samples.indices, id: \.self) { GaugeStatusPanel(report: samples[$0]) }
        }
    }
}

#Preview("Control Center: every state") {
    Desk(colors: [.orange, .pink, .purple, .blue]) {
        HStack(alignment: .top, spacing: 16) {
            ForEach(samples.indices, id: \.self) { ControlCenterStatusPanel(report: samples[$0]) }
        }
    }
}

#Preview("Settings: every state") {
    Desk(colors: [.orange, .pink, .purple, .blue]) {
        HStack(alignment: .top, spacing: 16) {
            ForEach(samples.indices, id: \.self) { SettingsStatusPanel(report: samples[$0]) }
        }
    }
}

#Preview("Gauge, dark") { Desk(colors: [.orange, .pink, .purple, .blue]) { GaugeStatusPanel(report: .onBattery) }.preferredColorScheme(.dark) }
#Preview("Battery") { Desk(colors: [.orange, .pink, .purple, .blue]) { BatteryPanel(report: .onBattery) } }
#Preview("Battery: charging") { Desk(colors: [.orange, .pink, .purple, .blue]) { BatteryPanel(report: .charging) } }
#Preview("Battery: Low Power") { Desk(colors: [.orange, .pink, .purple, .blue]) { BatteryPanel(report: .lowPower) } }
#Preview("Battery: no battery") { Desk(colors: [.orange, .pink, .purple, .blue]) { BatteryPanel(report: .desktop) } }
#Preview("Battery: light") {
    Desk(colors: [.mint, .cyan, .teal]) { BatteryPanel(report: .onBattery) }.preferredColorScheme(.light)
}
#Preview("Wi-Fi") { Desk(colors: [.orange, .pink, .purple, .blue]) { WifiPanel(report: .onBattery) } }
#Preview("Wi-Fi: off") { Desk(colors: [.orange, .pink, .purple, .blue]) { WifiPanel(report: .wifiOff) } }
#Preview("Wi-Fi: hotspot") { Desk(colors: [.orange, .pink, .purple, .blue]) { WifiPanel(report: .hotspot) } }
#Preview("Wi-Fi: scanning") { Desk(colors: [.orange, .pink, .purple, .blue]) { WifiPanel(report: .desktop) } }
#Preview("Wi-Fi: light") {
    Desk(colors: [.mint, .cyan, .teal]) { WifiPanel(report: .onBattery) }.preferredColorScheme(.light)
}
#endif
