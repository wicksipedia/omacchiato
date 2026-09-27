import SwiftUI
#if canImport(StatusGauge)
import StatusGauge
#endif

// Pieces that every design of the status panel shares.

extension StatusReport.Battery {
    // The iOS battery colours: green while charging, yellow in low power
    // mode, red when low.
    var tint: Color {
        if charging { return .green }
        if mode == "low power" { return .yellow }
        if low { return .red }
        return .primary
    }

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

extension StatusReport {
    var gauge: StatusGauge {
        StatusGauge(battery: Double(battery?.percent ?? 0) / 100,
                    charging: battery?.onAC ?? false,
                    wifi: wifi.on ? wifiLevel(rssi: wifi.rssi ?? 0) : nil)
    }
}

// The bar's own gauge, drawn large with AppKit inside SwiftUI.
struct GaugeGlyph: View {
    var gauge: StatusGauge
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            ctx.withCGContext { cg in
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                gauge.draw(in: CGRect(origin: .zero, size: size),
                           colors: .init(ink: scheme == .dark ? .white : .black))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

public struct PanelCard<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    public init(title: String? = nil, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Label(title.uppercased(), systemImage: symbol ?? "")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }
}

// A row that highlights under the pointer and runs its action on a click.
public struct HoverRow<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovered = false

    public init(action: (() -> Void)?, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered && action != nil ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 7))
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .onTapGesture { action?() }
    }
}

struct NetworkRow: View {
    var network: StatusReport.Network
    var current: Bool
    var action: (() -> Void)?

    var body: some View {
        HoverRow(action: current ? nil : action) {
            HStack(spacing: 8) {
                Image(systemName: "wifi", variableValue: signalFill(network.rssi))
                    .foregroundStyle(current ? Color.accentColor : .primary)
                    .frame(width: 20)
                Text(network.ssid).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if !network.open { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                if current { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor) }
            }
            .font(.system(size: 13, weight: current ? .semibold : .regular))
        }
    }
}

struct PhoneRow: View {
    var phone: StatusReport.Phone
    var action: (() -> Void)?

    var body: some View {
        HoverRow(action: phone.connected ? nil : action) {
            HStack(spacing: 8) {
                Image(systemName: "personalhotspot")
                    .foregroundStyle(phone.connected ? Color.accentColor : .primary)
                    .frame(width: 20)
                Text(phone.name).lineLimit(1)
                Spacer(minLength: 4)
                if phone.connected {
                    Text("Connected").foregroundStyle(.secondary)
                } else if let battery = phone.battery {
                    Label("\(battery)%", systemImage: "battery.75percent")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
        }
    }
}

// The networks card: the joined network first, then the rest by strength,
// then the phones that can share a hotspot.
struct NetworksList: View {
    var wifi: StatusReport.WiFi
    var actions: StatusActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ssid = wifi.ssid {
                NetworkRow(network: .init(ssid: ssid, rssi: wifi.rssi ?? -50), current: true)
            }
            ForEach(wifi.networks.filter { $0.ssid != wifi.ssid }) { network in
                NetworkRow(network: network, current: false) { actions.join(network.ssid) }
            }
            if wifi.networks.isEmpty && wifi.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for networks…").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .padding(6)
            }
            if !wifi.phones.isEmpty {
                Text("PERSONAL HOTSPOT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.horizontal, 6)
                ForEach(wifi.phones) { phone in
                    PhoneRow(phone: phone) { actions.hotspot(phone.name) }
                }
            }
        }
    }
}

// Drawn by hand: the popup window never becomes key, and a system Toggle
// or ProgressView in a window that is not key draws grey.
struct WifiSwitch: View {
    var on: Bool
    var action: () -> Void

    var body: some View {
        Capsule()
            .fill(on ? AnyShapeStyle(Color.green) : AnyShapeStyle(.fill.secondary))
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).shadow(radius: 1, y: 0.5).padding(2)
            }
            .animation(.snappy(duration: 0.2), value: on)
            .contentShape(.capsule)
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel("Wi-Fi")
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
    }
}

struct LevelBar: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.fill.tertiary)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * min(1, max(0, value))))
                }
        }
        .frame(height: 6)
    }
}

struct SettingsRow: View {
    var title: String
    var action: () -> Void

    var body: some View {
        HoverRow(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
        }
    }
}

// The panel sits on Liquid Glass, as the macOS menus do. The glass is a
// layer behind the content: glass around the content would bleach the
// coloured icons and set the text colour from the windows behind.
// The fill keeps the text legible over any window.
struct PanelBackground: ViewModifier {
    var width: CGFloat = 320

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22)
        content
            .padding(12)
            .frame(width: width)
            .background {
                Color.clear.glassEffect(.regular, in: shape)
                shape.fill(.background.opacity(0.6))
            }
    }
}

extension View {
    public func statusPanelBackground(width: CGFloat = 320) -> some View { modifier(PanelBackground(width: width)) }
}
