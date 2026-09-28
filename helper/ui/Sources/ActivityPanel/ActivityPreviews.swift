#if DEBUG
import AppKit
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

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
