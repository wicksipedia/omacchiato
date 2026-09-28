import Charts
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the AI usage popup, to compare in the previews. Each one
// shows the same data and offers the same actions.

// "Rings": each provider's windows as Activity rings, then the week.
public struct RingsAIUsagePanel: View {
    var report: AIUsageReport
    var actions: AIUsageActions

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
                    WeekHeadline(report: report)
                    WeekChart(report: report)
                    ModelShare(report: report).padding(.top, 4)
                }
                ReportRow(action: actions.openReport)
            }
        }
        .statusPanelBackground(width: 340)
    }

    // One row a window, with "Resets in" said once over the time column.
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
                        .foregroundStyle(m.tint == .green ? AnyShapeStyle(.primary) : AnyShapeStyle(m.tint))
                        .gridColumnAlignment(.trailing)
                    Text(m.resetsIn.flatMap { $0 > 0 ? resetText($0) : nil } ?? "")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct WeekHeadline: View {
    var report: AIUsageReport

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(tokenText(report.weekTokens)).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("tokens").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(dollarText(report.weekCost)).font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("at API prices").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// "Screen Time": the week first, with the daily average as the headline,
// then the limits as tracks and the models as a most-used list.
public struct ScreenTimeAIUsagePanel: View {
    var report: AIUsageReport
    var actions: AIUsageActions

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
                    Text("Daily Average").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(tokenText(report.weekTokens / days) + " tokens")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(dollarText(report.weekCost / Double(days))) a day · \(report.sessions) sessions · \(report.activeHours)h active")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    WeekChart(report: report, height: 140).padding(.top, 4)
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
                    let top = report.models.first?.tokens ?? 1
                    ForEach(Array(report.models.prefix(3).enumerated()), id: \.offset) { i, model in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(model.name).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("\(tokenText(model.tokens)) · \(dollarText(model.cost))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Capsule().fill(modelPalette[i])
                                .frame(width: max(4, 290 * CGFloat(model.tokens) / CGFloat(max(1, top))), height: 5)
                        }
                    }
                }
                ReportRow(action: actions.openReport)
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
                PanelCard(title: "Spend This Week", symbol: "dollarsign.circle") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(dollarText(report.weekCost)).font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("at API prices").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(tokenText(report.weekTokens) + " tokens").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    costChart
                }
                ReportRow(action: actions.openReport)
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

    var costChart: some View {
        Chart(report.days) { day in
            AreaMark(x: .value("Day", day.date, unit: .day), y: .value("Cost", day.cost))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", day.date, unit: .day), y: .value("Cost", day.cost))
                .interpolationMethod(.monotone)
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
            if Calendar.current.isDate(day.date, inSameDayAs: report.now) {
                PointMark(x: .value("Day", day.date, unit: .day), y: .value("Cost", day.cost))
                    .foregroundStyle(.green)
                    .annotation(position: .top) {
                        Text(dollarText(day.cost)).font(.system(size: 10, weight: .semibold))
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
                AxisValueLabel { if let n = value.as(Double.self) { Text(dollarText(n)) } }
            }
        }
        .frame(height: 100)
    }
}
