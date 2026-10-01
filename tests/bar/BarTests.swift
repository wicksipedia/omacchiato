import AppKit
import CoreLocation
import Testing
@testable import omacchiato_bar
import BarPills
import CalendarPanel
import WeatherPanel

// Serialized: some tests set the global NSTimeZone.default.
@MainActor @Suite(.serialized)
struct BarTests {
    @Test("the weather pill opens its panel once a report has come in")
    func weatherPopup() {
        let saved = weatherReport
        defer { weatherReport = saved }
        weatherReport = nil
        #expect(!hasPopup("weather"))
        weatherReport = WeatherReport()
        #expect(hasPopup("weather"))
    }

    @Test("the weather asks wttr.in for a place rounded to two decimals")
    func weatherPlace() {
        #expect(weatherURL(nil).absoluteString == "https://wttr.in/?format=j1")
        #expect(weatherURL(CLLocationCoordinate2D(latitude: -32.93456, longitude: 151.71549)).absoluteString
            == "https://wttr.in/-32.93,151.72?format=j1")
    }

    @Test("windows on one frame keep the layout order")
    func parkedWindows() {
        #expect(layoutOrder([(1799, 12, "Voice Memos"), (1799, 12, "Notes")]) == ["Voice Memos", "Notes"])
    }

    @Test("the leftmost window comes first")
    func leftmostFirst() {
        #expect(layoutOrder([(900, 12, "Notes"), (6, 12, "Voice Memos")]) == ["Voice Memos", "Notes"])
    }

    @Test("a workspace chip widens by one step per extra card, up to three")
    func chipWidths() {
        #expect(chipWidth(cards: 0) == chipWidth(cards: 1))
        #expect(chipWidth(cards: 2) == chipWidth(cards: 1) + handStep)
        #expect(chipWidth(cards: 5) == chipWidth(cards: 3))
    }

    @Test("a click lands on the card under it, left to right")
    func handClick() {
        let slot = NSRect(x: 100, y: 0, width: 48, height: 34)
        #expect(handIndex(at: 100, in: slot, count: 3) == 0)
        #expect(handIndex(at: 124, in: slot, count: 3) == 1)
        #expect(handIndex(at: 148, in: slot, count: 3) == 2)
        #expect(handIndex(at: 130, in: slot, count: 1) == 0)
    }

    @Test("a hand holds three apps, each once")
    func hand() {
        #expect(handOf(["a", "b", "a", "c", "d"]) == ["a", "b", "c"])
    }

    @Test("a long row ends in … inside its room, and a short row stays whole")
    func fitRow() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let cut = fit(String(repeating: "wide ", count: 60), font, 200)
        #expect(advance(cut, font) <= 200)
        #expect(cut.hasSuffix("…"))
        #expect(fit("short", font, 200) == "short")
    }

    @Test("a closed section hides its rows and keeps its rule")
    func sections() {
        let rows = [PopupRow(text: "h", section: "closed"), PopupRow(text: "x"), PopupRow(separator: true),
                    PopupRow(text: "h2", section: "open"), PopupRow(text: "y")]
        #expect(foldSections("test", rows).map(\.text) == ["h", "", "h2", "y"])
        #expect(foldSections("test", rows).map(\.open) == [false, nil, true, nil])
    }

    @Test("plugin rows read subtitle, bar and bar_color")
    func pluginRows() throws {
        let row = try #require(pluginPopupRows(
            [["text": "claude", "subtitle": "max", "bar": 0.5, "bar_color": "red"]], of: BarPlugin()).first)
        #expect(row.subtitle == "max")
        #expect(row.inlineBar == 0.5)
        #expect(row.barTint != nil)
    }

    @Test("the month grid blanks other months' days and circles today")
    func monthGrid() throws {
        let cal = Calendar(identifier: .gregorian)
        let sep21 = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12)))
        let weeks = monthWeeks(sep21)
        #expect(weeks.first?.cells.map(\.day) == [nil, 1, 2, 3, 4, 5, 6])
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.cells.count == 7 })
        #expect(weeks.flatMap(\.cells).filter(\.today).map(\.day) == [21])
        #expect(cal.component(.weekday, from: weeks[0].monday) == 2)
    }

    @Test("events that overlap share the width, and a free lane is reused")
    func lanes() {
        let t = { (h: Double) in Date(timeIntervalSinceReferenceDate: h * 3600) }
        let spans = [(t(9), t(10)), (t(9.5), t(11)), (t(10), t(10.5)), (t(12), t(13))]
        let lanes = timelineLanes(spans.map { (start: $0.0, end: $0.1) })
        #expect(lanes.map(\.at) == [0, 1, 0, 0])
        #expect(lanes.map(\.of) == [2, 2, 2, 1])
    }

    @Test("a week link counts the day the clocks change")
    func daylightSaving() throws {
        let zone = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: "Australia/Sydney"))
        defer { NSTimeZone.default = zone }
        let cal = Calendar(identifier: .gregorian)
        let before = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12)))
        let after = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        #expect(dayOffset(from: before, to: after) == 2)
    }

    @Test("menu shortcuts read the modifier mask")
    func shortcuts() {
        #expect(shortcutText("Q", 4) == "⌃⌘Q")
        #expect(shortcutText("Q", 1) == "⇧⌘Q")
        #expect(shortcutText("F", 8) == "F")
    }

    @Test("menu bar apps sort by name and tell two icons of one app apart")
    func menuBarApps() {
        let titles = menuBarTitles([("OneDrive", "OneDrive - SSW"), ("Bartender", ""),
                                    ("OneDrive", "OneDrive - TinaCMS"), ("Zed", ""), ("Zed", "")])
        #expect(titles.map(\.text) == ["Bartender", "OneDrive · SSW", "OneDrive · TinaCMS", "Zed 1", "Zed 2"])
    }

    @Test("the OmniWM dev build counts as OmniWM")
    func omniWM() {
        #expect(isOmniWM("com.barut.OmniWM"))
        #expect(isOmniWM("com.barut.OmniWM.dev"))
        #expect(!isOmniWM("com.example"))
        #expect(!isOmniWM(nil))
    }

    @Test("a command that runs too long stops, and so does every process under it")
    func shellTimeout() {
        let start = Date()
        #expect(shell("/bin/sh", ["-c", "echo early; sleep 10"], timeout: 0.3) == "early\n")
        #expect(shell("/bin/sh", ["-c", "echo early; /bin/sh -c 'sleep 10; :'; :"], timeout: 0.3) == "early\n")
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(shell("/bin/echo", ["fast"], timeout: 5) == "fast\n")
    }

    @Test("a plugin runs once at a time, and requests during a run fold into one more run")
    func pluginGate() {
        var gate = RunGate()
        let steps = [gate.start("prs"), gate.start("prs"), gate.start("prs"), gate.start("usage"),
                     gate.finish("prs"), gate.start("prs"), gate.finish("prs"), gate.finish("usage")]
        #expect(steps == [true, false, false, true, true, true, false, false])
    }

    @Test("the clock names an event from 10 minutes before until 5 minutes after it starts")
    func soonEvent() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let labels = [11, 10, 4.5, 0, -4, -6].map { minutes in
            soonLabel(start: now.addingTimeInterval(minutes * 60), allDay: false, now: now)
        }
        #expect(labels == [nil, "in 10m", "in 5m", "now", "now", nil])
        #expect(soonLabel(start: now.addingTimeInterval(60), allDay: true, now: now) == nil)
    }

    @Test("a meeting link comes from the event URL, else a call link in the location or notes")
    func meetingLinks() {
        let own = URL(string: "https://example.com/event")!
        #expect(meetingLink(url: own, location: nil, notes: nil) == own)
        #expect(meetingLink(url: nil, location: "Room 4", notes: "Join: <https://acme.zoom.us/j/123?pwd=x> thanks")
                == URL(string: "https://acme.zoom.us/j/123?pwd=x"))
        #expect(meetingLink(url: nil, location: "https://teams.microsoft.com/l/meetup-join/abc", notes: nil)?.host
                == "teams.microsoft.com")
        #expect(meetingLink(url: nil, location: "https://evil.com/zoom.us", notes: "http://zoom.us/j/1") == nil)
    }

    @Test("arrow keys step through the clickable rows and wrap at the ends")
    func popupSelection() {
        let rows = [1, 3, 4]
        #expect(nextSelection(rows, from: nil, by: 1) == 1)
        #expect(nextSelection(rows, from: nil, by: -1) == 4)
        #expect(nextSelection(rows, from: 3, by: 1) == 4)
        #expect(nextSelection(rows, from: 4, by: 1) == 1)
        #expect(nextSelection(rows, from: 1, by: -1) == 4)
        #expect(nextSelection(rows, from: 2, by: 1) == 1)
        #expect(nextSelection([], from: nil, by: 1) == nil)
    }

    @Test("execute returns stderr and the exit status, and marks a timeout")
    func executeResult() {
        let failed = execute("/bin/sh", ["-c", "echo oops >&2; exit 3"])
        #expect(failed.err == "oops\n")
        #expect(failed.status == 3)
        #expect(!failed.timedOut)
        #expect(execute("/bin/sh", ["-c", "sleep 5"], timeout: 0.2).timedOut)
    }

    @Test("a plugin run fails on a timeout, or on a non-zero exit with no output")
    func pluginProblems() {
        #expect(pluginProblem(ShellResult(out: "3", status: 0), limit: 30) == nil)
        #expect(pluginProblem(ShellResult(out: "{\"label\":\"x\"}", status: 1), limit: 30) == nil)
        let exit = pluginProblem(ShellResult(err: "sh: gh: command not found\nmore", status: 127), limit: 30)
        #expect(exit?.what == "failed with exit 127")
        #expect(exit?.detail == "sh: gh: command not found")
        #expect(pluginProblem(ShellResult(timedOut: true), limit: 120)?.what == "no answer in 120 s")
    }

    @Test("an event row links to the event in Calendar, with the occurrence for a repeating one")
    func calendarLinks() {
        let start = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        #expect(calendarLink(id: "ABC-1", start: start, repeats: false)?.absoluteString
                == "ical://ekevent/ABC-1?method=show&options=more")
        #expect(calendarLink(id: "ABC-1", start: start, repeats: true)?.absoluteString
                == "ical://ekevent/20260921T141320Z/ABC-1?method=show&options=more")
    }

    @Test("a clear pill still takes clicks")
    func clickable() {
        #expect(NSColor.clear.clickable.alphaComponent > 0)
    }
}

