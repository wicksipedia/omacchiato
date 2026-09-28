#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension KeepAwakeReport {
    static let one = KeepAwakeReport(holders: [
        Holder(name: "Steam", pid: 1234, duration: "2h 15m"),
    ])

    static let few = KeepAwakeReport(holders: [
        Holder(name: "Zoom", pid: 2345, duration: "48m"),
        Holder(name: "Fantastical", pid: 3456, duration: "12m"),
        Holder(name: "caffeinate", pid: nil, duration: "<1m"),
    ])

    static let long = KeepAwakeReport(holders: [
        Holder(name: "Adobe Creative Cloud Helper (Renderer)", pid: nil, duration: "26h 3m"),
    ])

    static let many = KeepAwakeReport(holders: (1...8).map {
        Holder(name: "App \($0)", pid: nil, duration: "\($0)m")
    })

    static let empty = KeepAwakeReport(holders: [])
}

#Preview("One holder") { Desk { KeepAwakePanel(report: .one) } }
#Preview("A few holders") { Desk { KeepAwakePanel(report: .few) } }
#Preview("A long name") { Desk { KeepAwakePanel(report: .long) } }
#Preview("Many holders") { Desk { KeepAwakePanel(report: .many) } }
#Preview("Nothing holding it") { Desk { KeepAwakePanel(report: .empty) } }
#Preview("Light") { Desk(colors: [.mint, .cyan, .teal]) { KeepAwakePanel(report: .few) }.preferredColorScheme(.light) }
#endif
