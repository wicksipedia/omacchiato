import Foundation
import Testing
import StatusPanel
@testable import BluetoothPanel
@testable import SoundPanel

@Suite struct BuiltinPanelTests {
    @Test("the speaker symbol follows the volume, and mute wins")
    func speaker() {
        #expect(SoundReport(volume: 0.2).speakerSymbol == "speaker.wave.1.fill")
        #expect(SoundReport(volume: 0.5).speakerSymbol == "speaker.wave.2.fill")
        #expect(SoundReport(volume: 0.9).speakerSymbol == "speaker.wave.3.fill")
        #expect(SoundReport(volume: 0.9, muted: true).speakerSymbol == "speaker.slash.fill")
        #expect(SoundReport(volume: 0).speakerSymbol == "speaker.slash.fill")
    }

    @Test("an output's symbol comes from its transport, then its name")
    func outputSymbol() {
        typealias O = SoundReport.Output
        #expect(O(id: 1, name: "MacBook Pro Speakers", transport: .builtIn).symbol == "laptopcomputer")
        #expect(O(id: 1, name: "Mac Studio Speakers", transport: .builtIn).symbol == "hifispeaker.fill")
        #expect(O(id: 1, name: "Matt’s AirPods Max", transport: .bluetooth).symbol == "airpodsmax")
        #expect(O(id: 1, name: "Matt’s AirPods Pro", transport: .bluetooth).symbol == "airpods.pro")
        #expect(O(id: 1, name: "Living Room", transport: .airPlay).symbol == "airplayaudio")
    }

    @Test("a Bluetooth device's symbol comes from its class, then its name")
    func deviceSymbol() {
        typealias D = BluetoothReport.Device
        #expect(D(id: "a", name: "Matt’s AirPods Max", kind: .audio).symbol == "airpodsmax")
        #expect(D(id: "a", name: "Sony WH-1000XM5", kind: .audio).symbol == "headphones")
        #expect(D(id: "a", name: "Magic Keyboard", kind: .keyboard).symbol == "keyboard.fill")
        #expect(D(id: "a", name: "Pad", kind: .gamepad).symbol == "gamecontroller.fill")
    }
}

@Suite struct UpdatedStampTests {
    @Test("the stamp says just now under a minute, then the age in words")
    func text() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(updatedText(now.addingTimeInterval(-20), now: now) == "Updated just now")
        #expect(updatedText(now.addingTimeInterval(-180), now: now) == "Updated 3 minutes ago")
        #expect(updatedText(now.addingTimeInterval(-7200), now: now) == "Updated 2 hours ago")
    }
}
