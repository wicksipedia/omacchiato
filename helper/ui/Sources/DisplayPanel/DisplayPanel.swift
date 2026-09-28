import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the brightness popup shows. The bar reads it from DisplayServices
// and CoreBrightness, and the previews build it by hand.
public struct DisplayReport {
    public var brightness: Double?       // 0...1; nil when the built-in display does not answer
    public var shade: Double             // 0...1: how far the bar dims below the lowest brightness
    public var nightShift: Bool?         // nil on a Mac without Night Shift

    public init(brightness: Double?, shade: Double = 0, nightShift: Bool? = nil) {
        self.brightness = brightness
        self.shade = shade
        self.nightShift = nightShift
    }
}

public struct DisplayActions {
    public var setBrightness: (Double) -> Void = { _ in }
    public var setShade: (Double) -> Void = { _ in }
    public var toggleNightShift: () -> Void = {}
    public var openSettings: () -> Void = {}

    public init() {}
}

// The Display module of Control Center, with the bar's own dimmer.
public struct DisplayPanel: View {
    var report: DisplayReport
    var actions: DisplayActions

    public init(report: DisplayReport, actions: DisplayActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            PanelCard(title: "Display", symbol: "display") {
                VStack(alignment: .leading, spacing: 10) {
                    if let brightness = report.brightness {
                        DisplaySliderRow(title: "Brightness", value: brightness, symbol: "sun.max.fill",
                                         onSlide: actions.setBrightness)
                    }
                    DisplaySliderRow(title: "Extra Dim", value: report.shade, symbol: "moon.fill",
                                     onSlide: actions.setShade)
                }
            }
            if let on = report.nightShift {
                PanelCard {
                    ControlTile(title: "Night Shift", subtitle: on ? "On" : "Off", symbol: "sun.horizon.fill",
                                on: on, tint: PanelColors.orange, action: actions.toggleNightShift)
                }
            }
            SettingsRow(title: "Display Settings", action: actions.openSettings)
        }
        .statusPanelBackground()
    }
}

struct DisplaySliderRow: View {
    var title: String
    var value: Double
    var symbol: String
    var onSlide: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ControlSlider(value: value, symbol: symbol, onSlide: onSlide)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
