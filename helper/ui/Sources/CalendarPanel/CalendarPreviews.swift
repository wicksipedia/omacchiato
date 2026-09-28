#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

private let days: [CalendarReport] = [.busy, .holiday, .free, .noAccess]

#Preview("Up Next") { Desk { UpNextCalendarPanel(report: .busy) } }
#Preview("Month") { Desk { MonthCalendarPanel(report: .busy) } }
#Preview("Timeline") { Desk { TimelineCalendarPanel(report: .busy) } }

#Preview("Up Next: every day") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(days.indices, id: \.self) { UpNextCalendarPanel(report: days[$0]) } } }
}

#Preview("Month: every day") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(days.indices, id: \.self) { MonthCalendarPanel(report: days[$0]) } } }
}

#Preview("Timeline: every day") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(days.indices, id: \.self) { TimelineCalendarPanel(report: days[$0]) } } }
}

#Preview("Up Next, dark") { Desk { UpNextCalendarPanel(report: .busy) }.preferredColorScheme(.dark) }
#endif
