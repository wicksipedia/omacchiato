import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The weather popup, in the style of the iOS Weather app. It reads a
// WeatherReport, which comes from one wttr.in `format=j1` answer.
public struct WeatherReport: Equatable {
    public struct Hour: Equatable {
        public var label: String
        public var code: Int
        public var night: Bool
        public var rain: Int
        public var temp: Int
    }

    public struct Day: Equatable {
        public var label: String
        public var code: Int
        public var rain: Int
        public var low: Int
        public var high: Int
    }

    public var location = ""
    public var temp = 0
    public var feels = 0
    public var desc = ""
    public var code = 113
    public var night = false
    public var hours: [Hour] = []
    public var days: [Day] = []
    public var wind = ""
    public var humidity = 0
    public var uv = 0
    public var sunrise = ""
    public var sunset = ""
    public var moon = ""
    public var updatedAt = Date()

    // The bar fetches every 30 minutes: two missed fetches.
    public static let staleAfter: TimeInterval = 3600

    public init() {}

    // wttr.in gives the hourly steps in the local time of the place.
    // The bar reads them with the Mac's clock.
    public init?(j1 data: Data, now: Date = Date(), calendar: Calendar = .current) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (root["current_condition"] as? [[String: Any]])?.first,
              let forecast = root["weather"] as? [[String: Any]], let today = forecast.first
        else { return nil }
        func text(_ d: [String: Any], _ key: String) -> String { d[key] as? String ?? "" }
        func int(_ d: [String: Any], _ key: String) -> Int { Int(text(d, key)) ?? 0 }
        func nested(_ d: [String: Any], _ key: String) -> String {
            ((d[key] as? [[String: Any]])?.first?["value"] as? String) ?? ""
        }
        func hourly(_ day: [String: Any]) -> [[String: Any]] { day["hourly"] as? [[String: Any]] ?? [] }

        let astro = (today["astronomy"] as? [[String: Any]])?.first ?? [:]
        sunrise = text(astro, "sunrise")
        sunset = text(astro, "sunset")
        moon = text(astro, "moon_phase")
        let rise = clockHour(sunrise) ?? 6
        let set = clockHour(sunset) ?? 18
        func isNight(_ hour: Double) -> Bool { hour < rise || hour >= set }

        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let hourNow = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60

        location = ((root["nearest_area"] as? [[String: Any]])?.first).map { nested($0, "areaName") } ?? ""
        temp = int(current, "temp_C")
        feels = int(current, "FeelsLikeC")
        desc = nested(current, "weatherDesc")
        code = int(current, "weatherCode")
        night = isNight(hourNow)
        humidity = int(current, "humidity")
        uv = int(current, "uvIndex")
        wind = "\(text(current, "winddir16Point")) \(text(current, "windspeedKmph")) km/h"

        // "Now", then the 3-hour steps that follow it, into the next days.
        let upcoming = forecast.enumerated().flatMap { index, day in
            hourly(day).map { (at: index * 24 + int($0, "time") / 100, step: $0) }
        }.filter { Double($0.at) > hourNow }
        hours = [Hour(label: "Now", code: code, night: night,
                      rain: hourly(today).map { int($0, "chanceofrain") }.first ?? 0, temp: temp)]
            + upcoming.prefix(7).map { at, step in
                Hour(label: hourLabel(at % 24), code: int(step, "weatherCode"),
                     night: isNight(Double(at % 24)), rain: int(step, "chanceofrain"), temp: int(step, "tempC"))
            }

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.calendar = calendar
        let weekday = DateFormatter()
        weekday.dateFormat = "EEE"
        weekday.calendar = calendar
        days = forecast.enumerated().map { index, day in
            let steps = hourly(day)
            let label = index == 0 ? "Today"
                : parser.date(from: text(day, "date")).map(weekday.string(from:)) ?? text(day, "date")
            // the midday step stands for the day
            let midday = steps.first { int($0, "time") == 1200 } ?? steps.first ?? [:]
            return Day(label: label, code: int(midday, "weatherCode"),
                       rain: steps.map { int($0, "chanceofrain") }.max() ?? 0,
                       low: int(day, "mintempC"), high: int(day, "maxtempC"))
        }
    }

    public var low: Int { days.first?.low ?? temp }
    public var high: Int { days.first?.high ?? temp }
}

// "05:39 AM" to 5.65.
func clockHour(_ text: String) -> Double? {
    let parts = text.split(whereSeparator: { $0 == ":" || $0 == " " })
    guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]) else { return nil }
    return h.truncatingRemainder(dividingBy: 12) + (parts[2] == "PM" ? 12 : 0) + m / 60
}

func hourLabel(_ hour: Int) -> String {
    let h = hour % 12 == 0 ? 12 : hour % 12
    return "\(h)\(hour < 12 ? "AM" : "PM")"
}

// WWO condition codes, as wttr.in reports them.
enum Sky {
    case clear, partly, cloudy, fog, drizzle, rain, heavy, storm, snow

