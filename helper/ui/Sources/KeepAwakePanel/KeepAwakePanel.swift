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
                ControlTile(title: "Keep Awake", subtitle: subtitle, symbol: "cup.and.saucer.fill", on: report.on) {
                    actions.set(report.on ? "off" : "on")
                }
                HStack(spacing: 6) {
                    ForEach(Self.durations, id: \.arg) { d in
                        DurationButton(title: d.title,
                                       on: report.on && d.arg == "on" && report.until == nil) { actions.set(d.arg) }
                    }
                }
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

    var subtitle: String {
        guard report.on else { return "Off" }
        guard let until = report.until else { return "Until turned off" }
        return "Until " + until.formatted(date: .omitted, time: .shortened)
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
