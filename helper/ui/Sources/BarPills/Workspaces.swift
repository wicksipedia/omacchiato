import AppKit

// Workspace chips: one bracket per display. Each chip shows up to three
// fanned app icons, its own glyph or image, or a digit while empty.
public struct WorkspaceChip {
    public enum Face {
        case digit(String)
        case glyph(String)
        case image(NSImage)
        case hand([NSImage], ring: Int?)    // ring: the card of the focused app
    }

    public var face: Face
    public var focused: Bool                // keyboard focus: the accent colour
    public var shown: Bool                  // the workspace this display shows: a dot under it

    public init(face: Face, focused: Bool = false, shown: Bool = false) {
        self.face = face
        self.focused = focused
        self.shown = shown
    }

    public var width: CGFloat {
        if case .hand(let cards, _) = face { return chipWidth(cards: cards.count) }
        return chipWidth(cards: 1)
    }
}

public let chipBox: CGFloat = 20
public let chipPad: CGFloat = 2
public let handStep: CGFloat = 12

// A workspace chip with a hand of app icons grows by handStep per extra card.
public func chipWidth(cards: Int) -> CGFloat {
    chipBox + chipPad * 2 + handStep * CGFloat(min(max(cards, 1), 3) - 1)
}

// The first three distinct apps: the cards a workspace chip fans out.
public func handOf(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return Array(names.filter { seen.insert($0).inserted }.prefix(3))
}

// Draws the chips in one bracket, starting at x.
// Returns each chip's slot: full bar height, for clicks.
@discardableResult
public func drawWorkspaces(_ chips: [WorkspaceChip], x: CGFloat, barHeight: CGFloat, pillHeight: CGFloat,
                           radius: CGFloat, digitFont: NSFont, glyphFont: NSFont, colors: PillColors) -> [NSRect] {
    let bracket = NSRect(x: x, y: (barHeight - pillHeight) / 2,
                         width: chips.reduce(0) { $0 + $1.width }, height: pillHeight)
    colors.background.setFill()
    NSBezierPath(roundedRect: bracket, xRadius: radius, yRadius: radius).fill()
    var slots: [NSRect] = []
    var left = x
    for chip in chips {
        let slot = NSRect(x: left, y: 0, width: chip.width, height: barHeight)
        let box = slot.insetBy(dx: chipPad, dy: 0)
        if chip.shown {
            colors.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: box.midX - 2, y: 2, width: 4, height: 4)).fill()
        }
        // Accent marks keyboard focus. The dot alone marks what this display shows.
        let tint = chip.focused ? colors.accent : colors.muted
        switch chip.face {
        case .digit(let digit): drawText(digit, digitFont, tint, centeredIn: box)
        case .glyph(let glyph): drawIcon(glyph, glyphFont, tint, centeredIn: box)
        case .image(let icon): icon.draw(in: NSRect(x: box.midX - 9, y: box.midY - 9, width: 18, height: 18))
        case .hand(let cards, let ring): drawHand(cards, ring: ring, centeredIn: box, ringColor: colors.accent)
        }
        slots.append(slot)
        left += chip.width
    }
    return slots
}

// Fans up to three icons like a hand of cards.
// The first sits in front, tilted left. The rest sit behind it, to the right.
func drawHand(_ icons: [NSImage], ring: Int?, centeredIn box: NSRect, ringColor: NSColor) {
    let card = NSRect(x: box.midX - 9, y: box.midY - 9, width: 18, height: 18)
    guard icons.count > 1 else {
        icons.first?.draw(in: card)
        if ring == 0 { drawRing(card, ringColor) }
        return
    }
    // chipWidth widens the chip by handStep per extra card, so the fan keeps full-size cards.
    let fan: [(shift: CGFloat, tilt: CGFloat)] = icons.count == 2
        ? [(-handStep / 2, 8), (handStep / 2, -8)]
        : [(-handStep, 10), (0, 0), (handStep, -10)]

    // The focused app's card pokes up out of the hand.
    func posed(_ i: Int, _ paint: () -> Void) {
        let pose = fan[i]
        NSGraphicsContext.saveGraphicsState()
        // tilt about the card's own bottom centre, then slide it by the shift
        let turn = NSAffineTransform()
        turn.translateX(by: card.midX + pose.shift, yBy: card.minY + (i == ring ? 3 : 0))
        turn.rotate(byDegrees: pose.tilt)
        turn.translateX(by: -card.midX, yBy: -card.minY)
        turn.concat()
        paint()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Draws the focused card last, on top with its ring, so the ring never crosses the card in front.
    for (i, icon) in icons.prefix(fan.count).enumerated().reversed() where i != ring { posed(i) { icon.draw(in: card) } }
    if let ring, ring < min(icons.count, fan.count) {
        posed(ring) {
            icons[ring].draw(in: card)
            drawRing(card, ringColor)
        }
    }
}

// Ring hugs the icon art, not the full box.
// Icon art usually sits within a margin of about a tenth of the box.
func drawRing(_ card: NSRect, _ color: NSColor) {
    let art = card.insetBy(dx: card.width * 0.06, dy: card.width * 0.06)
    let path = NSBezierPath(roundedRect: art, xRadius: art.width * 0.26, yRadius: art.width * 0.26)
    path.lineWidth = 1.2
    color.withAlphaComponent(0.8).setStroke()
    path.stroke()
}
