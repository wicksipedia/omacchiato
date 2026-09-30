import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Pieces that every design of the pull request panel shares.

extension PRReport.PR {
    var tint: Color { state == .closed ? .secondary : stage.tint }
}

// Mail's unread dot. With an action, it turns into a check under the
// pointer, and a click marks the PR read.
struct UnreadDot: View {
    var pr: PRReport.PR
    var actions: PRActions
    @State private var hovered = false
    @State private var marked = false

    var body: some View {
        if let markRead = actions.markRead, pr.markRead != nil {
            ZStack {
                if marked {
                    Spinner(color: PanelColors.accent).frame(width: 12, height: 12)
                } else if hovered {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PanelColors.accent)
                } else {
                    Circle().fill(PanelColors.accent).frame(width: 8, height: 8)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .onTapGesture {
                guard !marked else { return }
                marked = true
                markRead(pr)
            }
            // if the row is still here after 15 s, the mark failed
            .task(id: marked) {
                guard marked else { return }
                try? await Task.sleep(for: .seconds(15))
                marked = false
            }
            .help("Mark as Read")
            .accessibilityLabel("Mark as Read")
            .accessibilityAddTraits(.isButton)
        } else {
            Circle().fill(PanelColors.accent).frame(width: 8, height: 8)
                .accessibilityLabel("Updated")
        }
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
            Text("+\(pr.additions)").foregroundStyle(PanelColors.green)
            Text("−\(pr.deletions)").foregroundStyle(PanelColors.red)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(total == 0 ? AnyShapeStyle(.fill.secondary)
                              : AnyShapeStyle(i < green ? PanelColors.green : PanelColors.red))
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
    var revealed = false        // the previews draw the row swiped open,
    var marking = false         // or waiting on GitHub

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
                        if pr.state == .open { DiffSize(pr: pr).fixedSize() }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if let note = pr.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(pr.stage == .needsYou ? AnyShapeStyle(PanelColors.red) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                    }
                }
                VStack(alignment: .trailing, spacing: 4) {
                    Text(ageText(pr.updated, now: now))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    if pr.unread { UnreadDot(pr: pr, actions: actions) }
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
        .modifier(SwipeToMarkRead(pr: pr, actions: actions, revealed: revealed, marking: marking))
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
    var refresh: (() -> Void)?
    @State private var retrying = false

    var body: some View {
        if let problem = report.problem {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.updated.map { "Not updated since \($0.formatted(date: .omitted, time: .shortened))" }
                         ?? "Could not read GitHub")
                        .font(.system(size: 12, weight: .semibold))
                    Text(problem).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    if let refresh {
                        Text(retrying ? "Trying again…" : "Try Again")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PanelColors.accent)
                            .padding(.top, 3)
                            .contentShape(.rect)
                            .onTapGesture {
                                guard !retrying else { return }
                                retrying = true
                                refresh()
                            }
                            .accessibilityAddTraits(.isButton)
                    }
                }
            } icon: {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(PanelColors.orange)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelColors.orange.opacity(0.12), in: .rect(cornerRadius: 12))
            .onChange(of: report.updated) { retrying = false }
            .task(id: retrying) {
                guard retrying else { return }
                try? await Task.sleep(for: .seconds(30))
                retrying = false
            }
        }
    }
}

struct EmptyPRs: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(PanelColors.green)
            Text("No Open Pull Requests").font(.system(size: 13, weight: .semibold))
            Text("Your merged and closed ones show here for a week while they are unread.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}

// Mail's swipe: two fingers to the left on a row show a Read button, and
// a long swipe marks the PR read at once. A horizontal scroll
// view reads the swipe, because it gets scroll events in a window that
// never becomes key.
struct SwipeToMarkRead: ViewModifier {
    var pr: PRReport.PR
    var actions: PRActions
    var revealed = false
    @State var marking = false
    @State private var position = ScrollPosition(edge: .leading)

    static let reveal: CGFloat = 72

    func body(content: Content) -> some View {
        if let markRead = actions.markRead, pr.markRead != nil {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    content
                        .opacity(marking ? 0.45 : 1)
                        .containerRelativeFrame(.horizontal)
                    Button { mark(markRead) } label: {
                        VStack(spacing: 2) {
                            if marking {
                                Spinner().frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "envelope.open.fill").font(.system(size: 13))
                            }
                            Text(marking ? "Marking" : "Read").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: Self.reveal)
                        .frame(maxHeight: .infinity)
                        .background(PanelColors.accent.opacity(marking ? 0.7 : 1), in: .rect(cornerRadius: 7))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(marking)
                    .accessibilityLabel(marking ? "Marking as Read" : "Mark as Read")
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position)
            .scrollDisabled(marking)
            .defaultScrollAnchor(revealed || marking ? .trailing : .leading)
            // the rubber band past the button is the long swipe
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.x > geo.contentSize.width - geo.containerSize.width + Self.reveal
            } action: { _, past in
                if past { mark(markRead) }
            }
            // The row goes when the list reads GitHub again. If it is still
            // here after 15 s, the mark failed, so offer the button again.
            .task(id: marking) {
                guard marking else { return }
                try? await Task.sleep(for: .seconds(15))
                marking = false
                withAnimation(.snappy(duration: 0.2)) { position.scrollTo(edge: .leading) }
            }
        } else {
            content
        }
    }

    func mark(_ markRead: (PRReport.PR) -> Void) {
        guard !marking else { return }
        marking = true
        withAnimation(.snappy(duration: 0.2)) { position.scrollTo(edge: .trailing) }
        markRead(pr)
    }
}

// Drawn by hand: a system spinner draws grey in a window that is not key.
struct Spinner: View {
    var color: Color = .white
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

extension View {
    func swipeToMarkRead(_ pr: PRReport.PR, _ actions: PRActions) -> some View {
        modifier(SwipeToMarkRead(pr: pr, actions: actions))
    }
}
