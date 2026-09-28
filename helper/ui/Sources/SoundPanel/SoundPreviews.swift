#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension SoundReport {
    static let desk = SoundReport(volume: 0.46, outputs: [
        Output(id: 1, name: "MacBook Pro Speakers", transport: .builtIn),
        Output(id: 2, name: "Matt’s AirPods Pro", transport: .bluetooth, current: true),
        Output(id: 3, name: "LG UltraFine Display Audio", transport: .display),
        Output(id: 4, name: "Living Room", transport: .airPlay),
    ])
    static let muted = SoundReport(volume: 0.7, muted: true, outputs: [
        Output(id: 1, name: "MacBook Pro Speakers", transport: .builtIn, current: true),
    ])
    static let loud = SoundReport(volume: 1, outputs: [
        Output(id: 1, name: "MacBook Pro Speakers", transport: .builtIn),
        Output(id: 5, name: "A USB audio interface with a very long product name", transport: .usb, current: true),
    ])
}

#Preview("Sound") { Desk { SoundPanel(report: .desk) } }
#Preview("Sound: muted") { Desk { SoundPanel(report: .muted) } }
#Preview("Sound: full, long name") { Desk { SoundPanel(report: .loud) } }
#Preview("Sound: light") { Desk(colors: [.mint, .cyan, .teal]) { SoundPanel(report: .desk) }.preferredColorScheme(.light) }
#endif
