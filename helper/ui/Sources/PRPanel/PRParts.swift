import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Pieces that every design of the pull request panel shares.

extension PRReport.PR {
    var tint: Color { state == .closed ? .secondary : stage.tint }
}

// Mail's unread dot.
struct UnreadDot: View {
    var body: some View {
        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
            .accessibilityLabel("Updated")
    }
}

// The size of the change as GitHub shows it: added lines, removed lines,
// and five blocks split between them.
struct DiffSize: View {
    var pr: PRReport.PR

    var body: some View {
        let total = pr.additions + pr.deletions
        let green = total == 0 ? 0 : Int((5 * Double(pr.additions) / Double(total)).rounded())
        HStack(spacing: 4) {
            Text("+\(pr.additions)").foregroundStyle(.green)
            Text("−\(pr.deletions)").foregroundStyle(.red)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(total == 0 ? AnyShapeStyle(.fill.secondary)
                              : AnyShapeStyle(i < green ? Color.green : Color.red))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
    }
}

// One PR: its mark, number and title, and what it waits for.
struct PRRow: View {
    var pr: PRReport.PR
    var now: Date
    var actions: PRActions
    var showRepo = false
    var showDiff = true

    var body: some View {
        HoverRow(action: pr.url.map { url in { actions.open(url) } }) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: pr.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pr.tint)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.system(size: 13, weight: pr.unread ? .semibold : .regular))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text((showRepo ? pr.repo : "") + "#\(pr.number)").truncationMode(.head)
                        Spacer(minLength: 4)
                        if showDiff && pr.state == .open { DiffSize(pr: pr).fixedSize() }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if let note = pr.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(pr.stage == .needsYou ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                    }
                }
                VStack(alignment: .trailing, spacing: 4) {
                    Text(ageText(pr.updated, now: now))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    if pr.unread { UnreadDot() }
                }
            }
            .padding(.leading, CGFloat(pr.depth) * 14)
            .overlay(alignment: .leading) {
                if pr.depth > 0 {
                    // the stack line from the PR this one sits on
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .offset(x: CGFloat(pr.depth - 1) * 14, y: -1)
                }
            }
        }
    }
}

struct RepoHeader: View {
    var name: String
    var count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "book.closed.fill").font(.system(size: 10))
            Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.head)
            Spacer()
            Text("\(count)").font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

// The list is old: GitHub was out of reach on the last run.
struct StaleNote: View {
    var report: PRReport

    var body: some View {
        if let problem = report.problem {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.updated.map { "Not updated since \($0.formatted(date: .omitted, time: .shortened))" }
                         ?? "Could not read GitHub")
                        .font(.system(size: 12, weight: .semibold))
                    Text(problem).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            } icon: {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
        }
    }
}

struct EmptyPRs: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(.green)
            Text("No Open Pull Requests").font(.system(size: 13, weight: .semibold))
            Text("Your merged and closed ones show here for a week while they are unread.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}

struct AllPRsRow: View {
    var action: () -> Void

    var body: some View {
        HoverRow(action: action) {
            HStack {
                Text("All Pull Requests")
                Spacer()
                Text("github.com").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
        }
    }
}
