import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif
#if canImport(ActivityPanel)
import ActivityPanel
#endif

// The stats popup: one metric per pill, drawn like Activity Monitor's own
// tabs, with the same numbers Storage settings shows for disk.
public struct StatsPanel: View {
    var report: StatsReport
    var actions: StatsActions

    public init(report: StatsReport, actions: StatsActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            switch report.metric {
            case .cpu: CPUCard(report: report)
            case .ram: RAMCard(report: report)
            case .disk: DiskCard(report: report, actions: actions)
            }
            if !report.top.isEmpty { StatsTopCard(report: report) }
        }
        .statusPanelBackground(width: 300)
    }
}

// Yellow from 75%, red from 90%. Keep in sync with level() in bin/omacchiato-stats.
extension StatsReport {
    var tint: Color {
        if percent >= 0.9 { return PanelColors.red }
        if percent >= 0.75 { return PanelColors.yellow }
        return PanelColors.accent
    }
}

struct CPUCard: View {
    var report: StatsReport

    var body: some View {
        PanelCard(title: "CPU", symbol: "cpu") {
            HStack(alignment: .firstTextBaseline) {
                Text(percentText(report.percent))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                if report.cores > 0 {
                    Text("\(report.cores) cores").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            StatsMeter(share: report.percent, tint: report.tint)
        }
    }
}

struct RAMCard: View {
    var report: StatsReport

    var body: some View {
        PanelCard(title: "Memory", symbol: "memorychip") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(byteText(report.used)).font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("of \(byteText(report.total))").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(percentText(report.percent)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            StatsMeter(share: report.percent, tint: report.tint)
            VStack(spacing: 4) {
                StatsPartRow(label: "App", value: byteText(report.app))
                StatsPartRow(label: "Wired", value: byteText(report.wired))
                StatsPartRow(label: "Compressed", value: byteText(report.compressed))
            }
            .padding(.top, 2)
        }
    }
}

struct DiskCard: View {
    var report: StatsReport
    var actions: StatsActions

    var body: some View {
        PanelCard(title: "Disk", symbol: "internaldrive") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(byteText(report.free)).font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("free").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(percentText(report.percent)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            StatsMeter(share: report.percent, tint: report.tint)
            Text("\(byteText(report.used)) of \(byteText(report.total))")
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        if let settings = report.settings {
            SettingsRow(title: "Storage Settings") { actions.open(settings) }
        }
    }
}

struct StatsTopCard: View {
    var report: StatsReport

    var title: String { report.metric == .cpu ? "Most CPU" : "Most Memory" }
    var symbol: String { report.metric == .cpu ? "flame" : "memorychip" }

    var body: some View {
        PanelCard(title: title, symbol: symbol) {
            VStack(spacing: 6) {
                ForEach(report.top) { process in
                    HStack {
                        Text(process.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(valueText(process.value))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
            }
        }
    }

    func valueText(_ value: Double) -> String {
        report.metric == .cpu ? percentText(value) : byteText(UInt64(max(0, value)))
    }
}

struct StatsMeter: View {
    var share: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.fill.tertiary)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint.gradient)
                        .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, share)))))
                }
        }
        .frame(height: 8)
    }
}

struct StatsPartRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(size: 12))
        .monospacedDigit()
    }
}
