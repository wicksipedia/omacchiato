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

// A colour emoji keeps its own colours whatever the theme, so it can
// vanish into the bar, as a yellow moon does on a pale pink one.
public func isColorEmoji(_ s: String) -> Bool {
    guard let first = s.unicodeScalars.first else { return false }
    return first.properties.isEmojiPresentation
        || (first.properties.isEmoji && s.unicodeScalars.contains("\u{FE0F}"))
}

// one glyph, centred on its ink in both axes. A colour emoji gets a soft
// halo in `color`, the bar's text colour, so it stands out on any theme.
public func drawIcon(_ s: String, _ font: NSFont, _ color: NSColor, centeredIn box: CGRect) {
    let ink = inkBox(s, font)
    let origin = CGPoint(x: box.midX - ink.midX, y: box.midY - ink.midY)
    guard isColorEmoji(s) else {
        drawLine(s, font, color, baseline: origin)
        return
    }
    let halo = haloImage(s, font, color)
    halo.draw(at: CGPoint(x: origin.x + ink.minX - haloPad, y: origin.y + ink.minY - haloPad),
              from: .zero, operation: .sourceOver, fraction: 1)
}

// The halo is drawn once into a small image and cached. A shadow drawn
// straight into the bar made the window server paint the whole bar
// through a 300 MB offscreen buffer on every redraw.
let haloPad: CGFloat = 5
private var haloCache: [String: NSImage] = [:]

func haloImage(_ s: String, _ font: NSFont, _ color: NSColor) -> NSImage {
    let key = "\(s)|\(font.pointSize)|\(color.usingColorSpace(.sRGB)?.description ?? "")"
    if let cached = haloCache[key] { return cached }
    let ink = inkBox(s, font)
    let image = NSImage(size: CGSize(width: ink.width + 2 * haloPad, height: ink.height + 2 * haloPad),
                        flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.setShadow(offset: .zero, blur: 2.5, color: color.cgColor)
        let baseline = CGPoint(x: haloPad - ink.minX, y: haloPad - ink.minY)
        // two passes: one shadow alone is too faint to lift a pale glyph
        drawLine(s, font, color, baseline: baseline)
        drawLine(s, font, color, baseline: baseline)
        return true
    }
    if haloCache.count > 32 { haloCache.removeAll() }
    haloCache[key] = image
    return image
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

// A plugin pill: its own icon and label, then any parts the plugin adds,
// each an icon and a label. A part can colour its label, such as a quiet time.
public struct PillPart {
    public var icon: String
    public var iconColor: NSColor?
    public var label: String
    public var labelColor: NSColor?
    public var under: Bool                  // stack the label under the label of the part before

    public init(icon: String = "", iconColor: NSColor? = nil, label: String = "", labelColor: NSColor? = nil,
                under: Bool = false) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.labelColor = labelColor
        self.under = under
    }
}

public struct PartsPill {
    // A part, and the label stacked under its own, if any.
    typealias Slot = (part: PillPart, under: PillPart?)
    var slots: [Slot] = []
    public var iconOnly: Bool               // `<pill> = icon` in bar-pills.conf drops the labels

    public static let pad: CGFloat = 6      // each side, inside the pill
    static let partGap: CGFloat = 10
    static let iconGap: CGFloat = 7

    public init(parts: [PillPart], iconOnly: Bool = false) {
        self.iconOnly = iconOnly
        for part in parts where !(part.icon.isEmpty && part.label.isEmpty) {
            if part.under, !iconOnly, let last = slots.indices.last, slots[last].under == nil,
               !slots[last].part.label.isEmpty {
                slots[last].under = part
            } else {
                slots.append((part, nil))
            }
        }
    }

    // Two lines fit in the pill only in smaller type.
    static func stacked(_ font: NSFont) -> (top: NSFont, bottom: NSFont) {
        (NSFontManager.shared.convert(font, toSize: 11), NSFontManager.shared.convert(font, toSize: 9))
    }

    // Icons and labels are sized by their ink, so a side bearing cannot change the gap to the next pill.
    func sizes(_ iconFont: NSFont, _ labelFont: NSFont) -> [(icon: CGFloat, gap: CGFloat, label: CGFloat)] {
        let small = Self.stacked(labelFont)
        return slots.map { slot in
            let hasIcon = !slot.part.icon.isEmpty
            let hasLabel = !slot.part.label.isEmpty && !(hasIcon && iconOnly)
            let label = !hasLabel ? 0 : slot.under.map {
                max(inkBox(slot.part.label, small.top).width, inkBox($0.label, small.bottom).width)
            } ?? inkBox(slot.part.label, labelFont).width
            return (hasIcon ? inkBox(slot.part.icon, iconFont).width : 0, hasIcon && hasLabel ? Self.iconGap : 0, label)
        }
    }

    public func width(iconFont: NSFont, labelFont: NSFont) -> CGFloat {
        guard !slots.isEmpty else { return 0 }
        return Self.pad * 2 + Self.partGap * CGFloat(slots.count - 1)
            + sizes(iconFont, labelFont).reduce(0) { $0 + $1.icon + $1.gap + $1.label }
    }

    // Draw the icons and labels, and return the box of each slot's label, nil for a slot with no label.
    // `skip` leaves one label undrawn, for a Ticker to draw.
    @discardableResult
    public func draw(in pill: NSRect, iconFont: NSFont, labelFont: NSFont, color: NSColor, skip: Int? = nil) -> [NSRect?] {
        let small = Self.stacked(labelFont)
        var x = pill.minX + Self.pad
        var boxes: [NSRect?] = []
        for (i, (slot, size)) in zip(slots, sizes(iconFont, labelFont)).enumerated() {
            let part = slot.part
            if size.icon > 0 {
                drawIcon(part.icon, iconFont, part.iconColor ?? color,
                         centeredIn: NSRect(x: x, y: pill.minY, width: size.icon, height: pill.height))
            }
            let left = x + size.icon + size.gap
            if size.label > 0 {
                boxes.append(NSRect(x: left, y: pill.minY, width: size.label, height: pill.height))
                // a tabular digit such as "1" has empty space on each side
                if let under = slot.under {
                    drawText(part.label, small.top, part.labelColor ?? color,
                             leftAt: left - inkBox(part.label, small.top).minX, midY: pill.midY + 5)
                    drawText(under.label, small.bottom, under.labelColor ?? color,
                             leftAt: left - inkBox(under.label, small.bottom).minX, midY: pill.midY - 6)
                } else if i != skip {
                    drawText(part.label, labelFont, part.labelColor ?? color,
                             leftAt: left - inkBox(part.label, labelFont).minX, midY: pill.midY)
                }
            } else {
                boxes.append(nil)
            }
            x += size.icon + size.gap + size.label + Self.partGap
        }
        return boxes
    }
}
