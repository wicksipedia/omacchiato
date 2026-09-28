import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Sample weeks for the Xcode previews and the settings window. Monday 28 September 2026, 10:40.
extension AIUsageReport {
    public static let morning: Date = {
        var parts = DateComponents(year: 2026, month: 9, day: 28, hour: 10, minute: 40)
        parts.calendar = Calendar(identifier: .gregorian)
        return parts.date ?? Date()
    }()

    public static let hour: TimeInterval = 3600
    public static let day: TimeInterval = 86400

    public static let claude = Provider(
        id: "claude", name: "Claude", plan: "Max 5x", glyph: "\u{ec82}",
        color: Color(red: 0.85, green: 0.47, blue: 0.34),
        metrics: [Metric(label: "Session", used: 0.42, resetsIn: 3 * hour, span: 5 * hour),
                  Metric(label: "Weekly", used: 0.61, resetsIn: 3.3 * day, span: 7 * day),
                  Metric(label: "Fable", used: 0.08, resetsIn: 3.3 * day, span: 7 * day)])
    public static let codex = Provider(
        id: "codex", name: "Codex", plan: "Plus", glyph: "\u{ec81}",
        metrics: [Metric(label: "5h", used: 0.12, resetsIn: 4 * hour, span: 5 * hour),
                  Metric(label: "Weekly", used: 0.2, resetsIn: 5 * day, span: 7 * day)])
    public static let copilot = Provider(
        id: "copilot", name: "Copilot", plan: "Business", glyph: "\u{ec1e}",
        metrics: [Metric(label: "Premium", used: 0.34, resetsIn: 3 * day, span: 30 * day)], open: false)

    // the week before: busier early on, quiet at the end
    public static let priors = [14_000_000, 21_000_000, 8_000_000, 0, 3_000_000, 18_000_000, 9_000_000]

    public static func week(_ tokens: [[Int]], costs: [Double]) -> [Day] {
        let names = ["Opus 5.5", "Opus 5", "Sonnet 5", "Haiku 4.5"]
        let cal = Calendar(identifier: .gregorian)
        return tokens.indices.map { i in
            Day(date: cal.date(byAdding: .day, value: i - 6, to: cal.startOfDay(for: morning)) ?? morning,
                models: Dictionary(uniqueKeysWithValues: zip(names, tokens[i]).filter { $0.1 > 0 }),
                cost: costs[i],
                priorModels: priors[i] == 0 ? [:] : ["Opus 5.5": priors[i] * 3 / 4, "Sonnet 5": priors[i] / 4])
        }
    }

    // UpdatedStamp reads the real clock, not this fixed "now". Computed, so
    // the read time is minutes before now each time a preview draws.
    public static var busy: AIUsageReport { AIUsageReport(
        now: morning, updated: Date().addingTimeInterval(-3 * 60), providers: [claude, codex, copilot],
        days: week([[9_000_000, 3_800_000, 0, 0], [0, 0, 0, 0], [30_100_000, 0, 6_000_000, 3_000_000],
                    [12_400_000, 0, 3_000_000, 0], [0, 0, 0, 0], [28_600_000, 0, 600_000, 2_000_000],
                    [22_000_000, 0, 0, 3_900_000]],
                   costs: [8.88, 0, 14.88, 6.67, 0, 9.81, 8.75]),
        models: [Model(name: "Opus 5.5", tokens: 102_100_000, cost: 36.58),
                 Model(name: "Sonnet 5", tokens: 9_600_000, cost: 3.53),
                 Model(name: "Haiku 4.5", tokens: 8_900_000, cost: 0.9),
                 Model(name: "Opus 5", tokens: 3_800_000, cost: 8.88)],
        sessions: 30, activeHours: 3) }

    // Ahead of pace, with an outage and an incident.
    public static let hot = AIUsageReport(
        now: morning, updated: Date().addingTimeInterval(-90),
        providers: [
            Provider(id: "claude", name: "Claude", plan: "Pro", glyph: "\u{ec82}", color: claude.color,
                     metrics: [Metric(label: "Session", used: 0.93, resetsIn: 3.5 * hour, span: 5 * hour),
                               Metric(label: "Weekly", used: 0.72, resetsIn: 4 * day, span: 7 * day)],
                     severity: 2, status: "Claude Code: Partial outage",
                     incidents: [Incident(name: "Elevated errors on Claude Opus 5.5", status: "identified",
                                          at: morning.addingTimeInterval(-1800))]),
            copilot,
        ],
        days: busy.days, models: busy.models, sessions: 30, activeHours: 3)

    // A fresh week: nothing used, and no tokscale.
    public static let quiet = AIUsageReport(
        now: morning, updated: Date(),
        providers: [Provider(id: "claude", name: "Claude", plan: "Max 5x", glyph: "\u{ec82}", color: claude.color,
                             metrics: [Metric(label: "Session", used: 0, resetsIn: 5 * hour, span: 5 * hour),
                                       Metric(label: "Weekly", used: 0, resetsIn: 7 * day, span: 7 * day)]),
                    Provider(id: "codex", name: "Codex", plan: "Free", glyph: "\u{ec81}")])

    public static let cold = AIUsageReport(
        now: morning, updated: Date().addingTimeInterval(-40 * 60), providers: [claude, codex, copilot],
        days: busy.days, models: busy.models, sessions: busy.sessions, activeHours: busy.activeHours)
}
