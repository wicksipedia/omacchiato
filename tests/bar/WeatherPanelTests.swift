import Foundation
import Testing
@testable import WeatherPanel

@Suite struct WeatherPanelTests {
    let data = try! Data(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../fixtures/wttr-j1.json"))

    func report(at hour: Int) -> WeatherReport {
        let now = Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date())!
        return WeatherReport(j1: data, now: now)!
    }

    @Test("the hourly strip starts at now and runs into the next day")
    func hours() {
        let r = report(at: 10)
        #expect(r.hours.map(\.label) == ["Now", "12PM", "3PM", "6PM", "9PM", "12AM", "3AM", "6AM"])
        #expect(r.hours[1].rain == 55)
        #expect(r.hours[3].night)
    }

    @Test("each day takes its midday sky and its highest chance of rain")
    func days() {
        let r = report(at: 10)
        #expect(r.days.count == 3)
        #expect(r.days[0].label == "Today")
        #expect(r.days[0].code == 353)
        #expect(r.days[0].rain == 78)
        #expect((r.low, r.high) == (14, 17))
    }

    @Test("sunrise and sunset text become hours of the day")
    func clock() {
        #expect(clockHour("05:39 AM") == 5 + 39.0 / 60)
        #expect(clockHour("12:15 AM") == 0.25)
        #expect(clockHour("05:55 PM") == 17 + 55.0 / 60)
        #expect(clockHour("") == nil)
    }
}
