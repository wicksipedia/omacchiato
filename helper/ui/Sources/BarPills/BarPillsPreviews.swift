#if DEBUG
import SwiftUI

// Icons come from apps on this Mac, not bundled images.
private func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
private let safari = icon("/System/Applications/Safari.app")
private let mail = icon("/System/Applications/Mail.app")
private let notes = icon("/System/Applications/Notes.app")
private let music = icon("/System/Applications/Music.app")

private func nerd(_ size: CGFloat) -> NSFont {
    NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: "JetBrainsMono Nerd Font", .face: "Bold"]), size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: .bold)
}

private struct StripTheme {
    var name: String
    var bar: NSColor
    var colors: PillColors
}

private let themes = [
    StripTheme(name: "catppuccin-latte", bar: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 0.9),
          colors: PillColors(background: .clear, accent: NSColor(srgbRed: 0.53, green: 0.22, blue: 0.94, alpha: 1),
                             label: NSColor(srgbRed: 0.30, green: 0.31, blue: 0.41, alpha: 1),
                             muted: NSColor(srgbRed: 0.61, green: 0.63, blue: 0.69, alpha: 1))),
    StripTheme(name: "tokyo-night", bar: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 0.9),
          colors: PillColors(background: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.26, alpha: 1),
                             accent: NSColor(srgbRed: 0.48, green: 0.64, blue: 0.97, alpha: 1),
                             label: NSColor(srgbRed: 0.75, green: 0.79, blue: 0.96, alpha: 1),
                             muted: NSColor(srgbRed: 0.34, green: 0.37, blue: 0.54, alpha: 1))),
]

private let chips: [WorkspaceChip] = [
    WorkspaceChip(face: .digit("1")),
    WorkspaceChip(face: .hand([safari], ring: 0), focused: true, shown: true),
    WorkspaceChip(face: .hand([mail, notes], ring: 1), focused: true),
    WorkspaceChip(face: .hand([safari, mail, notes], ring: nil)),
    WorkspaceChip(face: .glyph("\u{f489}")),
    WorkspaceChip(face: .image(music)),
    WorkspaceChip(face: .digit("7")),
]

private final class Strip: NSView {
    let theme: StripTheme
    let marquee = Marquee()
    let ticker = Ticker()
    static let barHeight: CGFloat = 34, pillHeight: CGFloat = 26

    init(_ theme: StripTheme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 1040, height: Self.barHeight))
        widthAnchor.constraint(equalToConstant: 1040).isActive = true
        heightAnchor.constraint(equalToConstant: Self.barHeight).isActive = true
        addSubview(marquee)
        addSubview(ticker)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        theme.bar.setFill()
        bounds.fill()
        let text = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let slots = drawWorkspaces(chips, x: 10, barHeight: Self.barHeight, pillHeight: Self.pillHeight, radius: 4,
                                   digitFont: text, glyphFont: nerd(14), colors: theme.colors)
        var x = (slots.last?.maxX ?? 0) + 12
        let pills = [MediaPill(title: "Tonight, Tonight, Tonight", art: music),
                     MediaPill(title: "No art yet"),
                     MediaPill(title: "BEAT CRUSADERS — Tonight, Tonight, Tonight (Live at Budokan)", art: music)]
        for (i, media) in pills.enumerated() {
            let cap = MediaPill.chrome(pillHeight: Self.pillHeight) + 180
            let width = media.layout(font: text, maxWidth: cap, pillHeight: Self.pillHeight).width
            let pill = NSRect(x: x, y: (Self.barHeight - Self.pillHeight) / 2, width: width, height: Self.pillHeight)
            let title = media.draw(in: pill, font: text, maxWidth: cap, radius: 4, placeholderFont: nerd(12),
                                   colors: theme.colors)
            if i == pills.count - 1 {
                marquee.show(media.title, font: text, color: theme.colors.label, in: title)
            } else {
                drawText(media.title, text, theme.colors.label, leftAt: title.minX, midY: title.midY)
            }
            x = pill.maxX + 12
        }
        let clock = NSRect(x: x, y: 0, width: advance("Mon 28 Sep  9:41", text), height: Self.barHeight)
        ticker.show("Mon 28 Sep  9:41", "Standup", "in 5m", font: text,
                    colors: (theme.colors.label, .systemYellow), in: clock)
    }
}

private func strips() -> NSView {
    let stack = NSStackView(views: themes.map { Strip($0) })
    stack.orientation = .vertical
    stack.spacing = 0
    return stack
}

#Preview("Bar pills") { strips() }
#endif
