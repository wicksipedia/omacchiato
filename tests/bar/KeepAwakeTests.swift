import Foundation
import Testing
@testable import omacchiato_bar

@Suite struct KeepAwakeTests {
    let now = Date(timeIntervalSince1970: 100)

    @Test("the state file reads as off, on, or on until an end time, as the script reads it")
    func state() {
        #expect(keepAwakeNow(state: "", now: now) == .off)
        #expect(keepAwakeNow(state: "off\n", now: now) == .off)
        #expect(keepAwakeNow(state: "on\n", now: now) == .on(until: nil))
        #expect(keepAwakeNow(state: "400\n", now: now) == .on(until: Date(timeIntervalSince1970: 400)))
        #expect(keepAwakeNow(state: "junk", now: now) == .off)
    }

    @Test("an end time in the past reads as off")
    func expired() {
        #expect(keepAwakeNow(state: "99", now: now) == .off)
    }

    @Test("the HUD says how long keep awake lasts, or why it ended")
    func hudDetail() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let at = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 17, minute: 30))!
        #expect(keepAwakeDetail(.on(until: nil), reason: nil, timeZone: calendar.timeZone, locale: Locale(identifier: "en_US")) == "Until turned off")
        #expect(keepAwakeDetail(.on(until: at), reason: nil, timeZone: calendar.timeZone, locale: Locale(identifier: "en_US")) == "Until 5:30\u{202F}PM") // macOS puts a narrow no-break space before PM
        #expect(keepAwakeDetail(.off, reason: "Timer ended", timeZone: calendar.timeZone, locale: Locale(identifier: "en_US")) == "Timer ended")
        #expect(keepAwakeDetail(.off, reason: nil, timeZone: calendar.timeZone, locale: Locale(identifier: "en_US")) == "Turned off")
    }
}
