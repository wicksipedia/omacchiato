import AppKit

// `NSString.size(withAttributes:)` returns the typographic box: advance width and line height.
// That box is wrong for centring one glyph in a pill.
// A glyph's ink does not fill its advance. Nerd Font icons have lopsided side bearings.
// A line box also reserves descender room that digits never use.
// On the live bar this put the wifi glyph 4 px right of centre and labels about 1 px high.
//
// So icons centre on their ink box. Text centres on cap height instead, because cap height
// does not move when the content changes: "28°C" and "8:05 PM" sit on the same baseline.
public func inkBox(_ s: String, _ font: NSFont) -> CGRect {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font]))
    return CTLineGetImageBounds(line, nil) // baseline at y = 0
}

public func advance(_ s: String, _ font: NSFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

public func fit(_ s: String, _ font: NSFont, _ width: CGFloat) -> String {
    guard advance(s, font) > width else { return s }
    var cut = s
    while !cut.isEmpty, advance(cut + "…", font) > width { cut.removeLast() }
    return cut.trimmingCharacters(in: .whitespaces) + "…"
}

// `origin` is the baseline. It is the only anchor that means the same thing for every string.
public func drawLine(_ s: String, _ font: NSFont, _ color: NSColor, baseline origin: CGPoint) {
    guard !s.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: s, attributes: [.font: font, .foregroundColor: color]))
    ctx.textPosition = origin
    CTLineDraw(line, ctx)
}

// one glyph, centred on its ink in both axes
public func drawIcon(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    let ink = inkBox(s, font)
    drawLine(s, font, color,
             baseline: CGPoint(x: box.midX - ink.midX, y: box.midY - ink.midY))
}

// a text run: advance-centred across, cap-height-centred down
public func drawText(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    drawLine(s, font, color,
             baseline: CGPoint(x: box.midX - advance(s, font) / 2,
                               y: box.midY - font.capHeight / 2))
}

public func drawText(_ s: String, _ font: NSFont, _ color: NSColor, leftAt x: CGFloat, midY: CGFloat) {
    drawLine(s, font, color, baseline: CGPoint(x: x, y: midY - font.capHeight / 2))
}

// The theme colours a pill draws with.
public struct PillColors {
    public var background: NSColor          // the pill itself
    public var accent: NSColor
    public var label: NSColor
    public var muted: NSColor

    public init(background: NSColor, accent: NSColor, label: NSColor, muted: NSColor) {
        self.background = background
        self.accent = accent
        self.label = label
        self.muted = muted
    }
}
