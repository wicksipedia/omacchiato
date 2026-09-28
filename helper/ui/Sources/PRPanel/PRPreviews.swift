#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Sample lists for the previews. Monday 28 September 2026, 10:40.
extension PRReport {
    static let morning: Date = {
        var parts = DateComponents(year: 2026, month: 9, day: 28, hour: 10, minute: 40)
        parts.calendar = Calendar(identifier: .gregorian)
        return parts.date ?? Date()
    }()

    static func ago(_ hours: Double) -> Date { morning.addingTimeInterval(-hours * 3600) }

    static let busy = PRReport(now: morning, prs: [
        PR(repo: "acme/web", number: 482, title: "Move checkout to the new payments API",
           checks: .failed, checkCounts: [.passed: 11, .failed: 2], threads: 3, unread: true,
           additions: 612, deletions: 240, updated: ago(0.4)),
        PR(repo: "acme/web", number: 490, title: "Add Apple Pay to checkout", checks: .running,
           checkCounts: [.passed: 6, .running: 7], depth: 1, additions: 188, deletions: 12, updated: ago(1)),
        PR(repo: "acme/web", number: 471, title: "Fix the date picker on Safari 26", checks: .passed,
           review: .approved, unread: true, additions: 14, deletions: 9, updated: ago(3)),
        PR(repo: "acme/web", number: 455, title: "Spike: server components for the product page",
           draft: true, additions: 1_204, deletions: 380, updated: ago(96)),
        PR(repo: "acme/infra", number: 88, title: "Raise the API pods' memory limit to 1 GiB",
           checks: .passed, additions: 2, deletions: 2, updated: ago(20)),
        PR(repo: "acme/infra", number: 85, title: "Rotate the staging database credentials",
           checks: .passed, conflicts: true, additions: 40, deletions: 31, updated: ago(50)),
        PR(repo: "wicksipedia/omacchiato", number: 61, title: "Show the AI usage popup as a panel",
           state: .merged, unread: true, additions: 820, deletions: 90, updated: ago(2)),
    ], updated: ago(0.05))

    static let calm = PRReport(now: morning, prs: [
        PR(repo: "wicksipedia/omacchiato", number: 64, title: "Show the pull request popup as a panel",
           checks: .passed, review: .approved, additions: 540, deletions: 210, updated: ago(0.2)),
        PR(repo: "wicksipedia/omacchiato", number: 63, title: "Draw provider logos from their ink box",
           checks: .passed, additions: 30, deletions: 8, updated: ago(5)),
    ], updated: ago(0.05))

    static let empty = PRReport(now: morning, prs: [])

    static let offline = PRReport(now: morning, prs: calm.prs,
                                  problem: "error connecting to api.github.com", updated: ago(1.5))

    // GitHub answered, but long ago: an orange stamp, not StaleNote.
    static let stale = PRReport(now: morning, prs: calm.prs, updated: ago(0.4))
}

#Preview("Reminders") { Desk { RemindersPRPanel(report: .busy) } }
#Preview("Inbox") { Desk { InboxPRPanel(report: .busy) } }
#Preview("Tracker") { Desk { TrackerPRPanel(report: .busy) } }

#Preview("Reminders: every list") {
    Desk {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow { RemindersPRPanel(report: .busy); RemindersPRPanel(report: .calm) }
            GridRow { RemindersPRPanel(report: .empty); RemindersPRPanel(report: .offline) }
        }
    }
}

#Preview("Inbox: every list") {
    Desk {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow { InboxPRPanel(report: .busy); InboxPRPanel(report: .calm) }
            GridRow { InboxPRPanel(report: .empty); InboxPRPanel(report: .offline) }
        }
    }
}

#Preview("Tracker: every list") {
    Desk {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow { TrackerPRPanel(report: .busy); TrackerPRPanel(report: .calm) }
            GridRow { TrackerPRPanel(report: .empty); TrackerPRPanel(report: .offline) }
        }
    }
}

#Preview("Reminders, dark") { Desk { RemindersPRPanel(report: .busy) }.preferredColorScheme(.dark) }

#Preview("Stale") { Desk { RemindersPRPanel(report: .stale) } }
#endif
