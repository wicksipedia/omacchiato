import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the AI usage popup shows: each provider's plan limits, its service
// health, and the last seven days of tokens. The bar decodes this from
// omacchiato-ai-usage; the previews build it by hand.
public struct AIUsageReport {
    public struct Metric: Identifiable {
        public var label: String
        public var used: Double              // 0...1
        public var resetsIn: TimeInterval?
        public var span: TimeInterval?       // the length of the window
        public var id: String { label }

        public init(label: String, used: Double, resetsIn: TimeInterval? = nil, span: TimeInterval? = nil) {
            self.label = label
            self.used = used
            self.resetsIn = resetsIn
            self.span = span
        }

        // How far through the window the clock is.
        public var elapsed: Double? {
            guard let left = resetsIn, let span, left > 0, left <= span else { return nil }
            return 1 - left / span
        }

        // The use at reset, if the rate holds steady. Early in a window
        // the rate says little, so there is no forecast.
        public var forecast: Double? {
            guard let elapsed, elapsed >= 0.1 else { return nil }
            return used / elapsed
        }

        // Keep in sync with pace_colour in bin/omacchiato-ai-usage.
        public var tint: Color {
            let pct = used * 100
            guard let elapsed else { return pct < 50 ? PanelColors.green : (pct < 80 ? PanelColors.orange : PanelColors.red) }
            let ahead = pct - elapsed * 100
            if pct >= 90 || ahead > 20 { return PanelColors.red }
            return ahead > 5 ? PanelColors.orange : PanelColors.green
        }
    }

    public struct Incident: Identifiable {
        public var name: String
        public var status: String
        public var at: Date?
        public var url: URL?
        public var id: String { name }

        public init(name: String, status: String, at: Date? = nil, url: URL? = nil) {
            self.name = name
            self.status = status
            self.at = at
            self.url = url
        }
    }

    public struct Provider: Identifiable {
        public var id: String
        public var name: String
        public var plan: String?
        public var glyph: String?            // a Nerd Font logo
        public var color: Color
        public var metrics: [Metric]
        public var severity: Int             // 0 operational, 1 degraded, 2 outage
        public var status: String?           // the component status when not operational
        public var incidents: [Incident]
        public var statusPage: URL?
        public var open: Bool                // shows its windows until a click folds it

        public init(id: String, name: String, plan: String? = nil, glyph: String? = nil, color: Color = .primary,
                    metrics: [Metric] = [], severity: Int = 0, status: String? = nil,
                    incidents: [Incident] = [], statusPage: URL? = nil, open: Bool = true) {
            self.id = id
            self.name = name
            self.plan = plan
            self.glyph = glyph
            self.color = color
            self.metrics = metrics
            self.severity = severity
            self.status = status
            self.incidents = incidents
            self.statusPage = statusPage
            self.open = open
        }

        public var healthy: Bool { severity == 0 && incidents.isEmpty }

        // The fullest window, which the pill also shows.
        public var headline: Metric? { metrics.max { $0.used < $1.used } }
    }

    public struct Day: Identifiable {
        public var date: Date
        public var models: [String: Int]    // tokens by model name
        public var cost: Double
        public var priorModels: [String: Int]  // tokens by model on the same weekday a week earlier
        public var modelCosts: [String: Double]
        public var priorCosts: [String: Double]
        public var id: Date { date }

        public init(date: Date, models: [String: Int], cost: Double, priorModels: [String: Int] = [:],
                    modelCosts: [String: Double]? = nil, priorCosts: [String: Double] = [:]) {
            self.date = date
            self.models = models
            self.cost = cost
            self.priorModels = priorModels
            self.modelCosts = modelCosts ?? (cost > 0 ? ["Other": cost] : [:])
            self.priorCosts = priorCosts
        }

        public var prior: Int { priorModels.values.reduce(0, +) }

        public var tokens: Int { models.values.reduce(0, +) }

        public func values(_ measure: UsageMeasure) -> [String: Double] {
            measure == .tokens ? models.mapValues(Double.init) : modelCosts
        }
        public func priorValues(_ measure: UsageMeasure) -> [String: Double] {
            measure == .tokens ? priorModels.mapValues(Double.init) : priorCosts
        }
        public func total(_ measure: UsageMeasure) -> Double { values(measure).values.reduce(0, +) }
        public func priorTotal(_ measure: UsageMeasure) -> Double { priorValues(measure).values.reduce(0, +) }
    }

