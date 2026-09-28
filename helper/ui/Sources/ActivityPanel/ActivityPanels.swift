import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the activity popup, to compare in the previews.

// "Monitor": CPU graph, memory, network and top processes, like Activity Monitor.
public struct MonitorActivityPanel: View {
    var report: ActivityReport
    var actions: ActivityActions

    public init(report: ActivityReport, actions: ActivityActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            if report.hot { HotNote().padding(.horizontal, 4) }
            PanelCard(title: "CPU", symbol: "cpu") {
                if let load = report.load {
                    HStack(alignment: .firstTextBaseline) {
                        Text(percentText(load.total))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: load.total))
                        Spacer()
                        legend(load)
                    }
                    .monospacedDigit()
                    .animatesSamples(load)
                    LoadGraph(history: report.history).frame(height: 54)
                    if report.cores.count > 1 {
                        CoreBars(cores: report.cores).frame(height: 16).animatesSamples(report.cores)
                    }
                } else {
                    Measuring()
                }
            }
            PanelCard(title: "Memory", symbol: "memorychip") {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(byteText(report.memoryUsed)).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("of \(byteText(report.memoryTotal))").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    PressureTag(pressure: report.pressure)
                }
                .monospacedDigit()
                ShareBar(share: report.memoryShare, tint: report.pressure.tint).animatesSamples(report.memoryUsed)
                Text("Compressed \(byteText(report.compressed)) · Swap \(byteText(report.swapUsed))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            PanelCard {
                HStack(spacing: 10) {
                    Image(systemName: "network").foregroundStyle(.secondary)
                    Rates(report: report).fixedSize()
                    NetworkGraph(history: report.networkHistory).frame(height: 18)
                }
            }
            if !report.processes.isEmpty {
                PanelCard(title: "Most CPU", symbol: "flame") {
                    VStack(spacing: 7) {
                        ForEach(report.processes.prefix(6)) { row($0) }
                    }
                    .animatesSamples(report.processes.map(\.id))
                }
            }
            MonitorLinks(actions: actions)
        }
        .statusPanelBackground(width: 320)
    }

    func legend(_ load: ActivityReport.Load) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            LegendItem(tint: userTint, label: "User", value: load.user)
            LegendItem(tint: systemTint, label: "System", value: load.system)
        }
    }

    func row(_ process: ActivityReport.Process) -> some View {
        HStack(spacing: 8) {
            ProcessIcon(process: process, size: 20)
            ProcessName(process: process).font(.system(size: 12))
            Spacer(minLength: 6)
            Text(byteText(process.memory))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(percentText(process.cpu))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(process.tint)
                .frame(width: 42, alignment: .trailing)
        }
        .monospacedDigit()
    }
}

struct LegendItem: View {
    var tint: Color
    var label: String
    var value: Double

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Text(percentText(value)).fontWeight(.medium).frame(minWidth: 28, alignment: .trailing)
        }
        .font(.system(size: 11))
    }
}

struct PressureTag: View {
    var pressure: ActivityReport.Pressure

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(pressure.tint).frame(width: 6, height: 6)
            Text("Pressure \(pressure.text)").foregroundStyle(pressure.textTint)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

// "Widgets": four square tiles, like iOS Home Screen widgets, then the
// next busiest processes.
public struct WidgetsActivityPanel: View {
    var report: ActivityReport
    var actions: ActivityActions

