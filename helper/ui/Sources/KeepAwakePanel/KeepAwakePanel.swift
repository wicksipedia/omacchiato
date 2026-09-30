import AppKit
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The keep-awake popup: the switch and how long to stay awake, then the
// other apps that hold the Mac up, as the Battery menu lists "Apps Using
// Significant Energy".
public struct KeepAwakePanel: View {
    var report: KeepAwakeReport
    var actions: KeepAwakeActions

    public init(report: KeepAwakeReport, actions: KeepAwakeActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            PanelCard {
                // the switch turns on with the last chosen time, as Super+Esc does
                ControlTile(title: "Keep Awake", subtitle: subtitle, symbol: "cup.and.saucer.fill", on: report.on) {
                    actions.set("toggle")
                }
                HStack(spacing: 6) {
                    ForEach(Self.durations, id: \.arg) { d in
                        DurationButton(title: d.title, on: report.last == d.arg) { actions.set(d.arg) }
                    }
                }
                .padding(.horizontal, 6)
                CustomDuration(chosen: custom, start: { actions.set("for \($0)") })
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
            PanelCard(title: "Also Keeping Awake", symbol: "cup.and.saucer.fill") {
                if report.holders.isEmpty {
                    NothingAwake()
                } else {
                    VStack(spacing: 0) {
                        ForEach(report.holders) { HolderRow(holder: $0) }
                    }
                }
            }
            SettingsRow(title: "Battery Settings", action: actions.openSettings)
        }
        .statusPanelBackground(width: 300)
    }

    static let durations = [(title: "30 min", arg: "for 30"), (title: "1 hr", arg: "for 60"),
                            (title: "2 hr", arg: "for 120"), (title: "Until Off", arg: "on")]

    // The last time, when the user chose it with Custom rather than a preset.
    var custom: Int? {
        guard let minutes = report.lastMinutes, !Self.durations.contains(where: { $0.arg == report.last })
        else { return nil }
        return minutes
    }

    var subtitle: String {
        guard report.on else { return "Off" }
        guard let until = report.until else { return "Until turned off" }
        return "Until " + until.formatted(date: .omitted, time: .shortened)
    }
}

// 15 minutes to 12 hours, in 15-minute steps. A popup never takes typed text.
func customMinutes(_ minutes: Int, by steps: Int) -> Int {
    min(720, max(15, minutes + steps * 15))
}

func customLabel(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) min" }
    return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
}

// A time of the user's own: − and + step it, and Start begins it.
struct CustomDuration: View {
    var chosen: Int?                     // the custom time last chosen, lit while it is the choice
    var start: (Int) -> Void
    @State private var minutes: Int?

    var body: some View {
        let shown = minutes ?? chosen ?? 45
        HStack(spacing: 6) {
            Text("Custom").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            StepButton(symbol: "minus") { minutes = customMinutes(shown, by: -1) }
            Text(customLabel(shown))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 70)
            StepButton(symbol: "plus") { minutes = customMinutes(shown, by: 1) }
            DurationButton(title: "Start", on: chosen == shown) { start(shown) }
                .frame(width: 64)
        }
    }
}

struct StepButton: View {
    var symbol: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 24, height: 24)
            .background(hovered ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary), in: .circle)
            .contentShape(.circle)
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

// A time choice, drawn by hand: the popup is never key, so a system
// button would draw grey.
struct DurationButton: View {
    var title: String
    var on: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(on ? AnyShapeStyle(PanelColors.accent)
                           : hovered ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary), in: .capsule)
            .contentShape(.capsule)
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

struct HolderRow: View {
    var holder: KeepAwakeReport.Holder

    var body: some View {
        HoverRow(action: nil) {
            HStack(spacing: 8) {
                HolderIcon(pid: holder.pid).frame(width: 22, height: 22)
                Text(holder.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Text(holder.duration)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .help(holder.name)
    }
}

struct HolderIcon: View {
    var pid: Int32?

    var body: some View {
        Group {
            if let icon = pid.flatMap({ NSRunningApplication(processIdentifier: $0)?.icon }) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

struct NothingAwake: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(PanelColors.green)
            Text("No other app is keeping the Mac awake").foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}
