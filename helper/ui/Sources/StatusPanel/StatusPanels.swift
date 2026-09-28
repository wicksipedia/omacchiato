import SwiftUI
#if canImport(StatusGauge)
import StatusGauge
#endif

// Three designs of the same popup, to compare in the previews. Each shows the same data and actions.

// "Gauge": the bar's gauge drawn large, then tiles like the weather panel.
public struct GaugeStatusPanel: View {
    var report: StatusReport
    var actions: StatusActions

    public init(report: StatusReport, actions: StatusActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            hero
            tiles
            if report.wifi.on {
                PanelCard(title: "Networks", symbol: "wifi") {
                    NetworksList(wifi: report.wifi, actions: actions)
                }
            }
            HStack(spacing: 0) {
                SettingsRow(title: "Battery Settings", action: actions.batterySettings)
                SettingsRow(title: "Wi-Fi Settings", action: actions.networkSettings)
            }
        }
        .statusPanelBackground()
    }

    var hero: some View {
        VStack(spacing: 6) {
            GaugeGlyph(gauge: report.gauge).frame(width: 92)
            if let b = report.battery {
                Text("\(b.percent)%")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(b.tint == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(b.tint))
                    .contentTransition(.numericText())
                Text([b.state, b.timeText].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let e = report.ethernet {
                HStack(spacing: 6) {
                    // Matches the Ethernet glyph the gauge draws.
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "ellipsis").font(.system(size: 11, weight: .black))
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold))
                    Text(e.name).lineLimit(1)
                }
                .font(.system(size: 13, weight: .medium))
            }
            HStack(spacing: 6) {
                Image(systemName: !report.wifi.on ? "wifi.slash" : (report.wifi.hotspot ? "personalhotspot" : "wifi"),
                      variableValue: report.wifi.rssi.map(signalFill) ?? 0)
                Text(report.wifi.on ? (report.wifi.ssid ?? "Not connected") : "Wi-Fi off")
                    .lineLimit(1)
                WifiSwitch(on: report.wifi.on, action: actions.toggleWifi)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 6)
    }

    var tiles: some View {
        let b = report.battery
        let w = report.wifi
        typealias Tile = (String, String, String, String?)
        var items: [Tile] = []
        if let b, let watts = b.watts {
            let note = b.adapterWatts.map { "\($0) W adapter" } ?? (b.onAC ? nil : "Draw")
            items.append(("Power", "bolt.fill", String(format: "%.1f W", watts), note))
        }
        if let b, let health = b.health { items.append(("Health", "heart.fill", "\(health)%", b.cycles.map { "\($0) cycles" })) }
        if let b, let mode = b.mode {
            let symbol = mode == "low power" ? "leaf.fill" : "gauge.with.dots.needle.67percent"
            items.append(("Mode", symbol, mode.capitalized, b.thermal.map { "Thermal \($0)" }))
        }
        if let rssi = w.rssi { items.append(("Signal", "wifi", "\(rssi) dBm", w.verdict)) }
        if let rate = w.rate { items.append(("Link", "arrow.up.arrow.down", "\(rate) Mbps", w.security)) }
        if let channel = w.channel {
            let band = [w.band, w.width].compactMap { $0 }.joined(separator: " · ")
            items.append(("Channel", "antenna.radiowaves.left.and.right", "\(channel)", band))
        }
        if let ip = report.ethernet?.ip ?? w.ip {
            let router = report.ethernet.map { $0.router } ?? w.router
            items.append(("Address", "network", ip, router.map { "Router \($0)" }))
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            ForEach(items, id: \.0) { title, symbol, value, note in
                VStack(alignment: .leading, spacing: 3) {
                    Label(title.uppercased(), systemImage: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(value).font(.system(size: 17, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(note ?? " ").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            }
        }
    }
}

// "Control Center": two big toggles side by side, then the network list, with the numbers folded away under Details.
public struct ControlCenterStatusPanel: View {
    var report: StatusReport
    var actions: StatusActions
    @State private var details = false

    public init(report: StatusReport, actions: StatusActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let b = report.battery { batteryTile(b) }
                wifiTile
            }
            if report.wifi.on {
                PanelCard {
                    NetworksList(wifi: report.wifi, actions: actions)
                }
            }
            PanelCard {
                DisclosureGroup("Details", isExpanded: $details) {
                    VStack(spacing: 6) { detailRows }.padding(.top, 6)
                }
                .font(.system(size: 13, weight: .medium))
            }
            HStack(spacing: 0) {
                SettingsRow(title: "Battery Settings", action: actions.batterySettings)
                SettingsRow(title: "Wi-Fi Settings", action: actions.networkSettings)
            }
        }
        .statusPanelBackground()
    }

    func batteryTile(_ b: StatusReport.Battery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: b.symbol)
                .font(.system(size: 22))
                .foregroundStyle(b.tint == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(b.tint))
            Text("\(b.percent)%").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(b.timeText ?? b.state).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 18))
    }

    var wifiTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: report.wifi.on ? "wifi" : "wifi.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(report.wifi.on ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(report.wifi.on ? AnyShapeStyle(PanelColors.accent) : AnyShapeStyle(.fill.tertiary),
                            in: .circle)
            Text("Wi-Fi").font(.system(size: 13, weight: .semibold))
            Text(report.wifi.on ? (report.wifi.ssid ?? "Not connected") : "Off")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .hoverFill(radius: 18)
        .background(.fill.quaternary, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture(perform: actions.toggleWifi)
    }

    @ViewBuilder var detailRows: some View {
        let b = report.battery
        let w = report.wifi
        let rows: [(String, String?)] = [
            ("Power", b?.watts.map { String(format: "%.1f W", $0) }),
            ("Adapter", b?.adapterWatts.map { "\($0) W" }),
            ("Mode", b?.mode?.capitalized),
            ("Health", b?.health.map { "\($0)%" }),
            ("Cycles", b?.cycles.map(String.init)),
            ("Signal", w.rssi.map { "\($0) dBm · \(w.verdict ?? "")" }),
            ("Link", w.rate.map { "\($0) Mbps" + (w.security.map { " · \($0)" } ?? "") }),
            ("Channel", w.channel.map { "\($0) · " + [w.band, w.width].compactMap { $0 }.joined(separator: " · ") }),
            ("IP address", w.ip),
            ("Router", w.router),
        ]
        ForEach(rows.filter { $0.1 != nil }, id: \.0) { label, value in
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value ?? "").monospacedDigit()
            }
            .font(.system(size: 12))
        }
    }
}

