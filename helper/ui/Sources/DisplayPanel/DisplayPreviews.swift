#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

#Preview("Display") { Desk { DisplayPanel(report: DisplayReport(brightness: 0.62, shade: 0, nightShift: false)) } }
#Preview("Display: dimmed, Night Shift on") {
    Desk { DisplayPanel(report: DisplayReport(brightness: 0.05, shade: 0.4, nightShift: true)) }
}
#Preview("Display: no built-in display") { Desk { DisplayPanel(report: DisplayReport(brightness: nil)) } }
#Preview("Display: light") {
    Desk(colors: [.mint, .cyan, .teal]) { DisplayPanel(report: DisplayReport(brightness: 0.8, nightShift: false)) }
        .preferredColorScheme(.light)
}
#endif
