import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the pull request popup, to compare in the previews.

// "Reminders": a tile per stage with its count, like Reminders' smart
// lists. A tap filters the list to that stage.
public struct RemindersPRPanel: View {
    var report: PRReport
    var actions: PRActions
    @State private var filter: PRReport.Stage?

    public init(report: PRReport, actions: PRActions = .init()) {
        self.report = report
        self.actions = actions
    }

    static let tiles: [PRReport.Stage] = [.needsYou, .inReview, .ready, .running]

    public var body: some View {
        VStack(spacing: 10) {
            StaleNote(report: report, refresh: actions.refresh)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.tiles, id: \.self) { tile($0) }
            }
            let shown = report.repos.map { ($0.name, $0.prs.filter { filter == nil || $0.stage == filter }) }
                .filter { !$0.1.isEmpty }
            if report.prs.isEmpty {
                PanelCard { EmptyPRs() }
            } else if shown.isEmpty {
                PanelCard {
                    Text("Nothing in \(filter?.title ?? "")").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            } else {
                PanelCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(shown, id: \.0) { name, prs in
                            VStack(alignment: .leading, spacing: 0) {
                                RepoHeader(name: name, count: prs.count)
                                ForEach(prs) { PRRow(pr: $0, now: report.now, actions: actions) }
                            }
                        }
                    }
                }
            }
            if let updated = report.updatedStamp {
                UpdatedStamp(updated, staleAfter: PRReport.staleAfter, refresh: actions.refresh)
            }
            SettingsRow(title: "All Pull Requests", detail: "github.com", action: actions.openAll)
        }
        .statusPanelBackground(width: 380)
    }

    func tile(_ stage: PRReport.Stage) -> some View {
        let on = filter == stage
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: stage.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(stage.tint))
                Spacer()
                Text("\(report.count(stage))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(on ? .white : .primary)
            }
            Text(stage.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .padding(10)
        .hoverFill(radius: 12)
        .background(on ? AnyShapeStyle(stage.tint) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { filter = on ? nil : stage } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// "Inbox": sections by what each PR waits for, like Mail's mailboxes;
// each row shows its repo.
public struct InboxPRPanel: View {
    var report: PRReport
    var actions: PRActions

    public init(report: PRReport, actions: PRActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            StaleNote(report: report, refresh: actions.refresh)
            StageBar(report: report)
            if report.prs.isEmpty { PanelCard { EmptyPRs() } }
            ForEach(PRReport.Stage.allCases, id: \.self) { stage in
                let prs = report.prs.filter { $0.stage == stage }
                if !prs.isEmpty {
                    PanelCard(title: stage.title, symbol: stage.symbol) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(prs) { PRRow(pr: $0, now: report.now, actions: actions, showRepo: true) }
                        }
                    }
                }
            }
            if let updated = report.updatedStamp {
                UpdatedStamp(updated, staleAfter: PRReport.staleAfter, refresh: actions.refresh)
            }
            SettingsRow(title: "All Pull Requests", detail: "github.com", action: actions.openAll)
        }
        .statusPanelBackground(width: 380)
    }
}

// The open PRs by stage, as one bar, like iPhone Storage shows space by app.
struct StageBar: View {
    var report: PRReport

    var body: some View {
        let stages = PRReport.Stage.allCases.filter { $0 != .done && report.count($0) > 0 }
        let total = stages.reduce(0) { $0 + report.count($1) }
        if total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(total)").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("open").foregroundStyle(.secondary)
                    Spacer()
                    let needs = report.count(.needsYou)
                    if needs > 0 {
                        Text("\(needs) need\(needs == 1 ? "s" : "") you").foregroundStyle(PanelColors.red)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .font(.system(size: 12))
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(stages, id: \.self) { stage in
                            Rectangle().fill(stage.tint)
                                .frame(width: (geo.size.width - CGFloat(stages.count - 1) * 2)
                                       * CGFloat(report.count(stage)) / CGFloat(total))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(.capsule)
            }
            .padding(.horizontal, 6)
        }
    }
}

// "Tracker": each PR as a delivery, with three steps: checks, review, merge.
public struct TrackerPRPanel: View {
    var report: PRReport
    var actions: PRActions

    public init(report: PRReport, actions: PRActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            StaleNote(report: report, refresh: actions.refresh)
            if report.prs.isEmpty { PanelCard { EmptyPRs() } }
            ForEach(report.repos, id: \.name) { repo in
                PanelCard {
                    RepoHeader(name: repo.name, count: repo.prs.count)
                    ForEach(repo.prs) { pr in
                        HoverRow(action: pr.url.map { url in { actions.open(url) } }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("#\(pr.number)").foregroundStyle(.secondary).monospacedDigit()
                                    Text(pr.title).fontWeight(pr.unread ? .semibold : .regular).lineLimit(2)
                                    Spacer(minLength: 4)
                                    if pr.unread { UnreadDot() }
                                }
                                .font(.system(size: 13))
                                Steps(pr: pr)
                                HStack {
                                    Text(pr.note ?? pr.stage.title)
                                        .foregroundStyle(pr.stage == .needsYou ? AnyShapeStyle(PanelColors.red)
                                                                                : AnyShapeStyle(.secondary))
                                    Spacer()
                                    if pr.state == .open { DiffSize(pr: pr) }
                                    Text(ageText(pr.updated, now: report.now)).foregroundStyle(.secondary)
                                }
                                .font(.system(size: 11))
                            }
                            .padding(.leading, CGFloat(pr.depth) * 14)
                        }
                    }
                }
            }
            if let updated = report.updatedStamp {
                UpdatedStamp(updated, staleAfter: PRReport.staleAfter, refresh: actions.refresh)
            }
            SettingsRow(title: "All Pull Requests", detail: "github.com", action: actions.openAll)
        }
        .statusPanelBackground(width: 380)
    }
}

// Checks, review and merge as three segments: green when done, red when
// blocked, orange while running, grey before.
struct Steps: View {
    var pr: PRReport.PR

    var body: some View {
        let steps: [(String, Color?)] = [
            ("Checks", pr.state != .open ? PanelColors.green : checkColor),
            ("Review", pr.state != .open ? PanelColors.green : reviewColor),
            ("Merge", pr.state == .merged ? .purple : (pr.state == .closed ? .gray : (pr.conflicts ? PanelColors.red : nil))),
        ]
        HStack(spacing: 4) {
            // the text under the steps names the stage, so the steps carry no labels
            ForEach(steps, id: \.0) { _, color in
                Capsule().fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.fill.tertiary)).frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pr.stage.title)
    }

    var checkColor: Color? {
        switch pr.checks {
        case .passed: return PanelColors.green
        case .failed: return PanelColors.red
        case .running: return PanelColors.orange
        case nil: return pr.draft ? nil : PanelColors.green
        }
    }

    var reviewColor: Color? {
        if pr.draft { return nil }
        if pr.review == .changes || pr.threads > 0 { return PanelColors.red }
        return pr.review == .approved ? PanelColors.green : .blue
    }
}
