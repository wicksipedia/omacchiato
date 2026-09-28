import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the Bluetooth popup shows. The bar reads it from IOBluetooth, and
// the previews build it by hand.
public struct BluetoothReport {
    public enum Kind: String { case audio, keyboard, mouse, trackpad, phone, computer, gamepad, other }

    public struct Device: Identifiable {
        public var id: String            // the Bluetooth address
        public var name: String
        public var kind: Kind
        public var connected: Bool

        public init(id: String, name: String, kind: Kind = .other, connected: Bool = false) {
            self.id = id
            self.name = name
            self.kind = kind
            self.connected = connected
        }

        public var symbol: String {
            switch kind {
            case .audio:
                if name.contains("AirPods Max") { return "airpodsmax" }
                if name.contains("AirPods") { return "airpods.pro" }
                if name.contains("Beats") { return "beats.headphones" }
                return "headphones"
            case .keyboard: return "keyboard.fill"
            case .mouse: return "magicmouse.fill"
            case .trackpad: return "rectangle.and.hand.point.up.left.fill"
            case .phone: return "iphone"
            case .computer: return "laptopcomputer"
            case .gamepad: return "gamecontroller.fill"
            case .other: return "wave.3.right"
            }
        }
    }

    public var allowed: Bool             // false until the bar has the Bluetooth grant
    public var devices: [Device]         // the paired devices

    public init(allowed: Bool = true, devices: [Device] = []) {
        self.allowed = allowed
        self.devices = devices
    }
}

public struct BluetoothActions {
    public var toggle: (String) -> Void = { _ in }   // connect or disconnect, by address
    public var openSettings: () -> Void = {}

    public init() {}
}

// The Bluetooth module of Control Center: connected devices first, then
// the rest of the paired devices. A click connects or disconnects.
public struct BluetoothPanel: View {
    var report: BluetoothReport
    var actions: BluetoothActions
    // The devices clicked, shown as busy until the next report.
    @State private var busy: Set<String> = []

    public init(report: BluetoothReport, actions: BluetoothActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            if !report.allowed {
                PanelCard {
                    Label("Omacchiato has no Bluetooth permission. Run omacchiato-permissions.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if report.devices.isEmpty {
                PanelCard {
                    Text("No paired devices")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            } else {
                section("Connected", report.devices.filter(\.connected))
                section("My Devices", report.devices.filter { !$0.connected })
            }
            SettingsRow(title: "Bluetooth Settings", action: actions.openSettings)
        }
        .statusPanelBackground()
        .onChange(of: report.devices.map(\.connected)) { busy = [] }
    }

    @ViewBuilder
    func section(_ title: String, _ devices: [BluetoothReport.Device]) -> some View {
        if !devices.isEmpty {
            PanelCard(title: title) {
                VStack(spacing: 0) {
                    ForEach(devices) { device in
                        ControlTile(title: device.name,
                                    subtitle: busy.contains(device.id)
                                        ? (device.connected ? "Disconnecting…" : "Connecting…")
                                        : (device.connected ? "Connected" : nil),
                                    symbol: device.symbol, on: device.connected) {
                            busy.insert(device.id)
                            actions.toggle(device.id)
                        }
                    }
                }
            }
        }
    }
}
