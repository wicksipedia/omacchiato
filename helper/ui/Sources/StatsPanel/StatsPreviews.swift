#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension StatsReport {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")

    static let cpuLight = StatsReport(metric: .cpu, percent: 0.08, cores: 18, top: [
        Process(name: "WindowServer", value: 0.45), Process(name: "coreaudiod", value: 0.15),
        Process(name: "claude", value: 0.09),
    ])

    static let cpuBusy = StatsReport(metric: .cpu, percent: 0.94, cores: 8, top: [
        Process(name: "Final Cut Pro", value: 3.8), Process(name: "Xcode", value: 1.2),
        Process(name: "WindowServer", value: 0.3), Process(name: "kernel_task", value: 0.2),
    ])

    static let ram = StatsReport(metric: .ram, percent: 0.62, used: 39_900_000_000, total: 64_000_000_000,
                                 app: 31_000_000_000, wired: 5_700_000_000, compressed: 3_200_000_000, top: [
        Process(name: "SWBBuildService", value: 2_000_000_000), Process(name: "Xcode", value: 1_800_000_000),
        Process(name: "claude", value: 900_000_000),
    ])

    static let ramFull = StatsReport(metric: .ram, percent: 0.93, used: 59_500_000_000, total: 64_000_000_000,
                                     app: 48_000_000_000, wired: 8_500_000_000, compressed: 3_000_000_000, top: [
        Process(name: "Final Cut Pro", value: 12_000_000_000), Process(name: "Xcode", value: 4_400_000_000),
    ])

    static let disk = StatsReport(metric: .disk, percent: 0.28, used: 564_700_000_000, total: 1_995_200_000_000,
                                  free: 1_430_500_000_000, settings: settingsURL)

    static let diskFull = StatsReport(metric: .disk, percent: 0.91, used: 1_815_800_000_000,
                                      total: 1_995_200_000_000, free: 179_400_000_000, settings: settingsURL)

    static let ramNoTop = StatsReport(metric: .ram, percent: 0.31, used: 19_800_000_000, total: 64_000_000_000,
                                      app: 14_000_000_000, wired: 4_000_000_000, compressed: 1_800_000_000)
}

#Preview("CPU idle") { Desk { StatsPanel(report: .cpuLight) } }
#Preview("CPU busy: red meter") { Desk { StatsPanel(report: .cpuBusy) } }
#Preview("Memory") { Desk { StatsPanel(report: .ram) } }
#Preview("Memory nearly full: red meter") { Desk { StatsPanel(report: .ramFull) } }
#Preview("Memory with no top processes") { Desk { StatsPanel(report: .ramNoTop) } }
#Preview("Disk") { Desk { StatsPanel(report: .disk) } }
#Preview("Disk nearly full: red meter") { Desk { StatsPanel(report: .diskFull) } }
#Preview("Light") { Desk(colors: [.mint, .cyan, .teal]) { StatsPanel(report: .ram) }.preferredColorScheme(.light) }
#endif