    init(code: Int) {
        switch code {
        case 113: self = .clear
        case 116: self = .partly
        case 119, 122: self = .cloudy
        case 143, 248, 260: self = .fog
        case 176, 263, 266: self = .drizzle
        case 293, 296, 353: self = .rain
        case 299, 302, 305, 308, 356, 359: self = .heavy
        case 200, 386, 389, 392, 395: self = .storm
        default: self = .snow
        }
    }

    func symbol(night: Bool) -> String {
        switch self {
        case .clear: night ? "moon.stars.fill" : "sun.max.fill"
        case .partly: night ? "cloud.moon.fill" : "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: night ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
        case .rain: "cloud.rain.fill"
        case .heavy: "cloud.heavyrain.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .snow: "cloud.snow.fill"
        }
    }

    func sky(night: Bool) -> [Color] {
        if night {
            switch self {
            case .clear, .partly: return [Color(hex: 0x0B1026), Color(hex: 0x2B3A67)]
            default: return [Color(hex: 0x1C222C), Color(hex: 0x3A4452)]
            }
        }
        switch self {
        case .clear: return [Color(hex: 0x2F7BD8), Color(hex: 0x7DB9E8)]
        case .partly: return [Color(hex: 0x4A7FB5), Color(hex: 0x8FB3D4)]
        case .cloudy: return [Color(hex: 0x4F5B68), Color(hex: 0x8793A0)]
        case .fog: return [Color(hex: 0x8C959D), Color(hex: 0xAEB5BB)]
        case .drizzle, .rain, .heavy: return [Color(hex: 0x3F4B5B), Color(hex: 0x6B7A8F)]
        case .storm: return [Color(hex: 0x252B36), Color(hex: 0x4C566A)]
        case .snow: return [Color(hex: 0x8A9BB0), Color(hex: 0xC9D5E2)]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    // The iOS range bars run blue when cold, through green, to red when hot.
    static func temperature(_ celsius: Int) -> Color {
        let stops: [(Int, UInt32)] = [(0, 0x5AC8FA), (10, 0x64D2C8), (17, 0x9BD770),
                                      (23, 0xF5D547), (29, 0xF5A623), (35, 0xF0544F)]
        return Color(hex: (stops.last { $0.0 <= celsius } ?? stops[0]).1)
    }
}

public struct WeatherPanel: View {
    var report: WeatherReport

    public init(report: WeatherReport) { self.report = report }

    public var body: some View {
        VStack(spacing: 10) {
            header
            card("HOURLY FORECAST", "clock") { hourly }
            card("\(report.days.count)-DAY FORECAST", "calendar") { daily }
            details
            // A darker backing than the cards: the orange of a stale stamp
            // is faint on a pale sky.
            UpdatedStamp(report.updatedAt, staleAfter: WeatherReport.staleAfter)
                .colorScheme(.dark)
                .padding(.vertical, 5)
                .background(.black.opacity(0.35), in: .rect(cornerRadius: 10))
        }
        .padding(14)
        .frame(width: 340)
        .foregroundStyle(.white)
        .background {
            LinearGradient(colors: Sky(code: report.code).sky(night: report.night),
                           startPoint: .top, endPoint: .bottom)
            SkyEffects(sky: Sky(code: report.code), night: report.night)
        }
    }

    var header: some View {
        VStack(spacing: 0) {
            Text(report.location).font(.system(size: 22, weight: .medium))
            Text("\(report.temp)°").font(.system(size: 72, weight: .thin))
            Text(report.desc).font(.system(size: 15, weight: .medium))
            Text("Feels like \(report.feels)°  L:\(report.low)° H:\(report.high)°")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 6)
        .shadow(color: .black.opacity(0.15), radius: 4)
    }

    func card<Content: View>(_ title: String, _ icon: String,
                             @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Divider().overlay(.white.opacity(0.25))
            content()
        }
        .padding(12)
        .background(.black.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    func rain(_ chance: Int) -> some View {
        // iOS shows a chance only when it is worth a look
        Text(chance >= 20 ? "\(chance)%" : " ")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: 0x8FD3FF))
    }

    func symbol(_ code: Int, night: Bool) -> some View {
        Image(systemName: Sky(code: code).symbol(night: night))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: 17))
            .frame(height: 22)
    }

    var hourly: some View {
        HStack(spacing: 0) {
            ForEach(Array(report.hours.enumerated()), id: \.offset) { _, hour in
                VStack(spacing: 4) {
                    Text(hour.label).font(.system(size: 12, weight: .semibold))
                    symbol(hour.code, night: hour.night)
                    rain(hour.rain)
                    Text("\(hour.temp)°").font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    var daily: some View {
        let low = report.days.map(\.low).min() ?? 0
        let high = report.days.map(\.high).max() ?? 1
        return VStack(spacing: 0) {
            ForEach(Array(report.days.enumerated()), id: \.offset) { index, day in
                if index > 0 { Divider().overlay(.white.opacity(0.25)) }
                HStack(spacing: 8) {
                    Text(day.label).font(.system(size: 15, weight: .medium))
                        .frame(width: 54, alignment: .leading)
                    VStack(spacing: 0) {
                        symbol(day.code, night: false)
                        if day.rain >= 20 { rain(day.rain) }
                    }
                    .frame(width: 34)
                    Text("\(day.low)°").foregroundStyle(.white.opacity(0.6))
                        .frame(width: 30, alignment: .trailing)
                    RangeBar(low: low, high: high, day: day,
                             now: index == 0 ? report.temp : nil)
                    Text("\(day.high)°").frame(width: 30, alignment: .trailing)
                }
                .font(.system(size: 15, weight: .medium))
                .frame(height: 40)
            }
        }
    }

    var details: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                tile("WIND", "wind", report.wind)
                tile("HUMIDITY", "humidity", "\(report.humidity)%")
            }
            GridRow {
                tile("UV INDEX", "sun.max", "\(report.uv)")
                tile("SUNRISE", "sunrise", report.sunrise.lowercased(), note: "Sunset \(report.sunset.lowercased())")
            }
        }
    }

    func tile(_ title: String, _ icon: String, _ value: String, note: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 20, weight: .medium))
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)) }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(.black.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}

