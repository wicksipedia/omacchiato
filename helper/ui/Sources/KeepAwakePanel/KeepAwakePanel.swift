import AppKit
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The keep-awake popup: who is holding the Mac up and for how long, as the
// Battery menu lists "Apps Using Significant Energy".
public struct KeepAwakePanel: View {
    var report: KeepAwakeReport
    var actions: KeepAwakeActions

    public init(report: KeepAwakeReport, actions: KeepAwakeActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            PanelCard(title: "Keeping Awake", symbol: "cup.and.saucer.fill") {
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
            Text("Nothing is keeping the Mac awake").foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}
