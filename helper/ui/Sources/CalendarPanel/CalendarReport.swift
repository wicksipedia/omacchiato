import SwiftUI

// What the clock popup shows: this month, and what is left of today. The
// bar reads the events with EventKit, and the previews build them by hand.
public struct CalendarReport {
    public struct Event: Identifiable {
        public var id: String
        public var title: String
        public var start: Date
        public var end: Date
        public var allDay: Bool
        public var repeats: Bool
        public var location: String?
        public var color: Color

        public init(id: String, title: String, start: Date, end: Date, allDay: Bool = false,
                    repeats: Bool = false, location: String? = nil, color: Color = .blue) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.allDay = allDay
            self.repeats = repeats
            self.location = location
            self.color = color
        }
    }

    public var now: Date
    public var access: Bool          // the Calendars grant
    public var events: [Event]       // what is left of today, by start time
    public var marks: [Date: [Color]] // each day's events as calendar colors, keyed by the start of the day

    public init(now: Date, access: Bool, events: [Event], marks: [Date: [Color]] = [:]) {
        self.now = now
        self.access = access
        self.events = events
        self.marks = marks
    }
}

public struct CalendarActions {
    public var openWeek: (Date) -> Void = { _ in }
    public var openEvent: (CalendarReport.Event) -> Void = { _ in }
    public var grantAccess: () -> Void = {}
    public var showMonth: (Date) -> Void = { _ in }   // the grid moved to the month of this date

    public init() {}
}

// One cell of the month grid. Days of the months around it are blank.
public struct MonthCell: Equatable {
    public var day: Int?
    public var today: Bool
    public var date: Date?           // the start of the day
}

// Weeks start on Monday. Each week carries its Monday, which a click on
// the week opens in Calendar. Today is circled only in its own month.
public func monthWeeks(_ month: Date, today now: Date? = nil) -> [(monday: Date, cells: [MonthCell])] {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)),
          let days = cal.range(of: .day, in: .month, for: month) else { return [] }
    let now = now ?? month
    let today = cal.isDate(now, equalTo: month, toGranularity: .month) ? cal.component(.day, from: now) : nil
    let leading = (cal.component(.weekday, from: monthStart) + 5) % 7
    let blank = MonthCell(day: nil, today: false, date: nil)
    var cells = Array(repeating: blank, count: leading)
        + days.map { MonthCell(day: $0, today: $0 == today,
                               date: cal.date(byAdding: .day, value: $0 - 1, to: monthStart)) }
    while cells.count % 7 != 0 { cells.append(blank) }
    return stride(from: 0, to: cells.count, by: 7).map { week in
        (cal.date(byAdding: .day, value: week - leading, to: monthStart) ?? monthStart,
         Array(cells[week..<week + 7]))
    }
}

// The first day of the month n months from the month of date.
public func shiftMonth(_ date: Date, by n: Int) -> Date {
    let cal = Calendar(identifier: .gregorian)
    let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    return cal.date(byAdding: .month, value: n, to: start) ?? start
}

// Each day's events as their colors, keyed by the start of the day. An
// event marks every day it touches, and its end is exclusive, so an
// all-day event that ends at midnight marks only its own days. Give the
// events in the order the marks show.
public func dayMarks(_ spans: [(start: Date, end: Date, color: Color)]) -> [Date: [Color]] {
    let cal = Calendar(identifier: .gregorian)
    var marks: [Date: [Color]] = [:]
    for span in spans {
        var day = cal.startOfDay(for: span.start)
        repeat {
            marks[day, default: []].append(span.color)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        } while day < span.end
    }
    return marks
}

// How long until the next event: the clock time is already in the row.
public func countdown(to start: Date, allDay: Bool, now: Date) -> String? {
    if allDay { return nil }
    let left = start.timeIntervalSince(now)
    if left <= 0 { return "Now" }
    if left < 3600 { return "in \(Int(left / 60)) min" }
    if left < 12 * 3600 { return "in \(Int(left / 3600)) h" }
    return nil
}