    public struct Model: Identifiable {
        public var name: String
        public var tokens: Int
        public var cost: Double
        // A shade of the provider's colour. Nil takes the next colour of modelPalette.
        public var color: Color?
        public var id: String { name }

        public func value(_ measure: UsageMeasure) -> Double { measure == .tokens ? Double(tokens) : cost }

        public init(name: String, tokens: Int, cost: Double, color: Color? = nil) {
            self.name = name
            self.tokens = tokens
            self.cost = cost
            self.color = color
        }
    }

    public var now: Date
    public var updated: Date                // when tokscale last read these numbers
    public var providers: [Provider]
    public var days: [Day]                  // the last seven, oldest first; empty without tokscale
    public var models: [Model]              // by tokens, most first
    public var sessions: Int
    public var activeHours: Int

    public init(now: Date, updated: Date? = nil, providers: [Provider], days: [Day] = [], models: [Model] = [],
                sessions: Int = 0, activeHours: Int = 0) {
        self.now = now
        self.updated = updated ?? now
        self.providers = providers
        self.days = days
        self.models = models
        self.sessions = sessions
        self.activeHours = activeHours
    }

    public var weekTokens: Int { days.reduce(0) { $0 + $1.tokens } }
    public var priorTokens: Int { days.reduce(0) { $0 + $1.prior } }

    // This week against the week before, as a fraction: 0.23 is 23% more. Nil without a week before.
    public var weekChange: Double? {
        priorTokens > 0 ? Double(weekTokens - priorTokens) / Double(priorTokens) : nil
    }
    public var weekCost: Double { days.reduce(0) { $0 + $1.cost } }

    public func weekValue(_ measure: UsageMeasure) -> Double { days.reduce(0) { $0 + $1.total(measure) } }
    public func priorValue(_ measure: UsageMeasure) -> Double { days.reduce(0) { $0 + $1.priorTotal(measure) } }
    public func weekChange(_ measure: UsageMeasure) -> Double? {
        let before = priorValue(measure)
        return before > 0 ? (weekValue(measure) - before) / before : nil
    }
    public var activeDays: Int { days.filter { $0.tokens > 0 }.count }

    // The models that get a colour of their own. The rest chart as "Other".
    public var topModels: [String] { Array(models.prefix(3).map(\.name)) }
    // The colours of topModels, then of Other.
    public var modelColors: [Color] {
        models.prefix(3).enumerated().map { $1.color ?? modelPalette[$0] } + [modelPalette[3]]
    }
}

public struct AIUsageActions {
    public var open: (URL) -> Void = { _ in }
    public var openReport: () -> Void = {}
    // Reads the data again, from a click on the "Updated" stamp. nil keeps the stamp plain.
    public var refresh: (() -> Void)?

    public init() {}
}

// 124441000 reads as 124.4M.
public func tokenText(_ n: Int) -> String {
    let d = Double(n)
    for (unit, size) in [("B", 1e9), ("M", 1e6), ("K", 1e3)] where (d / size * 10).rounded() / 10 >= 1 {
        return String(format: "%.1f%@", d / size, unit)
    }
    return "\(n)"
}

// What the week chart counts. A click on the chart switches it.
public enum UsageMeasure: String {
    case tokens, cost

    public var toggled: UsageMeasure { self == .tokens ? .cost : .tokens }
    public func text(_ value: Double) -> String { self == .tokens ? tokenText(Int(value)) : dollarText(value) }
}

public func dollarText(_ amount: Double) -> String {
    amount >= 10 || amount == 0 ? String(format: "$%.0f", amount) : String(format: "$%.2f", amount)
}