@Suite struct MenuBadgeTests {
    @Test("an update count in a menu title becomes a badge, as the macOS menu draws it")
    func badge() {
        #expect(menuBadge("System Settings…, 1 update") == ("System Settings…", "1 update"))
        #expect(menuBadge("System Settings…, 12 updates") == ("System Settings…", "12 updates"))
        #expect(menuBadge("System Settings…") == ("System Settings…", ""))
        #expect(menuBadge("Log Out Matt Wicks…") == ("Log Out Matt Wicks…", ""))
    }

    @Test("a command that closes its pipes and hangs still times out")
    func executeTimesOut() {
        let started = Date()
        let result = execute("/bin/sh", ["-c", "echo hi; exec >&- 2>&-; sleep 30"], timeout: 1)
        #expect(result.timedOut)
        #expect(result.out == "hi\n")
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("a child that ignores SIGTERM still dies when its shell does")
    func executeKillsChild() {
        let started = Date()
        let result = execute("/bin/sh", ["-c", "(trap '' TERM; sleep 31.25) & wait"], timeout: 1)
        #expect(result.timedOut)
        #expect(Date().timeIntervalSince(started) < 6)
        // launchd reaps the killed orphan a moment later
        var left = "x"
        for _ in 0..<20 where !left.isEmpty {
            left = shell("/usr/bin/pgrep", ["-xf", "sleep 31.25"])
            if !left.isEmpty { usleep(50_000) }
        }
        #expect(left.isEmpty)
    }

    @Test("a child that ignores SIGTERM and closes its pipes still dies")
    func executeKillsQuietChild() {
        _ = execute("/bin/sh", ["-c", "(trap '' TERM; exec >/dev/null 2>&1; sleep 31.75) & wait"], timeout: 1)
        var left = "x"
        for _ in 0..<20 where !left.isEmpty {
            left = shell("/usr/bin/pgrep", ["-xf", "sleep 31.75"])
            if !left.isEmpty { usleep(50_000) }
        }
        #expect(left.isEmpty)
    }

    @Test("a quick command returns its output and status")
    func executeReturns() {
        let result = execute("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: 5)
        #expect((result.out, result.err, result.status, result.timedOut) == ("out\n", "err\n", 3, false))
    }
}
