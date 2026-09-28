import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Pieces that every design of the activity panel shares.

// The samples that a graph holds: 40 samples of 1.5 s make a minute.
public let activityHistoryLimit = 40

// Activity Monitor's colours: blue for user time, red for system time.
let userTint = Color.blue
let systemTint = PanelColors.red

extension ActivityReport.Pressure {
    var tint: Color {
        switch self {
        case .normal: return PanelColors.green
        case .warning: return PanelColors.yellow
        case .critical: return PanelColors.red
        }
    }

    // Yellow text does not read on the light panel.
    var textTint: AnyShapeStyle {
        switch self {
        case .normal: return AnyShapeStyle(.secondary)
        case .warning: return AnyShapeStyle(PanelColors.orange)
        case .critical: return AnyShapeStyle(PanelColors.red)
        }
    }

    var text: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "High"
        case .critical: return "Critical"
        }
    }
}

extension ActivityReport.Process {
    // A process that holds most of a core for itself stands out.
    var tint: Color { cpu >= 0.9 ? PanelColors.red : (cpu >= 0.5 ? PanelColors.orange : .primary) }
}

// A filled line of the last samples. It starts at the right edge and
// fills left, so a new sample always lands in the same spot.
struct Sparkline: Shape {
    var values: [Double]                    // 0...1
    var slots = activityHistoryLimit
    var filled = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(max(1, slots - 1))
        let start = rect.maxX - step * CGFloat(values.count - 1)
        let points = values.enumerated().map { i, v in
            CGPoint(x: start + step * CGFloat(i), y: rect.maxY - rect.height * CGFloat(min(1, max(0, v))))
        }
        path.addLines(points)
        if filled {
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// The CPU load of the last minute, system time under user time, as
// Activity Monitor draws it.
struct LoadGraph: View {
    var history: [ActivityReport.Load]
    var lines = true

    var body: some View {
        ZStack {
            Sparkline(values: history.map(\.total)).fill(userTint.opacity(0.35))
            Sparkline(values: history.map(\.system)).fill(systemTint.opacity(0.45))
            if lines {
                Sparkline(values: history.map(\.total), filled: false)
                    .stroke(userTint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .background {
            // quarter lines, so the height reads as a share
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    Divider().opacity(0.5)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// One bar for each core, as the CPU History window draws them.
struct CoreBars: View {
    var cores: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(cores.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.fill.tertiary)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2).fill(userTint.gradient)
                                .frame(height: max(2, geo.size.height * CGFloat(min(1, cores[i]))))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(cores.count) cores")
    }
}

// A share as a ring, as the iOS battery widget draws it.
struct ShareRing: View {
    var share: Double
    var tint: Color
    var width: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(.fill.tertiary, lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0.005, share))))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
    }
}

struct ProcessIcon: View {
    var process: ActivityReport.Process
    var size: CGFloat

    var body: some View {
        Group {
            if let icon = process.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                // a command with no app: the Terminal glyph, as Activity Monitor shows one
                Image(systemName: "apple.terminal")
                    .font(.system(size: size * 0.62))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// The name of a row, with the number of processes when it holds more than one.
struct ProcessName: View {
    var process: ActivityReport.Process

    var body: some View {
        HStack(spacing: 4) {
            Text(process.name).lineLimit(1).truncationMode(.middle)
            if process.count > 1 {
                Text("\(process.count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.fill.tertiary, in: .capsule)
                    .help("\(process.count) processes")
            }
        }
        .help(process.name)
    }
}

// The first sample needs a second one before it shows a load.
struct Measuring: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg").foregroundStyle(.secondary)
            Text("Measuring…").foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

// The note when macOS slows the CPU because the Mac is hot.
struct HotNote: View {
    var body: some View {
        Label("The Mac is hot, so macOS slows the CPU.", systemImage: "thermometer.high")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(PanelColors.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LinkRow: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        HoverRow(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
        }
    }
}

// The rows that open a full monitor.
struct MonitorLinks: View {
    var actions: ActivityActions

    var body: some View {
        VStack(spacing: 0) {
            LinkRow(title: "Activity Monitor", symbol: "chart.bar.xaxis", action: actions.openActivityMonitor)
            if let btop = actions.openTerminalMonitor {
                LinkRow(title: "btop in a terminal", symbol: "apple.terminal", action: btop)
            }
        }
    }
}

struct ShareBar: View {
    var share: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.fill.tertiary)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint.gradient)
                        .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, share)))))
                }
        }
        .frame(height: height)
    }
}

// The download and upload rates, with arrows as Activity Monitor labels them.
struct Rates: View {
    var report: ActivityReport
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 10) {
            Label(rateText(report.download), systemImage: "arrow.down")
            Label(rateText(report.upload), systemImage: "arrow.up")
        }
        .labelStyle(RateLabelStyle())
        .font(.system(size: size, weight: .medium, design: .rounded))
        .monospacedDigit()
    }
}

struct RateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

// The network rates of the last minute, scaled to the fastest sample.
struct NetworkGraph: View {
    var history: [Double]

    var body: some View {
        let top = max(history.max() ?? 0, 1)
        let values = history.map { $0 / top }
        Sparkline(values: values)
            .fill(Color.purple.opacity(0.35))
            .overlay {
                Sparkline(values: values, filled: false)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .accessibilityHidden(true)
    }
}

// The animation for a new sample. Reduce motion shows the new values at once.
struct SampleAnimation<V: Equatable>: ViewModifier {
    var value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.35), value: value)
    }
}

extension View {
    func animatesSamples<V: Equatable>(_ value: V) -> some View { modifier(SampleAnimation(value: value)) }
}
