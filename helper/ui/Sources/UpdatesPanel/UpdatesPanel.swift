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

    var title: String {
        if report.channel == "edge" { return "Omacchiato Edge" }
        return report.target.map { "Omacchiato \($0)" } ?? "Omacchiato Update"
    }

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
                    if !report.counts.isEmpty {
                        UpdatesChannelPicker(channel: report.channel, counts: report.counts, pick: actions.setChannel)
                    }
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

// A dropdown drawn by hand, as a system menu draws grey in a window that is not key.
// It opens in place, under its button.
struct UpdatesChannelPicker: View {
    var channel: String
    var counts: [String: Int]
    var pick: (String) -> Void
    @State private var open = false

    static let names = ["release": "Latest Release", "edge": "Edge"]
    static let details = ["release": "The newest tagged release", "edge": "The newest commit"]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(Self.names[channel] ?? channel).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.quaternary.opacity(open ? 1 : 0.5), in: .capsule)
            .contentShape(.capsule)
            .onTapGesture { open.toggle() }
            .accessibilityAddTraits(.isButton)
            if open {
                VStack(spacing: 2) {
                    ForEach(["release", "edge"], id: \.self) { id in
                        UpdatesChannelRow(name: Self.names[id] ?? id, detail: Self.details[id] ?? "",
                                          count: counts[id] ?? 0, selected: id == channel) {
                            open = false
                            if id != channel { pick(id) }
                        }
                    }
                }
                .padding(4)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
        }
    }
}

struct UpdatesChannelRow: View {
    var name: String
    var detail: String
    var count: Int
    var selected: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                .opacity(selected ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(count == 0 ? "Up to date" : "\(count) new")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovered ? PanelColors.accent.opacity(0.2) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
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
