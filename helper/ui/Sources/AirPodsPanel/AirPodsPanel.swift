import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The AirPods popup: a card for each device with Apple's picture of it
// and a ring for each battery, as the Batteries widget draws them, then
// noise control as Control Center lays it out.
public struct AirPodsPanel: View {
    var report: AirPodsReport
    var actions: AirPodsActions

    public init(report: AirPodsReport, actions: AirPodsActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(report.devices) { DeviceSection(device: $0, actions: actions) }
            SettingsRow(title: "Sound Settings", action: actions.openSettings)
        }
        .statusPanelBackground(width: 320)
    }
}

struct DeviceSection: View {
    var device: AirPodsReport.Device
    var actions: AirPodsActions
    // The mode the user picked, shown until the next report confirms it.
    @State private var picked: String?

    var body: some View {
        PanelCard {
            VStack(spacing: 12) {
                ProductPicture(device: device)
                VStack(spacing: 2) {
                    Text(device.name).font(.system(size: 13, weight: .semibold))
                    if let subtitle = device.subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if device.cable {
                        Label("Plugged into this Mac", systemImage: "cable.connector")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    ForEach(device.batteries) { BatteryRing(battery: $0, max: device.isMax).frame(maxWidth: .infinity) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        if !device.modes.isEmpty {
            PanelCard(title: "Noise Control", symbol: "ear") {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(device.modes) { mode in
                        ModeButton(mode: mode, on: (picked ?? device.mode) == mode.id) {
                            picked = mode.id
                            actions.setMode(mode)
                        }
                    }
                }
            }
            .onChange(of: device.mode) { picked = nil }
        }
    }
}

struct ProductPicture: View {
    var device: AirPodsReport.Device

    var body: some View {
        let images = ProductArt.images(for: device.type)
        Group {
            if images.isEmpty {
                Image(systemName: device.isMax ? "airpodsmax" : "airpods.pro")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: -6) {
                    ForEach(images.indices, id: \.self) {
                        Image(nsImage: images[$0]).resizable().interpolation(.high).scaledToFit()
                    }
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }
        }
        .frame(height: 104)
        .accessibilityHidden(true)
    }
}

struct BatteryRing: View {
    var battery: AirPodsReport.Battery
    var max: Bool

    var symbol: String {
        switch battery.part {
        case "Left": return "airpods.pro.left"
        case "Right": return "airpods.pro.right"
        case "Case": return "airpods.pro.chargingcase.wireless.fill"
        default: return max ? "airpodsmax" : "airpods.pro"
        }
    }

    var body: some View {
        let tint = battery.low ? PanelColors.red : PanelColors.green
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(.fill.tertiary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: Double(battery.percent) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol).font(.system(size: 15))
            }
            .frame(width: 44, height: 44)
            Text("\(battery.percent)%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(battery.low ? AnyShapeStyle(PanelColors.red) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.part)
        .accessibilityValue("\(battery.percent) percent")
    }
}

struct ModeButton: View {
    var mode: AirPodsReport.Mode
    var on: Bool
    var action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: mode.symbol)
                .font(.system(size: 15))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 38, height: 38)
                .background(on ? AnyShapeStyle(PanelColors.accent) : AnyShapeStyle(.fill.tertiary), in: .circle)
            Text(mode.title)
                .font(.system(size: 10, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                // "Transparency" is one word wider than a quarter of the card.
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .hoverFill(radius: 10)
        .contentShape(.rect)
        .onTapGesture { if !on { action() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
