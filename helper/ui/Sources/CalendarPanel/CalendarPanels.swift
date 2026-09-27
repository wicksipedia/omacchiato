import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the clock popup, to compare in the previews. Each one
// shows the month and what is left of today, and offers the same clicks.

private func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

// The month grid. A click on a week opens that week in Calendar.
struct MonthGrid: View {
    var now: Date
    var openWeek: (Date) -> Void
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            ForEach(Array(monthWeeks(now).enumerated()), id: \.offset) { _, week in
                HoverRow(action: { openWeek(week.monday) }) {
                    HStack(spacing: 0) {
                        ForEach(Array(week.cells.enumerated()), id: \.offset) { index, cell in
                            Text(cell.day.map(String.init) ?? "")
                                .font(.system(size: compact ? 11 : 13, weight: cell.today ? .bold : .regular))
                                .foregroundStyle(cell.today ? AnyShapeStyle(.white)
                                                 : (index >= 5 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
                                .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                                .background(cell.today ? AnyShapeStyle(Color.red) : AnyShapeStyle(.clear), in: .circle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

// One event: a bar in the calendar's colour, the title, the time and the
// place. The next event says how long you have.
struct EventRow: View {
    var event: CalendarReport.Event
    var now: Date
    var next: Bool
    var open: (CalendarReport.Event) -> Void

    var body: some View {
        HoverRow(action: { open(event) }) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text(event.allDay ? "All day" : "\(timeText(event.start)) – \(timeText(event.end))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let place = event.location, !place.isEmpty {
                        Label(place, systemImage: "mappin")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if next, let left = countdown(to: event.start, allDay: event.allDay, now: now) {
                    Text(left)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(event.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(event.color.opacity(0.18), in: .capsule)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// What the events area says when there is nothing to list.
struct EventsEmpty: View {
    var report: CalendarReport
    var grant: () -> Void

    var body: some View {
        if !report.access {
            HoverRow(action: grant) {
                Label("Allow access to see today's events", systemImage: "calendar.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Nothing left today", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}

// "Up Next": the date large, the next event as the hero, the rest of the
// day under it, and a small month at the bottom. Like the iOS Calendar
// widget.
public struct UpNextCalendarPanel: View {
    var report: CalendarReport
    var actions: CalendarActions

    public init(report: CalendarReport, actions: CalendarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(report.now.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                    Text(report.now.formatted(.dateTime.day()))
                        .font(.system(size: 44, weight: .light))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(report.now.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Week \(Calendar(identifier: .iso8601).component(.weekOfYear, from: report.now))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            PanelCard(title: "Today", symbol: "calendar") {
                if report.events.isEmpty {
                    EventsEmpty(report: report, grant: actions.grantAccess)
                } else {
                    ForEach(Array(report.events.prefix(6).enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, now: report.now, next: index == 0, open: actions.openEvent)
                    }
                }
            }
            PanelCard {
                MonthGrid(now: report.now, openWeek: actions.openWeek, compact: true)
            }
        }
        .statusPanelBackground()
    }
}

// "Month": the month grid first and large, like the iOS Calendar month
// view, with today's events under it.
public struct MonthCalendarPanel: View {
    var report: CalendarReport
    var actions: CalendarActions

    public init(report: CalendarReport, actions: CalendarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.now.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.red)
                Text(report.now.formatted(.dateTime.year()))
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Text("Week \(Calendar(identifier: .iso8601).component(.weekOfYear, from: report.now))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            MonthGrid(now: report.now, openWeek: actions.openWeek)
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(report.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
                if report.events.isEmpty {
                    EventsEmpty(report: report, grant: actions.grantAccess)
                } else {
                    ForEach(Array(report.events.prefix(6).enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, now: report.now, next: index == 0, open: actions.openEvent)
                    }
                }
            }
        }
        .statusPanelBackground()
    }
}

// "Timeline": the rest of the day as blocks on an hour scale, like the
// iOS Calendar day view, with the month beside the date at the top.
public struct TimelineCalendarPanel: View {
    var report: CalendarReport
    var actions: CalendarActions

    public init(report: CalendarReport, actions: CalendarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    // One hour on the scale, in points, and the width the events share.
    let hour: CGFloat = 34
    let laneWidth: CGFloat = 340 - 24 - 8 - 44

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(report.now.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                    Text(report.now.formatted(.dateTime.day()))
                        .font(.system(size: 38, weight: .light))
                    Text(report.now.formatted(.dateTime.month(.wide)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                MonthGrid(now: report.now, openWeek: actions.openWeek, compact: true)
            }
            .padding(.horizontal, 4)
            let allDay = report.events.filter(\.allDay)
            if !allDay.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(allDay.prefix(3)) { event in
                        HoverRow(action: { actions.openEvent(event) }) {
                            HStack(spacing: 6) {
                                Circle().fill(event.color).frame(width: 7, height: 7)
                                Text(event.title).lineLimit(1)
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                    }
                    if allDay.count > 3 {
                        Text("+\(allDay.count - 3) more all day")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                    }
                }
            }
            let timed = report.events.filter { !$0.allDay }
            if timed.isEmpty {
                PanelCard { EventsEmpty(report: report, grant: actions.grantAccess) }
            } else {
                timeline(timed)
            }
        }
        .statusPanelBackground(width: 340)
    }

    func timeline(_ events: [CalendarReport.Event]) -> some View {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .hour, for: report.now)?.start ?? report.now
        let last = events.map(\.end).max() ?? first
        let hours = max(3, min(8, Int(ceil(last.timeIntervalSince(first) / 3600))))
        func y(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(first) / 3600) * hour }
        return ZStack(alignment: .topLeading) {
            ForEach(0...hours, id: \.self) { step in
                let at = first.addingTimeInterval(Double(step) * 3600)
                HStack(spacing: 6) {
                    Text(at.formatted(.dateTime.hour()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Rectangle().fill(.separator).frame(height: 0.5)
                }
                .offset(y: CGFloat(step) * hour - 6)
            }
            let lanes = timelineLanes(events.map { ($0.start, $0.end) })
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                let top = max(0, y(event.start))
                let lane = lanes[index]
                let height = max(22, min(y(event.end), CGFloat(hours) * hour) - top - 2)
                HoverRow(action: { actions.openEvent(event) }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if height > 34 {
                            Text("\(timeText(event.start)) – \(timeText(event.end))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: (laneWidth - 2) / CGFloat(lane.of), height: height, alignment: .topLeading)
                .background(event.color.opacity(0.22), in: .rect(cornerRadius: 6))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3)
                }
                .offset(x: 44 + laneWidth / CGFloat(lane.of) * CGFloat(lane.at), y: top)
            }
            // now, in red, as in the iOS day view
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .padding(.leading, 40)
            .offset(y: y(report.now) - 3.5)
        }
        .frame(height: CGFloat(hours) * hour, alignment: .top)
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }
}

// Events that overlap share the width side by side, as in the iOS day
// view. Each event gets the first free lane, and the number of lanes of
// the group of overlapping events it belongs to.
public func timelineLanes(_ spans: [(start: Date, end: Date)]) -> [(at: Int, of: Int)] {
    var result = Array(repeating: (at: 0, of: 1), count: spans.count)
    var group: [Int] = []
    var laneEnds: [Date] = []
    func close() {
        for i in group { result[i].of = laneEnds.count }
        group = []
        laneEnds = []
    }
    for (i, span) in spans.enumerated() {
        if !laneEnds.isEmpty, laneEnds.allSatisfy({ $0 <= span.start }) { close() }
        if let free = laneEnds.firstIndex(where: { $0 <= span.start }) {
            laneEnds[free] = span.end
            result[i].at = free
        } else {
            laneEnds.append(span.end)
            result[i].at = laneEnds.count - 1
        }
        group.append(i)
    }
    close()
    return result
}
