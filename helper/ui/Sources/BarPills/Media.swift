import AppKit

// The music pill: the album art, then the title. The art slot is always
// there, so the title does not move while the art loads. A title wider
// than its box scrolls in a Marquee over the bar.
public struct MediaPill {
    public var title: String
    public var art: NSImage?

    public init(title: String, art: NSImage? = nil) {
        self.title = title
        self.art = art
    }

    public static func artSide(pillHeight: CGFloat) -> CGFloat { pillHeight - 6 }

    // The space around the title: 8 pt makes the gap before the art match the gap before the app name.
    public static func chrome(pillHeight: CGFloat) -> CGFloat { 8 + artSide(pillHeight: pillHeight) + 8 + 10 }

    // The pill's width, and its art and title boxes, from the pill's own origin. maxWidth caps the whole pill.
    public func layout(font: NSFont, maxWidth: CGFloat, pillHeight: CGFloat)
        -> (width: CGFloat, art: NSRect, title: NSRect) {
        let side = Self.artSide(pillHeight: pillHeight)
        let inset = (pillHeight - side) / 2
        let art = NSRect(x: 8, y: inset, width: side, height: side)
        let x = 8 + side + 8
        let cap = max(0, maxWidth - x - 10)
        let w = min(ceil(advance(title, font)), cap)
        return (x + w + 10, art, NSRect(x: x, y: 0, width: w, height: pillHeight))
    }

    // Draw the pill and its art, and return the box the title scrolls in.
    public func draw(in pill: NSRect, font: NSFont, maxWidth: CGFloat, radius: CGFloat,
                     placeholderFont: NSFont, colors: PillColors) -> NSRect {
        let layout = layout(font: font, maxWidth: maxWidth, pillHeight: pill.height)
        colors.background.setFill()
        NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
        let r = layout.art.offsetBy(dx: pill.minX, dy: pill.minY)
        if let art {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).addClip()
            art.draw(in: r)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // placeholder while the art loads, or for a track with no art
            colors.muted.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            drawText("\u{F075A}", placeholderFont, colors.muted, centeredIn: r)
        }
        return layout.title.offsetBy(dx: pill.minX, dy: pill.minY)
    }
}

// Draws the title once into a layer, using the bar's own text routine.
// If the title is wider than its box, it scrolls.
// Core Animation moves the layer in the render server, so the bar redraws nothing while it scrolls.
// Ticker slides a label up to a second line and back, holding each for 4 s.
// It keeps the label's width, so the second line is cut to fit.
public final class Ticker: NSView {
    private let strip = CALayer()
    private var content = ""

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        strip.anchorPoint = .zero
        layer?.addSublayer(strip)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // clicks belong to the bar underneath
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public func hide() {
        isHidden = true
        content = ""
    }

    // slide: the seconds each change of line takes. Zero swaps the lines with no motion.
    public func show(_ label: String, _ text: String, _ tail: String, font: NSFont,
                     colors: (NSColor, NSColor), in box: NSRect, slide: CFTimeInterval = 0.4) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isHidden = false
        frame = box
        let second = fit(text, font, box.width - advance(" " + tail, font)) + " " + tail
        let key = "\(label)|\(second)|\(font)|\(colors)|\(box.size)"
        guard key != content else { return }
        content = key
        // three lines from the top: label, second, label again, so the loop
        // ends where it starts
        let h = box.height
        let size = NSSize(width: box.width, height: h * 3)
        strip.contents = NSImage(size: size, flipped: false) { _ in
            for (index, (line, color)) in [(label, colors.0), (second, colors.1), (label, colors.0)].enumerated() {
                let midY = h * CGFloat(2 - index) + h / 2
                drawLine(line, font, color, baseline: CGPoint(x: 0, y: midY - font.capHeight / 2))
            }
            return true
        }
        strip.contentsScale = window?.backingScaleFactor ?? 2
        strip.frame = NSRect(x: 0, y: -2 * h, width: size.width, height: size.height)
        strip.removeAllAnimations()
        let hold: CFTimeInterval = 4
        let total = 2 * (hold + slide)
        let cycle = CAKeyframeAnimation(keyPath: "transform.translation.y")
        cycle.values = [0, 0, h, h, 2 * h]
        cycle.keyTimes = [0, hold, hold + slide, 2 * hold + slide, total].map { NSNumber(value: $0 / total) }
        if slide == 0 {
            // Reduce motion: swap the lines with no slide. Discrete takes one more key time than values.
            cycle.calculationMode = .discrete
            cycle.values = [0, h]
            cycle.keyTimes = [0, 0.5, 1]
        }
        cycle.duration = total
        cycle.repeatCount = .infinity
        strip.add(cycle, forKey: "tick")
    }
}

public final class Marquee: NSView {
    private let strip = CALayer()
    private var content = ""

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        strip.anchorPoint = .zero
        layer?.addSublayer(strip)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // clicks belong to the bar underneath
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public func hide() {
        isHidden = true
        content = ""
    }

    public func show(_ title: String, font: NSFont, color: NSColor, in box: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isHidden = false
        frame = box
        let fits = advance(title, font) <= box.width + 0.5
        let spacer = "      "
        let text = fits ? title : title + spacer + title
        let key = "\(text)|\(font)|\(color)|\(box.size)"
        guard key != content else { return }
        content = key
        let size = NSSize(width: ceil(advance(text, font)) + 2, height: box.height)
        strip.contents = NSImage(size: size, flipped: false) { rect in
            drawLine(text, font, color, baseline: CGPoint(x: 0, y: rect.midY - font.capHeight / 2))
            return true
        }
        strip.contentsScale = window?.backingScaleFactor ?? 2
        strip.frame = NSRect(origin: .zero, size: size)
        strip.removeAllAnimations()
        guard !fits else { return }
        // hold at the start, then travel one title and gap at 30 pt a second
        let distance = advance(title + spacer, font)
        let hold: CFTimeInterval = 2
        let travel = CFTimeInterval(distance / 30)
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -distance]
        scroll.keyTimes = [0, NSNumber(value: hold / (hold + travel)), 1]
        scroll.duration = hold + travel
        scroll.repeatCount = .infinity
        strip.add(scroll, forKey: "scroll")
    }
}