    public init(report: ActivityReport, actions: ActivityActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            if report.hot { HotNote().padding(.horizontal, 4) }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile("CPU", "cpu") { cpu }
                    tile("Memory", "memorychip") { memory }
                }
                GridRow {
                    tile("Network", "network") { network }
                    tile("Busiest", "flame") { busiest }
                }
            }
            if report.processes.count > 1 {
                PanelCard {
                    VStack(spacing: 6) {
                        ForEach(report.processes.dropFirst().prefix(4)) { process in
                            HStack(spacing: 8) {
                                ProcessIcon(process: process, size: 18)
                                ProcessName(process: process).font(.system(size: 12))
                                Spacer(minLength: 6)
                                Text(percentText(process.cpu))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(process.tint)
                            }
                            .monospacedDigit()
                        }
                    }
                    .animatesSamples(report.processes.map(\.id))
                }
            }
            MonitorLinks(actions: actions)
        }
        .statusPanelBackground(width: 330)
    }

    func tile<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(width: 148, height: 132)
        .background(.fill.quaternary, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder var cpu: some View {
        if let load = report.load {
            Text(percentText(load.total))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: load.total))
                .animatesSamples(load)
            Spacer(minLength: 0)
            LoadGraph(history: report.history, lines: false).frame(height: 40)
        } else {
            Measuring()
        }
    }

    @ViewBuilder var memory: some View {
        HStack(spacing: 8) {
            ShareRing(share: report.memoryShare, tint: report.pressure.tint, width: 6)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(percentText(report.memoryShare))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .animatesSamples(report.memoryUsed)
            VStack(alignment: .leading, spacing: 1) {
                Text(byteText(report.memoryUsed)).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("of \(byteText(report.memoryTotal))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .fixedSize()
        }
        Spacer(minLength: 0)
        Text("Pressure \(report.pressure.text)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(report.pressure.textTint)
    }

    @ViewBuilder var network: some View {
        VStack(alignment: .leading, spacing: 3) {
            rate(report.download, "arrow.down")
            rate(report.upload, "arrow.up")
        }
        Spacer(minLength: 0)
        NetworkGraph(history: report.networkHistory).frame(height: 34)
    }

    func rate(_ value: Double?, _ symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(rateText(value)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    @ViewBuilder var busiest: some View {
        if let top = report.processes.first, top.cpu >= 0.01 {
            ProcessIcon(process: top, size: 36)
            Spacer(minLength: 0)
            Text(top.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(percentText(top.cpu))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(top.tint)
        } else if report.load == nil {
            Measuring()
        } else {
            Image(systemName: "leaf").font(.system(size: 26)).foregroundStyle(PanelColors.green)
            Spacer(minLength: 0)
            Text("Nothing is busy").font(.system(size: 12, weight: .medium))
        }
    }
}

// "Top": the process list first, like top or btop, under a CPU/memory/network strip.
public struct TopActivityPanel: View {
    var report: ActivityReport
    var actions: ActivityActions

    public init(report: ActivityReport, actions: ActivityActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            if report.hot { HotNote().padding(.horizontal, 4) }
            HStack(spacing: 8) {
                stat("CPU", report.load.map { percentText($0.total) } ?? "–") {
                    LoadGraph(history: report.history, lines: false)
                }
                stat("Memory", byteText(report.memoryUsed)) {
                    VStack {
                        Spacer(minLength: 0)
                        ShareBar(share: report.memoryShare, tint: report.pressure.tint, height: 8)
                    }
                }
                stat("Network", rateText((report.download ?? 0) + (report.upload ?? 0))) {
                    NetworkGraph(history: report.networkHistory)
                }
            }
            PanelCard {
                if report.processes.isEmpty { Measuring() }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 7) {
                    if !report.processes.isEmpty { GridRow {
                        Text("PROCESS").gridCellColumns(2)
                        Text("CPU").gridColumnAlignment(.trailing)
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("MEMORY").gridColumnAlignment(.trailing)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary) }
                    ForEach(report.processes.prefix(10)) { process in
                        GridRow {
                            ProcessIcon(process: process, size: 16)
                            ProcessName(process: process)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(percentText(process.cpu))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(process.tint)
                            // one core fills the bar; more cores overflow it in red
                            ShareBar(share: process.cpu, tint: process.cpu >= 0.9 ? PanelColors.red : userTint, height: 5)
                                .frame(width: 36)
                            Text(byteText(process.memory))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                }
                .animatesSamples(report.processes.map(\.id))
            }
            MonitorLinks(actions: actions)
        }
        .statusPanelBackground(width: 360)
    }

    func stat<Graph: View>(_ title: String, _ value: String, @ViewBuilder graph: () -> Graph) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
            graph().frame(height: 22)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }
}
