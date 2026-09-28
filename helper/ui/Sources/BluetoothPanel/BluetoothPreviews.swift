#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension BluetoothReport {
    static let desk = BluetoothReport(devices: [
        Device(id: "1", name: "Matt’s AirPods Pro", kind: .audio, connected: true),
        Device(id: "2", name: "Magic Keyboard with Touch ID", kind: .keyboard, connected: true),
        Device(id: "3", name: "Magic Trackpad", kind: .trackpad),
        Device(id: "4", name: "Matt’s AirPods Max", kind: .audio),
        Device(id: "5", name: "Xbox Wireless Controller", kind: .gamepad),
        Device(id: "6", name: "Matt’s iPhone", kind: .phone),
    ])
}

#Preview("Bluetooth") { Desk { BluetoothPanel(report: .desk) } }
#Preview("Bluetooth: nothing paired") { Desk { BluetoothPanel(report: BluetoothReport()) } }
#Preview("Bluetooth: no permission") { Desk { BluetoothPanel(report: BluetoothReport(allowed: false)) } }
#Preview("Bluetooth: light") {
    Desk(colors: [.mint, .cyan, .teal]) { BluetoothPanel(report: .desk) }.preferredColorScheme(.light)
}
#endif
