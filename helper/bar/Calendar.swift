import ApplicationServices
import AppKit
import CoreAudio
import CoreBluetooth
import CoreLocation
import CoreWLAN
import EventKit
import IOBluetooth
import IOKit.ps
import SystemConfiguration
import UniformTypeIdentifiers
// swiftc builds helper/ui into this module, and SwiftPM builds it as its own.
import SwiftUI
#if canImport(StatusGauge)
import StatusGauge
import ActivityPanel
import BarPills
import AIUsagePanel
import CalendarPanel
import MenuBarPanel
import PRPanel
import RowsPanel
import StatusPanel
import ThemePanel
import WeatherPanel
#endif

// --- calendar --------------------------------------------------------------
// A day with a clock change is 23 or 25 hours, so day count from
// seconds / 86400 is off by one. Count whole days on the calendar instead.
func dayOffset(from now: Date, to date: Date) -> Int {
    let cal = Calendar(identifier: .gregorian)
    return cal.dateComponents([.day], from: cal.startOfDay(for: now),
                              to: cal.startOfDay(for: date)).day ?? 0
}

// AppleScript takes a date string, which parses in the app's locale, so
// this passes a day offset from midday instead. Midday keeps the same
// day across a change of daylight saving.
func openCalendarWeek(of date: Date) {
    let days = dayOffset(from: Date(), to: date)
    let script = """
    tell application "Calendar"
        activate
        switch view to week view
        view calendar at ((current date) - (time of (current date)) + 12 * hours + \(days) * days)
    end tell
    """
    closePopup()
    DispatchQueue.global(qos: .userInitiated).async { _ = shell("/usr/bin/osascript", ["-e", script]) }
}

var eventStore: EKEventStore?
var todayEvents: [EKEvent] = []
var eventsDay: Date?
var eventsAt: TimeInterval = 0
var eventsLoading = false

// Never touch EventKit before the grant is there: a launchd agent would
// raise the dialog with nothing on screen to explain it. The fetch costs
// enough to keep off the main thread, and one answer serves for a minute.
func loadTodayEvents() {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, !eventsLoading else { return }
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    if eventsDay == start, Date.timeIntervalSinceReferenceDate - eventsAt < 60 { return }
    eventsLoading = true
    let store = eventStore ?? EKEventStore()
    eventStore = store
    DispatchQueue.global(qos: .userInitiated).async {
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                    calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        DispatchQueue.main.async {
            todayEvents = found
            eventsDay = start
            eventsAt = Date.timeIntervalSinceReferenceDate
            eventsLoading = false
            updateClock()
            if openPopup == "clock" { refreshPopup() }
        }
    }
}

// The marks of each month that the grid has shown, keyed by the first of
// the month. Like today's events, one answer serves for a minute.
var monthMarks: [Date: (at: TimeInterval, marks: [Date: [Color]])] = [:]
var monthsLoading: Set<Date> = []
var shownMonth: Date?   // the month that the open grid shows, when not this month

func loadMonth(_ date: Date) {
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
    let start = shiftMonth(date, by: 0)
    let end = shiftMonth(date, by: 1)
    if let cached = monthMarks[start], Date.timeIntervalSinceReferenceDate - cached.at < 60 { return }
    guard !monthsLoading.contains(start) else { return }
    monthsLoading.insert(start)
    let store = eventStore ?? EKEventStore()
    eventStore = store
    DispatchQueue.global(qos: .userInitiated).async {
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        // an event that starts before the month marks only the month's days
        let marks = dayMarks(events.map { event in
            (start: max(event.startDate, start), end: event.endDate,
             color: event.calendar.cgColor.map { Color(cgColor: $0) } ?? .blue)
        }).filter { $0.key >= start && $0.key < end }
        DispatchQueue.main.async {
            monthMarks[start] = (Date.timeIntervalSinceReferenceDate, marks)
            monthsLoading.remove(start)
            if openPopup == "clock" { refreshPopup() }
        }
    }
}

func calendarReport() -> CalendarReport {
    let now = Date()
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
        return CalendarReport(now: now, access: false, events: [])
    }
    loadTodayEvents()
    loadMonth(now)
    if let shownMonth { loadMonth(shownMonth) }
    let marks = monthMarks.values.reduce(into: [Date: [Color]]()) { all, month in all.merge(month.marks) { a, _ in a } }
    return CalendarReport(now: now, access: true, events: todayEvents.filter { $0.endDate > now }.map { event in
        CalendarReport.Event(id: event.calendarItemIdentifier, title: event.title ?? "Event",
                             start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                             repeats: event.hasRecurrenceRules, location: event.location,
                             color: event.calendar.cgColor.map { Color(cgColor: $0) } ?? .blue)
    }, marks: marks)
}

let calendarActions: CalendarActions = {
    var actions = CalendarActions()
    actions.openWeek = openCalendarWeek(of:)
    actions.showMonth = { month in
        shownMonth = month
        loadMonth(month)
    }
    actions.openEvent = { event in
        guard let link = calendarLink(id: event.id, start: event.start, repeats: event.repeats) else { return }
        closePopup()
        NSWorkspace.shared.open(link)
    }
    actions.grantAccess = {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        closePopup()
    }
    return actions
}()
