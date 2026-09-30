#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension UpdatesReport {
    static func commit(_ subject: String, hash: String = "a1b2c3d", age: String = "2 hours ago") -> Commit {
        Commit(hash: hash, subject: subject, age: age)
    }

    static let updateCommand = "/bin/sh -c 'omacchiato-update; read'"

    static let one = UpdatesReport(target: "v2026.10.01", commits: [commit("Fix a race in the theme watcher")],
                                   update: updateCommand, updated: Date().addingTimeInterval(-120))

    static let few = UpdatesReport(target: "v2026.10.01", commits: [
        commit("Show the AirPods popup as a panel with a picture of the product", hash: "ee369ed", age: "3 hours ago"),
        commit("Turn the battery ring yellow in Low Power Mode", hash: "85bf981", age: "1 day ago"),
        commit("Install the binaries from a GitHub release instead of building them", hash: "df2831e", age: "2 days ago"),
    ], update: updateCommand, updated: Date().addingTimeInterval(-600))

    static let many = UpdatesReport(
        target: "v2026.10.15",
        commits: (0..<10).map { commit("Commit number \($0 + 1)", hash: String(format: "%07x", $0)) },
        more: 6, update: updateCommand, updated: Date().addingTimeInterval(-1800))

    static let noRelease = UpdatesReport(target: nil, commits: [commit("Add the updates panel")], update: updateCommand,
                                         updated: Date().addingTimeInterval(-300))

    static let longSubject = UpdatesReport(target: "v2026.10.01", commits: [
        commit("Rewrite the gesture daemon's haptic actuator handling so a long-idle handle reopens instead of reporting a silent success",
              age: "3 weeks ago"),
    ], update: updateCommand, updated: Date().addingTimeInterval(-3000))

    static let edge = UpdatesReport(commits: [commit("Drop a variable that the Settings report no longer changes")] + few.commits,
                                    update: updateCommand, updated: Date().addingTimeInterval(-120),
                                    channel: "edge", counts: ["release": 3, "edge": 4])

    static let stale = UpdatesReport(target: "v2026.10.01", commits: [commit("Fix a race in the theme watcher")],
                                     update: updateCommand, updated: Date().addingTimeInterval(-5 * 3600))
}

#Preview("One commit") { Desk { UpdatesPanel(report: .one) } }
#Preview("A few commits") { Desk { UpdatesPanel(report: .few) } }
#Preview("Many commits") { Desk { UpdatesPanel(report: .many) } }
#Preview("No release yet") { Desk { UpdatesPanel(report: .noRelease) } }
#Preview("A long subject") { Desk { UpdatesPanel(report: .longSubject) } }
#Preview("Edge") { Desk { UpdatesPanel(report: .edge) } }
#Preview("Stale fetch") { Desk { UpdatesPanel(report: .stale) } }
#Preview("Light") { Desk(colors: [.mint, .cyan, .teal]) { UpdatesPanel(report: .few) }.preferredColorScheme(.light) }
#endif
