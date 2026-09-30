import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the bar shows in place of the macOS volume HUD when a volume key is
// pressed: the output, a level bar in 16 notches, and the percent.
public struct VolumeOSD: View {
    var report: SoundReport

    public init(report: SoundReport) {
        self.report = report
    }

    var output: SoundReport.Output? { report.outputs.first { $0.current } }
    var level: Double { report.muted ? 0 : Swift.min(1, Swift.max(0, report.volume)) }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.speakerSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(report.muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(PanelColors.accent))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    if let output {
                        Image(systemName: output.symbol).font(.system(size: 10))
                        Text(output.name).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Text(report.muted ? "Muted" : "\(Int((report.volume * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                Notches(level: level, tint: report.muted ? .gray : PanelColors.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 260)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

// 16 blocks, as the macOS HUD counts steps. A block between two steps fills in part.
struct Notches: View {
    var level: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { i in
                let fill = Swift.min(1, Swift.max(0, level * 16 - Double(i)))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.fill.tertiary)
                        RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: geo.size.width * fill)
                    }
                }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
