#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

private let weeks: [AIUsageReport] = [.busy, .hot, .quiet]

#Preview("Rings") { Desk { RingsAIUsagePanel(report: .busy) } }
#Preview("Screen Time") { Desk { ScreenTimeAIUsagePanel(report: .busy) } }
#Preview("Forecast") { Desk { ForecastAIUsagePanel(report: .busy) } }

#Preview("Rings: every week") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(weeks.indices, id: \.self) { RingsAIUsagePanel(report: weeks[$0]) } } }
}

#Preview("Screen Time: every week") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(weeks.indices, id: \.self) { ScreenTimeAIUsagePanel(report: weeks[$0]) } } }
}

#Preview("Forecast: every week") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(weeks.indices, id: \.self) { ForecastAIUsagePanel(report: weeks[$0]) } } }
}

#Preview("Rings, dark") { Desk { RingsAIUsagePanel(report: .busy) }.preferredColorScheme(.dark) }
#Preview("Rings: stale") { Desk { RingsAIUsagePanel(report: .cold) } }
#Preview("Day tooltip") {
    Desk { DayTooltip(day: AIUsageReport.busy.days[2], top: AIUsageReport.busy.topModels, today: AIUsageReport.morning) }
}
#endif
