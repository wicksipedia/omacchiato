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

    public init(now: Date, access: Bool, events: [Event]) {
        self.now = now
        self.access = access
        self.events = events
    }
}

public struct CalendarActions {
    public var openWeek: (Date) -> Void = { _ in }
    public var openEvent: (CalendarReport.Event) -> Void = { _ in }
    public var grantAccess: () -> Void = {}

    public init() {}
}

// One cell of the month grid. Days of the months around it are blank.
public struct MonthCell: Equatable {
    public var day: Int?
    public var today: Bool
}

// Weeks start on Monday. Each week carries its Monday, which a click on
// the week opens in Calendar.
public func monthWeeks(_ now: Date) -> [(monday: Date, cells: [MonthCell])] {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
          let days = cal.range(of: .day, in: .month, for: now) else { return [] }
    let today = cal.component(.day, from: now)
    let leading = (cal.component(.weekday, from: monthStart) + 5) % 7
    var cells = Array(repeating: MonthCell(day: nil, today: false), count: leading)
        + days.map { MonthCell(day: $0, today: $0 == today) }
    while cells.count % 7 != 0 { cells.append(MonthCell(day: nil, today: false)) }
    return stride(from: 0, to: cells.count, by: 7).map { week in
        (cal.date(byAdding: .day, value: week - leading, to: monthStart) ?? monthStart,
         Array(cells[week..<week + 7]))
    }
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