// "Settings": grouped lists, like iOS Settings > Battery and > Wi-Fi.
public struct SettingsStatusPanel: View {
    var report: StatusReport
    var actions: StatusActions

    public init(report: StatusReport, actions: StatusActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = report.battery { batteryGroup(b) }
            wifiGroup
            if report.wifi.on {
                group("Networks") { NetworksList(wifi: report.wifi, actions: actions) }
            }
        }
        .statusPanelBackground()
    }

    func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(6)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        }
    }

    func row(_ symbol: String, _ tint: Color, _ label: String, _ value: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: .rect(cornerRadius: 6))
            Text(label)
            Spacer()
            Text(value ?? "").foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    func batteryGroup(_ b: StatusReport.Battery) -> some View {
        group("Battery") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(b.percent)%").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(b.state).foregroundStyle(.secondary)
                    Spacer()
                    Text(b.timeText ?? "").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                LevelBar(value: Double(b.percent) / 100, tint: b.tint == .primary ? PanelColors.green : b.tint)
            }
            .padding(6)
            if let mode = b.mode {
                row(mode == "low power" ? "leaf.fill" : "gauge.with.dots.needle.67percent",
                    mode == "low power" ? PanelColors.yellow : PanelColors.orange, "Power mode", mode.capitalized)
            }
            if let w = b.watts {
                row("bolt.fill", PanelColors.green, b.onAC ? "Charging at" : "Power draw", String(format: "%.1f W", w))
            }
            if let a = b.adapterWatts { row("powerplug.fill", .gray, "Adapter", "\(a) W") }
            if let h = b.health { row("heart.fill", .pink, "Health", "\(h)%") }
            if let c = b.cycles { row("arrow.triangle.2.circlepath", .blue, "Cycles", "\(c)") }
            if let t = b.thermal { row("thermometer.medium", PanelColors.red, "Thermal", t.capitalized) }
            SettingsRow(title: "Battery Settings", action: actions.batterySettings)
        }
    }

    var wifiGroup: some View {
        let w = report.wifi
        return group("Wi-Fi") {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.blue, in: .rect(cornerRadius: 6))
                Text("Wi-Fi")
                Spacer()
                WifiSwitch(on: w.on, action: actions.toggleWifi)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            if w.on {
                if let rssi = w.rssi { row("cellularbars", PanelColors.green, "Signal", "\(rssi) dBm · \(w.verdict ?? "")") }
                if let rate = w.rate { row("arrow.up.arrow.down", .teal, "Link", "\(rate) Mbps" + (w.security.map { " · \($0)" } ?? "")) }
                if let ch = w.channel {
                    row("antenna.radiowaves.left.and.right", .purple, "Channel",
                        "\(ch) · " + [w.band, w.width].compactMap { $0 }.joined(separator: " · "))
                }
                if let ip = w.ip { row("network", .indigo, "IP address", ip) }
                if let router = w.router { row("wifi.router.fill", .gray, "Router", router) }
            }
            SettingsRow(title: "Wi-Fi Settings", action: actions.networkSettings)
        }
    }
}
