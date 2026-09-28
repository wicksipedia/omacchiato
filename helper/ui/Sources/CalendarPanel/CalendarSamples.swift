import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Sample days for the Xcode previews and the settings window. Monday 28 September 2026, 10:40.
extension CalendarReport {
    public static let morning: Date = {
        var parts = DateComponents(year: 2026, month: 9, day: 28, hour: 10, minute: 40)
        parts.calendar = Calendar(identifier: .gregorian)
        return parts.date ?? Date()
    }()

    public static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: minute, second: 0, of: morning) ?? morning
    }

    public static let busy = CalendarReport(now: morning, access: true, events: [
        Event(id: "1", title: "1:1 with Sam", start: at(11), end: at(11, 30), repeats: true, color: .blue),
        Event(id: "2", title: "Design review: status and calendar panels", start: at(13), end: at(14),
              location: "Zoom", color: .purple),
        Event(id: "3", title: "Quarterly planning — infrastructure roadmap and hiring for next year",
              start: at(14, 30), end: at(16), location: "Level 4, Boardroom", color: .orange),
        Event(id: "4", title: "School pickup", start: at(15, 15), end: at(15, 45), color: .green),
        Event(id: "5", title: "Gym", start: at(17, 30), end: at(18, 30), repeats: true, color: .red),
    ])

    public static let holiday = CalendarReport(now: morning, access: true, events: [
        Event(id: "h", title: "Labour Day", start: at(0), end: at(23, 59), allDay: true, color: .green),
        Event(id: "h2", title: "Term 3 school holidays (between Term 3 and Term 4)", start: at(0), end: at(23, 59), allDay: true, color: .purple),
        Event(id: "h3", title: "Sukkot (Day 3)", start: at(0), end: at(23, 59), allDay: true, color: .indigo),
        Event(id: "h4", title: "Bin night", start: at(0), end: at(23, 59), allDay: true, color: .gray),
        Event(id: "6", title: "Coffee with Priya", start: at(10, 30), end: at(11, 15),
              location: "Single O Surry Hills", color: .teal),
    ])

    public static let free = CalendarReport(now: morning, access: true, events: [])
    public static let noAccess = CalendarReport(now: morning, access: false, events: [])
}
