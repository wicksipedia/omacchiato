import SwiftUI

// The accent and status colours of every panel. They start as the system
// colours, and the bar sets them from the theme. Data colours, such as the
// usage rings and the model bars, stay on the system palette.
public enum PanelColors {
    public static var accent = Color.accentColor
    public static var red = Color.red
    public static var green = Color.green
    public static var orange = Color.orange
    public static var yellow = Color.yellow
}
#if canImport(StatusGauge)
import StatusGauge
#endif

// Pieces that every design of the status panel shares.

extension StatusReport.Battery {
    // Yellow in Low Power Mode, as the Mac's battery icon; then green while charging, red when low.
    var tint: Color {
        if mode == "low power" { return PanelColors.yellow }
        if charging { return PanelColors.green }
        if low { return PanelColors.red }
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
                    lowPower: battery?.mode == "low power",
                    wifi: wifi.on ? wifiLevel(rssi: wifi.rssi ?? 0) : nil,
                    link: ethernet != nil ? .ethernet : (wifi.hotspot ? .hotspot : .wifi))
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
// The arrow keys select a row as the pointer does.
public struct HoverRow<Content: View>: View {
    var action: (() -> Void)?
    var selected: Bool
    @ViewBuilder var content: Content
    @State private var hovered = false

    public init(action: (() -> Void)?, selected: Bool = false, @ViewBuilder content: () -> Content) {
        self.action = action
        self.selected = selected
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((hovered || selected) && action != nil ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 7))
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .onTapGesture { action?() }
    }
}

// The hover fill of HoverRow, for a click target that keeps its own layout.
struct HoverFill: ViewModifier {
    var radius: CGFloat
    var inset: CGFloat
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(hovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear))
                    .padding(-inset)
            }
            .onHover { hovered = $0 }
    }
}

extension View {
    public func hoverFill(radius: CGFloat = 7, inset: CGFloat = 0) -> some View {
        modifier(HoverFill(radius: radius, inset: inset))
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
                    .foregroundStyle(current ? PanelColors.accent : .primary)
                    .frame(width: 20)
                Text(network.ssid).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if !network.open { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                if current { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(PanelColors.accent) }
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
                    .foregroundStyle(phone.connected ? PanelColors.accent : .primary)
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

// Networks card order: the joined network first, then the rest by strength, then hotspot phones.
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

// Drawn by hand. The popup window never becomes key, so a system Toggle
// or ProgressView here draws grey.
struct WifiSwitch: View {
    var on: Bool
    var action: () -> Void

    var body: some View {
        Capsule()
            .fill(on ? AnyShapeStyle(PanelColors.green) : AnyShapeStyle(.fill.secondary))
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

public struct SettingsRow: View {
    var title: String
    var detail = ""
    var action: () -> Void

    public init(title: String, detail: String = "", action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        HoverRow(action: action) {
            HStack {
                Text(title)
                Spacer()
                if !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
        }
    }
}

// Liquid Glass sits behind the content, like macOS menus.
// Wrapping the content in glass bleaches the icons and tints text from windows behind.
// A fill instead keeps text legible over any window.
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

// Renders a glyph as a template image of its ink box.
// Nerd Font glyphs are wider than their advance and sit off-center, so SwiftUI Text crops them.
public func glyphImage(_ glyph: String, size: CGFloat) -> NSImage? {
    guard let font = NSFontManager.shared.font(withFamily: "JetBrainsMono Nerd Font",
                                               traits: [], weight: 9, size: size) else { return nil }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: [.font: font]))
    let ink = CTLineGetImageBounds(line, nil)
    guard ink.width > 0, ink.height > 0 else { return nil }
    let image = NSImage(size: ink.size, flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.textPosition = CGPoint(x: -ink.minX, y: -ink.minY)
        CTLineDraw(line, ctx)
        return true
    }
    image.isTemplate = true
    return image
}