// 3 days 7 hours reads as 3d 7h, and 2 hours 5 minutes as 2h 5m.
public func resetText(_ left: TimeInterval) -> String {
    let minutes = Int(left) / 60
    let (d, h, m) = (minutes / 1440, minutes / 60 % 24, minutes % 60)
    if d > 0 { return "\(d)d \(h)h" }
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

// The moment of the reset: "Today 2:00 PM" on the same day, "Sat 2:00 PM"
// within the week, and "Oct 9" past that.
public func resetAtText(_ at: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
    let at = Date(timeIntervalSinceReferenceDate: (at.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    let time = at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    if calendar.isDate(at, inSameDayAs: now) { return "Today \(time)" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: at)).day ?? 0
    if days < 7 {
        let day = at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
        return "\(day) \(time)"
    }
    return at.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
}

extension AIUsageReport.Metric {
    // One line on where the window is heading at the current rate.
    public var forecastText: String? {
        if used >= 1 { return resetsIn.map { "Limit reached. Resets in \(resetText($0))." } ?? "Limit reached." }
        guard let forecast, let elapsed, let span, let left = resetsIn else { return nil }
        if used == 0 { return "Not used in this window." }
        if forecast <= 1 { return "On pace for \(Int((forecast * 100).rounded()))% at the reset." }
        let toFull = (1 - used) * elapsed * span / used
        return "Runs out in \(resetText(toFull)), \(resetText(left - toFull)) before the reset."
    }
}

// The "panel" object that omacchiato-ai-usage prints. Keep in sync with
// panel() in bin/omacchiato-ai-usage.
extension AIUsageReport {
    public init?(json: [String: Any], now: Date = Date()) {
        guard json["kind"] as? String == "ai-usage" else { return nil }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let stamp = ISO8601DateFormatter()
        let fine = ISO8601DateFormatter()
        fine.formatOptions.insert(.withFractionalSeconds)
        func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
        func list(_ any: Any?) -> [[String: Any]] { any as? [[String: Any]] ?? [] }

        let providers = list(json["providers"]).map { p in
            Provider(
                id: p["id"] as? String ?? "", name: p["name"] as? String ?? "",
                plan: p["plan"] as? String, glyph: p["glyph"] as? String,
                color: aiColor(p["color"] as? String),
                metrics: list(p["metrics"]).map {
                    Metric(label: $0["label"] as? String ?? "", used: number($0["used"]) ?? 0,
                           resetsIn: number($0["resets_in"]), span: number($0["span"]))
                },
                severity: (p["severity"] as? Int) ?? 0, status: p["status"] as? String,
                incidents: list(p["incidents"]).map {
                    let at = $0["at"] as? String ?? ""
                    return Incident(name: $0["name"] as? String ?? "", status: $0["status"] as? String ?? "",
                                    at: fine.date(from: at) ?? stamp.date(from: at),
                                    url: ($0["url"] as? String).flatMap(URL.init(string:)))
                },
                statusPage: (p["status_page"] as? String).flatMap(URL.init(string:)),
                open: p["open"] as? Bool ?? true)
        }
        let days = list(json["days"]).compactMap { d -> Day? in
            guard let date = (d["date"] as? String).flatMap(day.date(from:)) else { return nil }
            return Day(date: date, models: (d["models"] as? [String: Int]) ?? [:], cost: number(d["cost"]) ?? 0,
                       priorModels: (d["prior_models"] as? [String: Int])
                           ?? ((d["prior"] as? Int).map { ["Other": $0] } ?? [:]),
                       modelCosts: (d["model_costs"] as? [String: Any])?.compactMapValues(number),
                       priorCosts: (d["prior_costs"] as? [String: Any])?.compactMapValues(number) ?? [:])
        }
        let models = list(json["models"]).map {
            Model(name: $0["name"] as? String ?? "", tokens: $0["tokens"] as? Int ?? 0, cost: number($0["cost"]) ?? 0,
                  color: ($0["color"] as? String).map(aiColor))
        }
        self.init(now: now, updated: number(json["updated"]).map { Date(timeIntervalSince1970: $0) },
                  providers: providers, days: days, models: models,
                  sessions: json["sessions"] as? Int ?? 0, activeHours: json["active_hours"] as? Int ?? 0)
    }
}

// A brand colour as #RRGGBB. "label" and anything else take the text colour.
func aiColor(_ name: String?) -> Color {
    guard let hex = name, hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) else {
        return .primary
    }
    return Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
}
