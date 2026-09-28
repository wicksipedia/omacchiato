#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension AirPodsReport {
    static let allModes: [Mode] = [
        Mode(id: "off", title: "Off"),
        Mode(id: "transparency", title: "Transparency"),
        Mode(id: "adaptive", title: "Adaptive"),
        Mode(id: "noise-cancellation", title: "Noise Cancellation"),
    ]
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")

    static let pro2 = AirPodsReport(devices: [
        Device(name: "Matt’s AirPods Pro", model: "AirPods Pro (2nd generation)", type: "com.apple.airpods-pro-gen2",
               batteries: [Battery(part: "Left", percent: 83), Battery(part: "Right", percent: 82),
                           Battery(part: "Case", percent: 52)],
               mode: "adaptive", modes: allModes),
    ], settings: settingsURL)

    static let pro3 = AirPodsReport(devices: [
        Device(name: "Studio", model: "AirPods Pro 3", type: "com.apple.airpods-pro-2025",
               batteries: [Battery(part: "Left", percent: 100), Battery(part: "Right", percent: 97)],
               mode: "noise-cancellation", modes: allModes),
    ], settings: settingsURL)

    static let maxOnCable = AirPodsReport(devices: [
        Device(name: "Matt’s AirPods Max", model: "AirPods Max", type: "com.apple.airpods-max-2024",
               batteries: [Battery(part: "Battery", percent: 64)], cable: true),
    ], settings: settingsURL)

    static let low = AirPodsReport(devices: [
        Device(name: "Matt’s AirPods Pro", model: "AirPods Pro (2nd generation)", type: "com.apple.airpods-pro-gen2",
               batteries: [Battery(part: "Left", percent: 12), Battery(part: "Right", percent: 9),
                           Battery(part: "Case", percent: 4)],
               mode: "transparency", modes: allModes),
    ], settings: settingsURL)

    static let unknownModel = AirPodsReport(devices: [
        Device(name: "Matt’s AirPods Pro", model: "AirPods Pro", type: "com.apple.headphones-future",
               batteries: [Battery(part: "Left", percent: 70), Battery(part: "Right", percent: 71)],
               mode: "off", modes: allModes),
    ], settings: settingsURL)

    static let two = AirPodsReport(devices: pro2.devices + maxOnCable.devices, settings: settingsURL)
}

#Preview("AirPods Pro 2") { Desk { AirPodsPanel(report: .pro2) } }
#Preview("AirPods Pro 3") { Desk { AirPodsPanel(report: .pro3) } }
#Preview("AirPods Max on a cable") { Desk { AirPodsPanel(report: .maxOnCable) } }
#Preview("Low batteries") { Desk { AirPodsPanel(report: .low) } }
#Preview("No picture: the symbol") { Desk { AirPodsPanel(report: .unknownModel) } }
#Preview("Two devices") { Desk { AirPodsPanel(report: .two) } }
#Preview("Light") { Desk(colors: [.mint, .cyan, .teal]) { AirPodsPanel(report: .pro2) }.preferredColorScheme(.light) }
#endif
