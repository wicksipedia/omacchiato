import AppKit

// The status pill: an open ring for the Mac battery, a wi-fi glyph in the
// ring, and four dots that close the ring for the wi-fi signal. The bar
// builds this file into its own module with swiftc.
public struct StatusGauge: Equatable {
    public var battery: Double      // 0...1
    public var charging: Bool
    public var wifi: Int?           // nil: wi-fi is off. 0: not joined. 1...4: lit dots

    public init(battery: Double, charging: Bool = false, wifi: Int? = 4) {
        self.battery = battery
        self.charging = charging
        self.wifi = wifi
    }

    public var batteryLow: Bool { battery <= 0.2 && !charging }

    // The ring runs clockwise from its lower-left end over the top.
    static let ringStart: CGFloat = 220
    static let ringSpan: CGFloat = 260

    public var ringEnd: CGFloat { Self.ringStart - Self.ringSpan * CGFloat(min(1, max(0, battery))) }

    public struct Colors {
        public var ink: NSColor
        public var low: NSColor
        public var charging: NSColor
        public init(ink: NSColor, low: NSColor = .systemRed, charging: NSColor = .systemGreen) {
            self.ink = ink
            self.low = low
            self.charging = charging
        }
    }

    // Draw into a square. The geometry is in units of the side, y up.
    public func draw(in rect: NSRect, colors: Colors) {
        let side = min(rect.width, rect.height)
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.midX + (x - 0.5) * side,
                    y: rect.midY + (flipped ? 0.5 - y : y - 0.5) * side)
        }
        // A flipped context mirrors the angles, so arcs go the other way.
        func arc(_ c: NSPoint, _ r: CGFloat, _ from: CGFloat, _ to: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.appendArc(withCenter: c, radius: r * side,
                           startAngle: flipped ? -from : from, endAngle: flipped ? -to : to,
                           clockwise: flipped ? (from < to) : (from > to))
            return path
        }
        let dim = colors.ink.withAlphaComponent(0.3)
        let stroke: CGFloat = 0.09 * side

        let centre = p(0.5, 0.5)
        let radius: CGFloat = 0.4
        func ring(_ to: CGFloat, _ color: NSColor) {
            let path = arc(centre, radius, Self.ringStart, to)
            path.lineWidth = stroke
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()
        }
        ring(Self.ringStart - Self.ringSpan, dim)
        if battery > 0 {
            ring(ringEnd, charging ? colors.charging : (batteryLow ? colors.low : colors.ink))
        }

        let base = p(0.5, 0.33)
        let joined = (wifi ?? 0) > 0
        let wedge = arc(base, 0.11, 45, 135)
        wedge.line(to: base)
        wedge.close()
        (joined ? colors.ink : dim).setFill()
        wedge.fill()
        for r in [CGFloat(0.21), 0.325] {
            let path = arc(base, r, 45, 135)
            path.lineWidth = stroke * 0.8
            path.lineCapStyle = .round
            (joined ? colors.ink : dim).setStroke()
            path.stroke()
        }
        if wifi == nil {
            let slash = NSBezierPath()
            slash.move(to: p(0.34, 0.34))
            slash.line(to: p(0.66, 0.66))
            slash.lineWidth = stroke * 0.8
            slash.lineCapStyle = .round
            colors.ink.setStroke()
            slash.stroke()
        }

        for (i, angle) in [CGFloat(240), 260, 280, 300].enumerated() {
            let a = (flipped ? -angle : angle) * .pi / 180
            let c = NSPoint(x: centre.x + cos(a) * radius * side, y: centre.y + sin(a) * radius * side)
            let r = stroke / 2
            (i < (wifi ?? 0) ? colors.ink : dim).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }
    }
}

// Signal strength to lit dots. 0 means not joined.
public func wifiLevel(rssi: Int) -> Int {
    if rssi == 0 { return 0 }
    if rssi >= -55 { return 4 }
    if rssi >= -65 { return 3 }
    if rssi >= -75 { return 2 }
    return 1
}

#if DEBUG
import SwiftUI

public final class StatusGaugeView: NSView {
    var gauge: StatusGauge
    var ink: NSColor

    public init(_ gauge: StatusGauge, side: CGFloat = 18, ink: NSColor = .labelColor) {
        self.gauge = gauge
        self.ink = ink
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        widthAnchor.constraint(equalToConstant: side).isActive = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirtyRect: NSRect) {
        gauge.draw(in: bounds, colors: .init(ink: ink))
    }
}

private let states: [(String, StatusGauge)] = [
    ("full", StatusGauge(battery: 1)),
    ("half", StatusGauge(battery: 0.5, wifi: 3)),
    ("low", StatusGauge(battery: 0.15, wifi: 1)),
    ("charging", StatusGauge(battery: 0.4, charging: true, wifi: 2)),
    ("not joined", StatusGauge(battery: 0.8, wifi: 0)),
    ("wi-fi off", StatusGauge(battery: 0.7, wifi: nil)),
]

private func grid(side: CGFloat) -> NSView {
    let rows = [NSAppearance.Name.aqua, .darkAqua].map { name -> NSView in
        let row = NSStackView(views: states.map { label, gauge in
            let cell = NSStackView(views: [StatusGaugeView(gauge, side: side),
                                           NSTextField(labelWithString: label)])
            cell.orientation = .vertical
            return cell
        })
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.appearance = NSAppearance(named: name)
        row.wantsLayer = true
        row.layer?.backgroundColor = name == .aqua ? NSColor.white.cgColor : NSColor.black.cgColor
        return row
    }
    let stack = NSStackView(views: rows)
    stack.orientation = .vertical
    stack.spacing = 0
    return stack
}

#Preview("bar size") { grid(side: 18) }
#Preview("large") { grid(side: 96) }
#endif
