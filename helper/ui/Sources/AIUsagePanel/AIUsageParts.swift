import Charts
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Pieces that every design of the AI usage panel shares.

let modelPalette: [Color] = [.orange, .purple, .teal, .gray]

// The provider's logo from the bar's Nerd Font, or its first letter
// on a Mac without that font.
struct ProviderMark: View {
    var provider: AIUsageReport.Provider
    var size: CGFloat = 15

    var body: some View {
        Group {
            if let logo = provider.glyph.flatMap({ glyphImage($0, size: size) }) {
                Image(nsImage: logo).renderingMode(.template)
            } else {
                Text(provider.name.prefix(1))
                    .font(.system(size: size * 0.7, weight: .bold, design: .rounded))
                    .frame(width: size, height: size)
                    .background(provider.color.opacity(0.2), in: .circle)
            }
        }
        .foregroundStyle(provider.color)
        .frame(width: size + 4, height: size + 4)
    }
}

struct ProviderHeader: View {
    var provider: AIUsageReport.Provider

    var body: some View {
        HStack(spacing: 6) {
            ProviderMark(provider: provider)
            Text(provider.name).font(.system(size: 13, weight: .semibold))
            if let plan = provider.plan {
                Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

// A provider's header folds its windows away on a click. A folded
// provider shows its fullest window in the header. A service problem
// stays on screen either way.
struct ProviderSection<Content: View>: View {
    var provider: AIUsageReport.Provider
    var actions: AIUsageActions
    var health = true
    @ViewBuilder var content: Content
    @State private var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(provider: AIUsageReport.Provider, actions: AIUsageActions, health: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.provider = provider
        self.actions = actions
        self.health = health
        self.content = content()
        _open = State(initialValue: provider.open)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProviderHeader(provider: provider)
                Spacer(minLength: 4)
                if !open, let m = provider.headline {
                    Text("\(Int((m.used * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(m.tint == .green ? AnyShapeStyle(.primary) : AnyShapeStyle(m.tint))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { open.toggle() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if health && !provider.healthy { HealthNote(provider: provider, actions: actions) }
            if open { content }
        }
    }
}

// A service problem, with its incidents. Each one opens the status page.
struct HealthNote: View {
    var provider: AIUsageReport.Provider
    var actions: AIUsageActions

    var body: some View {
        let tint: Color = provider.severity >= 2 ? .red : .orange
        VStack(alignment: .leading, spacing: 0) {
            HoverRow(action: provider.statusPage.map { url in { actions.open(url) } }) {
                Label(provider.status ?? "\(provider.name) has an incident",
                      systemImage: provider.severity >= 2 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            ForEach(provider.incidents) { incident in
                HoverRow(action: (incident.url ?? provider.statusPage).map { url in { actions.open(url) } }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.name).font(.system(size: 12)).lineLimit(2)
                        Text([incident.status.capitalized, incident.at?.formatted(date: .omitted, time: .shortened)]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

// A colour for each ring, outside in, as the Fitness app gives each of
// its rings one. The percent text carries the pace.
let ringColors: [Color] = [.blue, .purple, .mint]

// Activity rings, one for each window, outside in. The tick on a ring
// marks how far through the window the clock is, so a fill past the tick
// is ahead of an even pace.
struct UsageRings: View {
    var metrics: [AIUsageReport.Metric]
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            ForEach(Array(metrics.prefix(3).enumerated()), id: \.offset) { i, metric in
                ZStack {
                    Circle().stroke(ringColors[i].opacity(0.22), lineWidth: lineWidth)
                    if metric.used > 0 {
                        Circle().trim(from: 0, to: min(1, metric.used))
                            .stroke(ringColors[i], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                    if let e = metric.elapsed {
                        Circle().trim(from: max(0, e - 0.005), to: min(1, e + 0.005))
                            .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth + 3))
                    }
                }
                .rotationEffect(.degrees(-90))
                .padding(CGFloat(i) * (lineWidth + 2) + lineWidth / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// A window as a track: the fill is the use so far, the pale fill the
// forecast at the reset, and the tick the clock.
struct PaceTrack: View {
    var metric: AIUsageReport.Metric
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                if let f = metric.forecast, f > metric.used {
                    Capsule().fill(metric.tint.opacity(0.3)).frame(width: w * min(1, f))
                }
                if metric.used > 0 {
                    Capsule().fill(metric.tint).frame(width: max(height, w * min(1, metric.used)))
                }
                if let e = metric.elapsed {
                    Capsule().fill(.primary).frame(width: 2, height: height + 6).offset(x: w * e - 1)
                }
            }
        }
        .frame(height: height)
    }
}

// Seven days of tokens, one bar a day, split by model as Screen Time
// splits by category. The dashed line is the daily average.
struct WeekChart: View {
    var report: AIUsageReport
    var height: CGFloat = 110
    var average = true

    struct Slice: Identifiable {
        var day: Date
        var model: String
        var tokens: Int
        var id: String { "\(day.timeIntervalSince1970)\(model)" }
    }

    var slices: [Slice] {
        let top = report.topModels
        return report.days.flatMap { day -> [Slice] in
            var other = 0
            var out: [Slice] = []
            for (model, n) in day.models {
                if top.contains(model) { out.append(Slice(day: day.date, model: model, tokens: n)) } else { other += n }
            }
            out.sort { (top.firstIndex(of: $0.model) ?? 9) < (top.firstIndex(of: $1.model) ?? 9) }
            return other > 0 ? out + [Slice(day: day.date, model: "Other", tokens: other)] : out
        }
    }

    var body: some View {
        let mean = report.days.isEmpty ? 0 : report.weekTokens / report.days.count
        Chart {
            ForEach(slices) { s in
                BarMark(x: .value("Day", s.day, unit: .day), y: .value("Tokens", s.tokens), width: .ratio(0.6))
                    .foregroundStyle(by: .value("Model", s.model))
                    .clipShape(.rect(cornerRadius: 3))
            }
            if average && mean > 0 {
                RuleMark(y: .value("Average", mean))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("avg").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: report.topModels + ["Other"], range: modelPalette)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Calendar.current.isDate(date, inSameDayAs: report.now)
                             ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel { if let n = value.as(Int.self) { Text(tokenText(n)) } }
            }
        }
        .frame(height: height)
    }
}

// The week's tokens by model, as iPhone Storage shows space by app.
struct ModelShare: View {
    var report: AIUsageReport

    var body: some View {
        let total = max(1, report.weekTokens)
        let shown = Array(report.models.prefix(3))
        let other = report.weekTokens - shown.reduce(0) { $0 + $1.tokens }
        let parts: [(String, Int, Color)] = shown.enumerated().map { ($1.name, $1.tokens, modelPalette[$0]) }
            + (other > 0 ? [("Other", other, modelPalette[3])] : [])
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { _, n, color in
                        Rectangle().fill(color)
                            .frame(width: max(2, (geo.size.width - CGFloat(parts.count - 1) * 2) * CGFloat(n) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(.capsule)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 4) {
                ForEach(parts, id: \.0) { name, n, color in
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 7, height: 7)
                        Text(name).foregroundStyle(.primary)
                        Text(tokenText(n)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
            }
            .font(.system(size: 11))
        }
    }
}

struct ReportRow: View {
    var action: () -> Void

    var body: some View {
        HoverRow(action: action) {
            HStack {
                Text("Token Report")
                Spacer()
                Text("tokscale").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
        }
    }
}
