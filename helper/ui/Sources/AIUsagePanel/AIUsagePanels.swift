import Charts
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the AI usage popup, to compare in the previews.

// "Rings": each provider's windows as Activity rings, then the week.
public struct RingsAIUsagePanel: View {
    var report: AIUsageReport
    var actions: AIUsageActions
    @AppStorage(aiUsageMeasureKey) private var measure = UsageMeasure.tokens

    public init(report: AIUsageReport, actions: AIUsageActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(report.providers) { provider in
                PanelCard {
                    ProviderSection(provider: provider, actions: actions) {
                        if provider.metrics.isEmpty {
                            Text("No data").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 14) {
                                UsageRings(metrics: provider.metrics).frame(width: 76, height: 76)
                                legend(Array(provider.metrics.prefix(3)))
                            }
                        }
                    }
                }
            }
            if !report.days.isEmpty {
                PanelCard(title: "Last 7 Days", symbol: "chart.bar.fill") {
                    WeekHeadline(report: report, measure: measure)
                    WeekChart(report: report, measure: measure) { measure = measure.toggled }
                    ModelShare(report: report, measure: measure).padding(.top, 4)
                }
            }
            UpdatedStamp(report.updated, staleAfter: aiUsageStaleAfter, refresh: actions.refresh)
            if !report.days.isEmpty {
                SettingsRow(title: "Token Report", detail: "tokscale", action: actions.openReport)
            }
        }
        .statusPanelBackground(width: 340)
    }

    // A window shorter than a day needs no day. A window that resets with
    // an earlier one names that one, as Fable does with Weekly.
    func resetCaption(_ metrics: [AIUsageReport.Metric], _ i: Int) -> String? {
        let m = metrics[i]
        guard let left = m.resetsIn, (m.span ?? .infinity) >= 86400 else { return nil }
        if let twin = metrics[..<i].first(where: { abs(($0.resetsIn ?? -.infinity) - left) < 60 }) {
            return "With \(twin.label)"
        }
        return resetAtText(report.now + left, now: report.now)
    }

    // One row per window. "Resets in" shows once, above the time column.
    func legend(_ metrics: [AIUsageReport.Metric]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            if metrics.contains(where: { ($0.resetsIn ?? 0) > 0 }) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("RESETS IN").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            ForEach(Array(metrics.enumerated()), id: \.offset) { i, m in
                GridRow(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Circle().fill(ringColors[i]).frame(width: 7, height: 7)
                        Text(m.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    // the pace colour only when ahead of pace
                    Text("\(Int((m.used * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(m.tint == PanelColors.green ? AnyShapeStyle(.primary) : AnyShapeStyle(m.tint))
                        .gridColumnAlignment(.trailing)
                    if let left = m.resetsIn, left > 0 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(resetText(left))
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                            if let caption = resetCaption(metrics, i) {
                                Text(caption)
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }
        }
    }
}

// The measure of the chart leads, and the other one follows on the right.
struct WeekHeadline: View {
    var report: AIUsageReport
    var measure: UsageMeasure = .tokens

    var body: some View {
        let tokens = (tokenText(report.weekTokens), "tokens"), cost = (dollarText(report.weekCost), "at API prices")
        let (lead, follow) = measure == .tokens ? (tokens, cost) : (cost, tokens)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(lead.0).font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(lead.1).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(follow.0).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(follow.1).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let change = report.weekChange(measure) {
                WeekChange(change: change)
            }
        }
    }
}

// How this week compares with the week before.
struct WeekChange: View {
    var change: Double

    var body: some View {
        let percent = Int((abs(change) * 100).rounded())
        let tint = percent == 0 ? Color.secondary : (change > 0 ? PanelColors.green : PanelColors.red)
        HStack(spacing: 4) {
            Image(systemName: percent == 0 ? "equal" : (change > 0 ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            if percent == 0 {
                Text("Same as last week")
            } else {
                Text("\(Text("\(percent)%").foregroundStyle(tint).fontWeight(.semibold)) \(change > 0 ? "more" : "less") than last week")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

// "Screen Time": the daily average leads. Limits follow as tracks,
// then models as a most-used list.
public struct ScreenTimeAIUsagePanel: View {
    var report: AIUsageReport
    var actions: AIUsageActions
    @AppStorage(aiUsageMeasureKey) private var measure = UsageMeasure.tokens

    public init(report: AIUsageReport, actions: AIUsageActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(report.providers.filter { !$0.healthy }) { HealthNote(provider: $0, actions: actions) }
            if !report.days.isEmpty {
                PanelCard {
                    let days = max(1, report.days.count)
                    let tokens = tokenText(report.weekTokens / days) + " tokens"
                    let cost = dollarText(report.weekCost / Double(days))
                    Text("Daily Average").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(measure == .tokens ? tokens : cost)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(measure == .tokens ? cost : tokens) a day · \(report.sessions) sessions · \(report.activeHours)h active")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    WeekChart(report: report, height: 140, measure: measure) { measure = measure.toggled }.padding(.top, 4)
                }
            }
            PanelCard(title: "Limits", symbol: "gauge.with.needle") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.providers) { provider in
                        ProviderSection(provider: provider, actions: actions, health: false) {
                            ForEach(provider.metrics) { track($0) }
                        }
                    }
                }
            }
            if !report.models.isEmpty {
                PanelCard(title: "Most Used", symbol: "cpu") {
                    let shown = Array(report.models.prefix(3))
                    let top = shown.map { $0.value(measure) }.max() ?? 0
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, model in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(model.name).font(.system(size: 12, weight: .medium))
                                Spacer()
                                let values = [tokenText(model.tokens), dollarText(model.cost)]
                                Text((measure == .tokens ? values : values.reversed()).joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Capsule().fill(report.modelColors[i])
                                .frame(width: max(4, 290 * model.value(measure) / max(top, .leastNonzeroMagnitude)), height: 5)
                        }
                    }
                }
            }
            UpdatedStamp(report.updated, staleAfter: aiUsageStaleAfter, refresh: actions.refresh)
            if !report.models.isEmpty {
                SettingsRow(title: "Token Report", detail: "tokscale", action: actions.openReport)
            }
        }
        .statusPanelBackground(width: 340)
    }

    func track(_ m: AIUsageReport.Metric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(m.label).font(.system(size: 12))
                Spacer()
                Text(["\(Int((m.used * 100).rounded()))%", m.resetsIn.flatMap { $0 > 0 ? resetText($0) : nil }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
            PaceTrack(metric: m, height: 6)
        }
    }
}

// "Forecast": where each window is heading at the current rate, then the
// week's cost as a line.
public struct ForecastAIUsagePanel: View {
    var report: AIUsageReport
    var actions: AIUsageActions
    @AppStorage(aiUsageMeasureKey) private var measure = UsageMeasure.tokens

    public init(report: AIUsageReport, actions: AIUsageActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(report.providers) { provider in
                PanelCard {
                    ProviderSection(provider: provider, actions: actions) {
                        if provider.metrics.isEmpty {
                            Text("No data").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ForEach(provider.metrics) { forecast($0) }
                    }
                }
            }
            if !report.days.isEmpty {
                PanelCard(title: measure == .cost ? "Spend This Week" : "Tokens This Week",
                          symbol: measure == .cost ? "dollarsign.circle" : "chart.line.uptrend.xyaxis") {
                    let tokens = tokenText(report.weekTokens), cost = dollarText(report.weekCost)
                    HStack(alignment: .firstTextBaseline) {
                        Text(measure == .cost ? cost : tokens).font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text(measure == .cost ? "at API prices" : "tokens").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(measure == .cost ? tokens + " tokens" : cost + " at API prices")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    weekChart
                        .contentShape(.rect)
                        .onTapGesture { measure = measure.toggled }
                }
            }
            UpdatedStamp(report.updated, staleAfter: aiUsageStaleAfter, refresh: actions.refresh)
            if !report.days.isEmpty {
                SettingsRow(title: "Token Report", detail: "tokscale", action: actions.openReport)
            }
        }
        .statusPanelBackground(width: 340)
    }

    func forecast(_ m: AIUsageReport.Metric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int((m.used * 100).rounded()))%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(m.tint)
            }
            PaceTrack(metric: m, height: 8)
            if let text = m.forecastText {
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // The week as a line, of cost or tokens. A click switches it.
    var weekChart: some View {
        Chart(report.days) { day in
            AreaMark(x: .value("Day", day.date, unit: .day), y: .value("Value", day.total(measure)))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(colors: [PanelColors.green.opacity(0.35), PanelColors.green.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", day.date, unit: .day), y: .value("Value", day.total(measure)))
                .interpolationMethod(.monotone)
                .foregroundStyle(PanelColors.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
            if Calendar.current.isDate(day.date, inSameDayAs: report.now) {
                PointMark(x: .value("Day", day.date, unit: .day), y: .value("Value", day.total(measure)))
                    .foregroundStyle(PanelColors.green)
                    .annotation(position: .top) {
                        Text(measure.text(day.total(measure))).font(.system(size: 10, weight: .semibold))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let n = value.as(Double.self) { Text(measure.text(n)) } }
            }
        }
        .frame(height: 100)
    }
}
