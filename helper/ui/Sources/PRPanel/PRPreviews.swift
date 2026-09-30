#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

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

// Point at an unread dot, or swipe left on an unread row in the live preview.
extension PRActions {
    static var markable: PRActions {
        var actions = PRActions()
        actions.markRead = { _ in }
        return actions
    }
}

#Preview("Mark as read") { Desk { RemindersPRPanel(report: .busy, actions: .markable) } }
#Preview("Mark as read, Tracker") { Desk { TrackerPRPanel(report: .busy, actions: .markable) } }

#Preview("Mark as read: swiped") {
    Desk {
        PanelCard {
            PRRow(pr: PRReport.busy.prs[0], now: PRReport.morning, actions: .markable)
            PRRow(pr: PRReport.busy.prs[0], now: PRReport.morning, actions: .markable, revealed: true)
            PRRow(pr: PRReport.busy.prs[0], now: PRReport.morning, actions: .markable, marking: true)
        }
        .statusPanelBackground()
    }
}

#Preview("Stale") { Desk { RemindersPRPanel(report: .stale) } }
#endif