// One day's span on the scale of the whole forecast.
struct RangeBar: View {
    var low: Int
    var high: Int
    var day: WeatherReport.Day
    var now: Int?

    var body: some View {
        GeometryReader { geo in
            let span = CGFloat(max(1, high - low))
            let x = { (t: Int) in CGFloat(t - low) / span * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(colors: [.temperature(day.low), .temperature(day.high)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, x(day.high) - x(day.low)))
                    .offset(x: x(day.low))
                if let now {
                    Circle().fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                        .frame(width: 6, height: 6)
                        .offset(x: min(max(0, x(now) - 3), geo.size.width - 6))
                }
            }
        }
        .frame(height: 5)
    }
}

#if DEBUG
extension WeatherReport {
    // A real wttr.in answer, with the place replaced.
    static var fixture: WeatherReport {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../../tests/fixtures/wttr-j1.json")
        let noon = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        return (try? Data(contentsOf: url)).flatMap { WeatherReport(j1: $0, now: noon) } ?? WeatherReport()
    }

    static func sample(_ code: Int, night: Bool = false, temp: Int = 24, updatedAt: Date = Date()) -> WeatherReport {
        var r = WeatherReport()
        r.updatedAt = updatedAt
        r.location = "Springfield"
        r.temp = temp
        r.feels = temp - 2
        let names: [Int: String] = [113: night ? "Clear" : "Sunny", 116: "Partly cloudy",
                                    122: "Overcast", 248: "Fog", 296: "Light rain",
                                    308: "Heavy rain", 389: "Thunderstorm", 338: "Heavy snow"]
        r.desc = names[code] ?? "Weather"
        r.code = code
        r.night = night
        // Preview builds wrap each literal, so an untyped tuple list type-checks too slowly.
        let steps: [(label: String, code: Int, rain: Int)] = [
            ("Now", code, 10), ("1PM", code, 25), ("4PM", 116, 40), ("7PM", 176, 65),
            ("10PM", 113, 5), ("1AM", 113, 0), ("4AM", 116, 0), ("7AM", 113, 0),
        ]
        r.hours = steps.enumerated().map { i, step in
            Hour(label: step.label, code: step.code, night: i >= 3 && i <= 6, rain: step.rain, temp: temp - i / 2)
        }
        r.days = [Day(label: "Today", code: code, rain: 40, low: temp - 8, high: temp + 2),
                  Day(label: "Mon", code: 176, rain: 80, low: temp - 10, high: temp - 1),
                  Day(label: "Tue", code: 116, rain: 0, low: temp - 12, high: temp + 5)]
        r.wind = "SSW 18 km/h"
        r.humidity = 64
        r.uv = 7
        r.sunrise = "05:39 AM"
        r.sunset = "05:55 PM"
        r.moon = "Waning Gibbous"
        return r
    }
}

#Preview("wttr.in answer") { WeatherPanel(report: .fixture) }
#Preview("stale") { WeatherPanel(report: .sample(116, temp: 18, updatedAt: Date().addingTimeInterval(-3 * 3600))) }
#Preview("sunny") { WeatherPanel(report: .sample(113)) }
#Preview("clear night") { WeatherPanel(report: .sample(113, night: true, temp: 14)) }
#Preview("partly cloudy") { WeatherPanel(report: .sample(116, temp: 21)) }
#Preview("overcast") { WeatherPanel(report: .sample(122, temp: 17)) }
#Preview("fog") { WeatherPanel(report: .sample(248, temp: 11)) }
#Preview("light rain") { WeatherPanel(report: .sample(296, temp: 16)) }
#Preview("heavy rain") { WeatherPanel(report: .sample(308, temp: 15)) }
#Preview("storm") { WeatherPanel(report: .sample(389, temp: 19)) }
#Preview("snow") { WeatherPanel(report: .sample(338, temp: -2)) }
#endif
