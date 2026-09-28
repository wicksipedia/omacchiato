#if DEBUG
import AppKit
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Sample minutes for the previews: a quiet desk, a build, a runaway
// process, and the states that break a layout.
extension ActivityReport {
    static let gib: UInt64 = 1 << 30
    static let mib: UInt64 = 1 << 20

    static func icon(_ path: String) -> NSImage? { NSWorkspace.shared.icon(forFile: path) }

    // A minute of load that wanders around `level`, the same on every run.
    static func minute(_ level: Double, swing: Double, system: Double = 0.3) -> [Load] {
        (0..<activityHistoryLimit).map { i -> Load in
            let t = Double(i)
            let total = min(1, max(0.01, level + swing * sin(t / 3.1) * cos(t / 7.3)))
            return Load(user: total * (1 - system), system: total * system)
        }
    }

    static func traffic(_ level: Double) -> [Double] {
        (0..<activityHistoryLimit).map { i -> Double in level * (1.2 + sin(Double(i) / 2.3) + 0.6 * cos(Double(i) / 0.9)) }
    }

    static let apps: [Process] = [
        Process(id: "/Applications/Safari.app", name: "Safari",
                icon: icon("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"),
                cpu: 0.18, memory: 2 * gib + 310 * mib, count: 14),
        Process(id: "/Applications/Xcode.app", name: "Xcode", icon: icon("/Applications/Xcode.app"),
                cpu: 0.09, memory: 1 * gib + 820 * mib, count: 3),
        Process(id: "/System/Applications/Mail.app", name: "Mail", icon: icon("/System/Applications/Mail.app"),
                cpu: 0.04, memory: 412 * mib, count: 5),
        Process(id: "/Applications/Ghostty.app", name: "Ghostty", icon: icon("/Applications/Ghostty.app"),
                cpu: 0.03, memory: 188 * mib),
        Process(id: "/usr/libexec/mds_stores", name: "mds_stores", cpu: 0.02, memory: 96 * mib),
        Process(id: "/System/Applications/Music.app", name: "Music", icon: icon("/System/Applications/Music.app"),
                cpu: 0.01, memory: 240 * mib, count: 2),
        Process(id: "/usr/sbin/bluetoothd", name: "bluetoothd", cpu: 0.01, memory: 18 * mib),
        Process(id: "/System/Applications/Notes.app", name: "Notes", icon: icon("/System/Applications/Notes.app"),
                cpu: 0.0, memory: 160 * mib),
        Process(id: "/usr/libexec/trustd", name: "trustd", cpu: 0.0, memory: 12 * mib),
        Process(id: "/usr/sbin/cfprefsd", name: "cfprefsd", cpu: 0.0, memory: 9 * mib, count: 2),
    ]

    static let quiet = ActivityReport(
        load: Load(user: 0.05, system: 0.03), history: minute(0.08, swing: 0.04),
        cores: [0.12, 0.08, 0.05, 0.04, 0.02, 0.01, 0.01, 0.0, 0.03, 0.01],
        memoryUsed: 9 * gib + 400 * mib, memoryTotal: 16 * gib, compressed: 1 * gib + 120 * mib,
        download: 42_000, upload: 8_000, networkHistory: traffic(40_000), processes: apps)

    // swift build in a terminal while Safari plays a video.
    static let building = ActivityReport(
        load: Load(user: 0.61, system: 0.14), history: minute(0.62, swing: 0.25, system: 0.2),
        cores: [0.98, 0.95, 0.91, 0.88, 0.79, 0.72, 0.64, 0.51, 0.44, 0.38],
        memoryUsed: 13 * gib + 700 * mib, memoryTotal: 16 * gib, compressed: 2 * gib + 900 * mib,
        swapUsed: 512 * mib, pressure: .warning, download: 18_400_000, upload: 1_200_000,
        networkHistory: traffic(9_000_000),
        processes: [Process(id: "/usr/bin/swift-frontend", name: "swift-frontend", cpu: 5.84, memory: 3 * gib, count: 8),
                    Process(id: "/usr/bin/ld", name: "ld", cpu: 0.72, memory: 640 * mib)] + apps)

    // A stuck node process holds four cores, and the Mac is hot.
    static let runaway = ActivityReport(
        load: Load(user: 0.42, system: 0.06), history: minute(0.45, swing: 0.05, system: 0.12),
        cores: [1, 1, 1, 1, 0.12, 0.08, 0.06, 0.04, 0.02, 0.02],
        memoryUsed: 15 * gib + 600 * mib, memoryTotal: 16 * gib, compressed: 5 * gib + 200 * mib,
        swapUsed: 6 * gib + 300 * mib, pressure: .critical, download: 0, upload: 0,
        networkHistory: [Double](repeating: 0, count: activityHistoryLimit),
        processes: [Process(id: "/opt/homebrew/bin/node", name: "node", cpu: 3.98, memory: 7 * gib + 100 * mib)] + apps,
        hot: true)

    // Names that do not fit, and one row for each of many helpers.
    static let longNames = ActivityReport(
        load: quiet.load, history: quiet.history, cores: quiet.cores,
        memoryUsed: quiet.memoryUsed, memoryTotal: quiet.memoryTotal, compressed: quiet.compressed,
        download: quiet.download, upload: quiet.upload, networkHistory: quiet.networkHistory,
        processes: [Process(id: "/Applications/Microsoft Teams.app", name: "Microsoft Teams (work or school) Classic",
                            icon: icon("/Applications/Microsoft Teams.app"), cpu: 1.12, memory: 3 * gib, count: 23),
                    Process(id: "/usr/libexec/com.apple.appkit.xpc.openAndSavePanelService",
                            name: "com.apple.appkit.xpc.openAndSavePanelService", cpu: 0.31, memory: 88 * mib)] + apps)

    // The first moment after the popup opens: one sample, no load yet.
    static let measuring = ActivityReport(
        load: nil, memoryUsed: 9 * gib + 400 * mib, memoryTotal: 16 * gib, compressed: 1 * gib)
}

private let minutes: [ActivityReport] = [.quiet, .building, .runaway, .longNames, .measuring]

private func btop() {}

private var withBtop: ActivityActions {
    var actions = ActivityActions()
    actions.openTerminalMonitor = btop
    return actions
}

#Preview("Monitor") { Desk { MonitorActivityPanel(report: .building, actions: withBtop) } }
#Preview("Widgets") { Desk { WidgetsActivityPanel(report: .building, actions: withBtop) } }
#Preview("Top") { Desk { TopActivityPanel(report: .building, actions: withBtop) } }

#Preview("Monitor: every minute") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(minutes.indices, id: \.self) { MonitorActivityPanel(report: minutes[$0]) } } }
}

#Preview("Widgets: every minute") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(minutes.indices, id: \.self) { WidgetsActivityPanel(report: minutes[$0]) } } }
}

#Preview("Top: every minute") {
    Desk { HStack(alignment: .top, spacing: 16) { ForEach(minutes.indices, id: \.self) { TopActivityPanel(report: minutes[$0]) } } }
}

#Preview("Monitor, dark") { Desk { MonitorActivityPanel(report: .runaway, actions: withBtop) }.preferredColorScheme(.dark) }
#endif
