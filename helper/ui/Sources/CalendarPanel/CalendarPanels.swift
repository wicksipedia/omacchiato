import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the same clock popup, to compare in the previews.
// Each shows the month and what is left of today, with the same actions.

private func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

// The month grid. A click on a week opens that week in Calendar. Under
// each day, its events show as colored bars, as in the iPhone's month
// view. With a step action, a row above the grid moves between months.
struct MonthGrid: View {
    var now: Date
    var month: Date
    var marks: [Date: [Color]]
    var openWeek: (Date) -> Void
    var step: ((Int) -> Void)?
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            if let step {
                MonthTitle(now: now, month: month, step: step)
                    .font(.system(size: compact ? 12 : 15, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
            }
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            ForEach(Array(monthWeeks(month, today: now).enumerated()), id: \.offset) { _, week in
                HoverRow(action: { openWeek(week.monday) }) {
                    HStack(spacing: 0) {
                        ForEach(Array(week.cells.enumerated()), id: \.offset) { index, cell in
                            VStack(spacing: 2) {
                                Text(cell.day.map(String.init) ?? "")
                                    .font(.system(size: compact ? 11 : 13, weight: cell.today ? .bold : .regular))
                                    .foregroundStyle(cell.today ? AnyShapeStyle(.white)
                                                     : (index >= 5 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
                                    .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                                    .background(cell.today ? AnyShapeStyle(Color.red) : AnyShapeStyle(.clear), in: .circle)
                                if !marks.isEmpty {
                                    DayMarks(colors: cell.date.flatMap { marks[$0] } ?? [])
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

// The month and year, with arrows to the months around it. A click on
// the title of another month goes back to this month.
struct MonthTitle: View {
    var now: Date
    var month: Date
    var step: (Int) -> Void
    var big = false

    var body: some View {
        let away = !Calendar(identifier: .gregorian).isDate(month, equalTo: now, toGranularity: .month)
        HStack(alignment: .firstTextBaseline, spacing: big ? 6 : 4) {
            Text(month.formatted(.dateTime.month(.wide)))
                .foregroundStyle(big ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
            Text(month.formatted(.dateTime.year()))
            Spacer(minLength: 4)
            if away {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                    .contentShape(.rect)
                    .onTapGesture { step(0) }
                    .accessibilityAddTraits(.isButton)
            }
            arrow("chevron.left", label: "Previous Month") { step(-1) }
            arrow("chevron.right", label: "Next Month") { step(1) }
        }
    }

    func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 20)
            .hoverFill(radius: 5)
            .contentShape(.rect)
            .onTapGesture(perform: action)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

// A day's events: two bars, then the count of the rest. The space stays
// the same on an empty day, so the rows line up.
struct DayMarks: View {
    var colors: [Color]

    var body: some View {
        VStack(spacing: 1.5) {
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(i < colors.count ? AnyShapeStyle(colors[i].opacity(0.75)) : AnyShapeStyle(.clear))
                    .frame(height: 3)
            }
            Text(colors.count > 2 ? "+\(colors.count - 2)" : " ")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 8)
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(colors.isEmpty ? "" : "\(colors.count) event\(colors.count == 1 ? "" : "s")")
    }
}

// One event: a colored bar, the title, the time, and the place.
// The next event also shows a countdown.
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

// "Up Next": big date, next event as hero, rest of today below, small month at bottom, like iOS Calendar's widget.
public struct UpNextCalendarPanel: View {
    var report: CalendarReport
    var actions: CalendarActions
    @State private var offset = 0

    public init(report: CalendarReport, actions: CalendarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    func step(_ n: Int) {
        offset = n == 0 ? 0 : offset + n
        actions.showMonth(shiftMonth(report.now, by: offset))
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
                MonthGrid(now: report.now, month: shiftMonth(report.now, by: offset), marks: report.marks,
                          openWeek: actions.openWeek, step: step, compact: true)
            }
        }
        .statusPanelBackground()
    }
}

// "Month": the month grid first and large, like the iOS Calendar month view, with today's events below.
public struct MonthCalendarPanel: View {
    var report: CalendarReport
    var actions: CalendarActions
    @State private var offset = 0

    public init(report: CalendarReport, actions: CalendarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    func step(_ n: Int) {
        offset = n == 0 ? 0 : offset + n
        actions.showMonth(shiftMonth(report.now, by: offset))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonthTitle(now: report.now, month: shiftMonth(report.now, by: offset), step: step, big: true)
                .font(.system(size: 24, weight: .bold))
                .padding(.horizontal, 6)
            MonthGrid(now: report.now, month: shiftMonth(report.now, by: offset), marks: report.marks,
                      openWeek: actions.openWeek)
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

// "Timeline": rest of day as blocks on an hour scale, like iOS Calendar's day view, under the month.
public struct TimelineCalendarPanel: View {
    var report: CalendarReport
    var actions: CalendarActions
    @State private var offset = 0

    public init(report: CalendarReport, actions: CalendarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    // One hour on the scale, in points, and the width the events share.
    let hour: CGFloat = 34
    let laneWidth: CGFloat = 340 - 24 - 8 - 44

    func step(_ n: Int) {
        offset = n == 0 ? 0 : offset + n
        actions.showMonth(shiftMonth(report.now, by: offset))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonthGrid(now: report.now, month: shiftMonth(report.now, by: offset), marks: report.marks,
                      openWeek: actions.openWeek, step: step)
            // the events below are today's, whatever month the grid shows
            Text(report.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 6)
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

// Overlapping events share the width side by side, like iOS Calendar's day view.
// Each event gets the first free lane. `of` is the lane count for its group of overlaps.
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
