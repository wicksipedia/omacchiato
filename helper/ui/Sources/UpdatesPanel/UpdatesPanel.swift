import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The updates popup, laid out like Software Update: the release ahead of
// this clone with a button to install it, then its commits as release notes.
public struct UpdatesPanel: View {
    var report: UpdatesReport
    var actions: UpdatesActions

    public init(report: UpdatesReport, actions: UpdatesActions = .init()) {
        self.report = report
        self.actions = actions
    }

    // The plugin fetches every hour: three missed fetches.
    static let staleAfter: TimeInterval = 3 * 3600

    var title: String { report.target.map { "Omacchiato \($0)" } ?? "Omacchiato Update" }

    var subtitle: String {
        let n = report.total
        return "\(n) commit\(n == 1 ? "" : "s") ready to install"
    }

    public var body: some View {
        VStack(spacing: 10) {
            PanelCard {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(PanelColors.accent)
                    VStack(spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    UpdatesButton(title: "Update Now") { actions.update(report.update) }
                }
                .frame(maxWidth: .infinity)
            }
            if !report.commits.isEmpty {
                PanelCard(title: "What's New", symbol: "list.bullet") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.commits) { UpdatesCommitRow(commit: $0) }
                        if report.more > 0 {
                            Text("And \(report.more) more")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let updated = report.updated {
                UpdatedStamp(updated, staleAfter: Self.staleAfter, refresh: actions.refresh)
            }
        }
        .statusPanelBackground(width: 320)
    }
}

struct UpdatesCommitRow: View {
    var commit: UpdatesReport.Commit

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 12, weight: .bold)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(commit.subject).font(.system(size: 12)).lineLimit(2)
                HStack(spacing: 4) {
                    Text(commit.hash).font(.system(size: 10, design: .monospaced))
                    Text(commit.age).font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

// Drawn by hand: a system button in a window that is not key draws grey.
struct UpdatesButton: View {
    var title: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(PanelColors.accent.opacity(hovered ? 0.85 : 1), in: .capsule)
            .contentShape(.capsule)
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}
