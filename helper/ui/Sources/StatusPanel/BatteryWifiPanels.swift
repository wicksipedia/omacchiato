import SwiftUI

// The popups of the battery and wi-fi pills, which a user can show in
// place of the status pill. Each is one half of the status panel.

public struct BatteryPanel: View {
    var report: StatusReport
    var actions: StatusActions

    public init(report: StatusReport, actions: StatusActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            if let b = report.battery {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(b.percent)%")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(b.tint == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(b.tint))
                            .contentTransition(.numericText())
                        Spacer()
                        Label(b.state, systemImage: b.charging ? "bolt.fill" : (b.onAC ? "powerplug.fill" : "battery.75percent"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    LevelBar(value: Double(b.percent) / 100, tint: b.tint == .primary ? PanelColors.green : b.tint)
                    if let time = b.timeText {
                        Text(time.prefix(1).uppercased() + time.dropFirst())
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(.fill.quaternary, in: .rect(cornerRadius: 14))
                StatusTiles(report: report, showWifi: false)
            } else {
                PanelCard {
                    Label("This Mac has no battery", systemImage: "powerplug.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            SettingsRow(title: "Battery Settings", action: actions.batterySettings)
        }
        .statusPanelBackground()
    }
}

public struct WifiPanel: View {
    var report: StatusReport
    var actions: StatusActions

    public init(report: StatusReport, actions: StatusActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        let w = report.wifi
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: !w.on ? "wifi.slash" : (w.hotspot ? "personalhotspot" : "wifi"),
                      variableValue: w.rssi.map(signalFill) ?? 0)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(w.on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 30, height: 30)
                    .background(w.on ? AnyShapeStyle(PanelColors.accent) : AnyShapeStyle(.fill.tertiary), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wi-Fi").font(.system(size: 13, weight: .semibold))
                    Text(w.on ? (w.ssid ?? "Not connected") : "Off")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                WifiSwitch(on: w.on, action: actions.toggleWifi)
            }
            .padding(.horizontal, 6)
            if w.on {
                StatusTiles(report: report, showBattery: false)
                PanelCard(title: "Networks", symbol: "wifi") {
                    NetworksList(wifi: w, actions: actions)
                }
            }
            SettingsRow(title: "Wi-Fi Settings", action: actions.networkSettings)
        }
        .statusPanelBackground()
    }
}
