import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// A small desktop in a theme's colours: wallpaper, bar, and two tiled
// windows, a focused terminal and an unfocused editor. Every colour comes
// from the theme's files.
struct ThemeMockup: View {
    var theme: Theme
    var top: CGFloat = 8                    // the corner radius at the top, and at the bottom
    var bottom: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let gap = w * 0.02
            let barH = h * 0.075
            let winW = w - gap * 3, winH = h - barH - gap * 2
            ZStack(alignment: .topLeading) {
                wallpaper.frame(width: w, height: h).clipped()
                MockBar(theme: theme, height: barH).frame(width: w)
                HStack(spacing: gap) {
                    MockWindow(theme: theme, focused: true) { MockTerminal(theme: theme, scale: w / 360) }
                        .frame(width: winW * 0.58, height: winH)
                    MockWindow(theme: theme, focused: false) { MockEditor(theme: theme, scale: w / 360) }
                        .frame(width: winW * 0.42, height: winH)
                }
                .offset(x: gap, y: barH + gap)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                          bottomTrailingRadius: bottom, topTrailingRadius: top))
        .accessibilityElement()
        .accessibilityLabel("A desktop in \(theme.title)")
    }

    @ViewBuilder var wallpaper: some View {
        if let image = theme.wallpaper {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [theme.terminal.background, theme.bar.accent.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct MockBar: View {
    var theme: Theme
    var height: CGFloat

    var body: some View {
        let s = height * 0.55
        HStack(spacing: s * 0.6) {
            Image(systemName: "apple.logo").foregroundStyle(theme.bar.accent)
            HStack(spacing: s * 0.35) {
                ForEach(1...4, id: \.self) { i in
                    Text("\(i)").foregroundStyle(i == 1 ? theme.bar.accent : theme.bar.muted)
                }
            }
            .padding(.horizontal, s * 0.4)
            .background(theme.bar.item, in: .capsule)
            Text("Ghostty").fontWeight(.bold).foregroundStyle(theme.bar.accent)
            Spacer()
            Image(systemName: "wifi")
            Text("Mon 9:41")
        }
        .font(.system(size: s, weight: .medium))
        .foregroundStyle(theme.bar.label)
        .padding(.horizontal, s * 0.7)
        .lineLimit(1)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(theme.bar.background)
    }
}

struct MockWindow<Content: View>: View {
    var theme: Theme
    var focused: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        let border: AnyShapeStyle = focused
            ? theme.border.gradient.map { AnyShapeStyle(LinearGradient(colors: [theme.border.active, $0],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing)) }
                ?? AnyShapeStyle(theme.border.active)
            : AnyShapeStyle(theme.border.inactive)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.terminal.background, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(border, lineWidth: focused ? 1.5 : 1))
            .shadow(color: focused && theme.border.glow ? theme.border.active.opacity(0.7) : .clear, radius: 5)
    }
}

// A prompt, a listing in the palette's colours, and the cursor.
struct MockTerminal: View {
    var theme: Theme
    var scale: CGFloat

    var body: some View {
        let p = theme.terminal.palette
        VStack(alignment: .leading, spacing: 2 * scale) {
            prompt("ls")
            HStack(spacing: 6 * scale) {
                Text("bin").foregroundStyle(p[4]).bold()
                Text("config").foregroundStyle(p[4]).bold()
                Text("install.sh").foregroundStyle(p[2]).bold()
                Text("README.md")
            }
            prompt("git status")
            Text("On branch main").foregroundStyle(p[8])
            Text("  modified:   bar.swift").foregroundStyle(p[1])
            Text("  new file:   theme.swift").foregroundStyle(p[2])
            HStack(spacing: 0) {
                prompt("")
                Rectangle().fill(theme.terminal.cursor).frame(width: 5 * scale, height: 9 * scale)
            }
        }
        .font(.system(size: 7.5 * scale, design: .monospaced))
        .foregroundStyle(theme.terminal.foreground)
        .lineLimit(1)
        .padding(7 * scale)
    }

    func prompt(_ command: String) -> some View {
        let p = theme.terminal.palette
        return HStack(spacing: 4 * scale) {
            Text("~/omacchiato").foregroundStyle(p[6])
            Text("❯").foregroundStyle(p[5])
            if !command.isEmpty { Text(command) }
        }
    }
}

// Lines of code drawn as coloured bars, as syntax highlighting reads at a distance.
struct MockEditor: View {
    var theme: Theme
    var scale: CGFloat

    static let lines: [[(Int, CGFloat)]] = [
        [(5, 18), (4, 30)], [(8, 40)], [(5, 14), (6, 22), (3, 16)], [(0, 0)],
        [(5, 18), (4, 26), (2, 20)], [(7, 10), (1, 24)], [(7, 10), (3, 30)], [(8, 8)],
        [(0, 0)], [(5, 14), (4, 36)], [(7, 12), (2, 28)],
    ]

    var body: some View {
        let p = theme.terminal.palette
        VStack(alignment: .leading, spacing: 4 * scale) {
            ForEach(Self.lines.indices, id: \.self) { i in
                HStack(spacing: 3 * scale) {
                    ForEach(Self.lines[i].indices, id: \.self) { j in
                        let (color, width) = Self.lines[i][j]
                        Capsule().fill(color == 7 ? theme.terminal.foreground : p[color])
                            .frame(width: width * scale, height: 3 * scale)
                    }
                }
                .padding(.leading, CGFloat(i % 3 == 1 ? 8 : 0) * scale)
                .frame(height: 3 * scale)
            }
        }
        .padding(8 * scale)
    }
}

// Which slot the cards set: a segmented control, drawn by hand because a
// system Picker draws grey in a non-key window. Each segment names its theme.
enum DaySlot { case day, night }

struct SlotPicker: View {
    @Binding var slot: DaySlot
    var day: Theme?
    var night: Theme?

    var body: some View {
        HStack(spacing: 2) {
            segment(.day, "sun.max.fill", "Day", day)
            segment(.night, "moon.fill", "Night", night)
        }
        .padding(2)
        .background(.fill.tertiary, in: .rect(cornerRadius: 9))
    }

    func segment(_ value: DaySlot, _ symbol: String, _ label: String, _ theme: Theme?) -> some View {
        let on = slot == value
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(value == .day ? Color.orange : Color.indigo)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(theme?.title ?? "None").font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(on ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
        .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy(duration: 0.15)) { slot = value } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

// Apply, drawn by hand: a system button in a window that is not key draws grey.
struct ApplyButton: View {
    var enabled: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 5) {
            if !enabled { Image(systemName: "checkmark") }
            Text(enabled ? "Apply" : "Applied")
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 16)
        .frame(height: 28)
        .foregroundStyle(enabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .background(enabled ? AnyShapeStyle(PanelColors.accent.opacity(hovered ? 0.85 : 1)) : AnyShapeStyle(.fill.tertiary),
                    in: .capsule)
        .contentShape(.capsule)
        .onHover { hovered = $0 }
        .onTapGesture { if enabled { action() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(enabled ? .isButton : [])
    }
}
