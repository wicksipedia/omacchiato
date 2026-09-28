import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the volume popup shows. The bar reads it from CoreAudio, and the
// previews build it by hand.
public struct SoundReport {
    public enum Transport: String { case builtIn, bluetooth, display, airPlay, usb, virtual, other }

    public struct Output: Identifiable {
        public var id: UInt32            // the CoreAudio device ID
        public var name: String
        public var transport: Transport
        public var current: Bool

        public init(id: UInt32, name: String, transport: Transport = .other, current: Bool = false) {
            self.id = id
            self.name = name
            self.transport = transport
            self.current = current
        }

        public var symbol: String {
            switch transport {
            case .builtIn: return name.contains("MacBook") ? "laptopcomputer" : "hifispeaker.fill"
            case .bluetooth:
                if name.contains("AirPods Max") { return "airpodsmax" }
                if name.contains("AirPods") { return "airpods.pro" }
                if name.contains("Beats") { return "beats.headphones" }
                return "headphones"
            case .display: return "display"
            case .airPlay: return "airplayaudio"
            case .usb: return "hifispeaker.fill"
            case .virtual: return "waveform"
            case .other: return "speaker.wave.2.fill"
            }
        }
    }

    public var volume: Double            // 0...1
    public var muted: Bool
    public var outputs: [Output]

    public init(volume: Double, muted: Bool = false, outputs: [Output] = []) {
        self.volume = volume
        self.muted = muted
        self.outputs = outputs
    }

    public var speakerSymbol: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : (volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }
}

public struct SoundActions {
    public var setVolume: (Double) -> Void = { _ in }
    public var toggleMute: () -> Void = {}
    public var selectOutput: (UInt32) -> Void = { _ in }
    public var openSettings: () -> Void = {}

    public init() {}
}

// The Sound module of Control Center: the slider, then the outputs.
public struct SoundPanel: View {
    var report: SoundReport
    var actions: SoundActions

    public init(report: SoundReport, actions: SoundActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            PanelCard(title: "Sound", symbol: "speaker.wave.2.fill") {
                HStack(spacing: 10) {
                    ControlSlider(value: report.muted ? 0 : report.volume, symbol: report.speakerSymbol,
                                  tint: report.muted ? .gray : PanelColors.accent,
                                  onSlide: actions.setVolume, onSymbolTap: actions.toggleMute)
                    Text(report.muted ? "Muted" : "\(Int((report.volume * 100).rounded()))%")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            if !report.outputs.isEmpty {
                PanelCard(title: "Output", symbol: "hifispeaker.2.fill") {
                    VStack(spacing: 0) {
                        ForEach(report.outputs) { output in
                            HStack {
                                ControlTile(title: output.name, symbol: output.symbol, on: output.current,
                                            action: output.current ? nil : { actions.selectOutput(output.id) })
                                if output.current {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(PanelColors.accent)
                                        .padding(.trailing, 6)
                                }
                            }
                        }
                    }
                }
            }
            SettingsRow(title: "Sound Settings", action: actions.openSettings)
        }
        .statusPanelBackground()
    }
}
