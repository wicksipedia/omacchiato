import SwiftUI

// The moving sky behind the weather panel: sun rays, stars, clouds, rain,
// snow, fog and lightning. Reduce motion stops the clock, so the sky holds
// still.
struct SkyEffects: View {
    var sky: Sky
    var night: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 30 frames a second is smooth enough for weather, at half the cost.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            Canvas { g, size in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                draw(&g, size, t)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        switch sky {
        case .clear:
            night ? stars(&g, size, t) : sun(&g, size, t)
        case .partly:
            night ? stars(&g, size, t) : sun(&g, size, t)
            clouds(&g, size, t, count: 3, opacity: 0.22)
        case .cloudy:
            clouds(&g, size, t, count: 7, opacity: 0.26, blur: 10)
        case .fog:
            fog(&g, size, t)
        case .drizzle:
            clouds(&g, size, t, count: 5, opacity: 0.18)
            rain(&g, size, t, drops: 45, speed: 500)
        case .rain:
            clouds(&g, size, t, count: 5, opacity: 0.18)
            rain(&g, size, t, drops: 100, speed: 700)
        case .heavy:
            clouds(&g, size, t, count: 6, opacity: 0.2)
            rain(&g, size, t, drops: 180, speed: 900)
        case .storm:
            clouds(&g, size, t, count: 6, opacity: 0.16)
            rain(&g, size, t, drops: 160, speed: 900)
            lightning(&g, size, t)
        case .snow:
            clouds(&g, size, t, count: 4, opacity: 0.18)
            snow(&g, size, t)
        }
    }

    func sun(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let centre = CGPoint(x: size.width * 0.18, y: size.height * 0.02)
        let glow = 170 + 12 * sin(t * 0.8)
        g.fill(Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
               with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .yellow.opacity(0.18), .clear]),
                                     center: centre, startRadius: 0, endRadius: glow))
        var rays = g
        rays.translateBy(x: centre.x, y: centre.y)
        rays.rotate(by: .radians(t * 0.05))
        rays.addFilter(.blur(radius: 6))
        for i in 0..<12 {
            let length = size.height * (0.55 + 0.2 * sin(t * 0.6 + Double(i) * 1.7))
            let spread = 0.05
            let a = Double(i) / 12 * 2 * .pi
            var ray = Path()
            ray.move(to: .zero)
            ray.addLine(to: CGPoint(x: cos(a - spread) * length, y: sin(a - spread) * length))
            ray.addLine(to: CGPoint(x: cos(a + spread) * length, y: sin(a + spread) * length))
            ray.closeSubpath()
            rays.fill(ray, with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .clear]),
                                                 startPoint: .zero,
                                                 endPoint: CGPoint(x: cos(a) * length, y: sin(a) * length)))
        }
    }

    func stars(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<70 {
            let x = noise(i, 1) * size.width
            let y = noise(i, 2) * size.height * 0.6
            let r = 0.6 + noise(i, 3) * 1.2
            let twinkle = 0.25 + 0.75 * abs(sin(t * (0.4 + noise(i, 4)) + noise(i, 5) * 6))
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(twinkle)))
        }
    }

    func clouds(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double, count: Int, opacity: Double,
                blur: Double = 18) {
        var layer = g
        layer.addFilter(.blur(radius: blur))
        for i in 0..<count {
            let width = 160 + noise(i, 6) * 140
            let travel = size.width + width * 2
            let x = (noise(i, 7) * travel + t * (6 + noise(i, 8) * 10)).truncatingRemainder(dividingBy: travel) - width
            let y = size.height * (0.02 + noise(i, 9) * 0.3)
            for (dx, dy, scale) in [(0.0, 0.0, 1.0), (0.3, -0.25, 0.7), (0.6, 0.05, 0.8)] {
                let w = width * 0.6 * scale
                layer.fill(Path(ellipseIn: CGRect(x: x + width * dx, y: y + width * dy * 0.4, width: w, height: w * 0.55)),
                           with: .color(.white.opacity(opacity)))
            }
        }
    }

    func rain(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double, drops: Int, speed: Double) {
        let slant = 0.12
        for i in 0..<drops {
            let length = 12 + noise(i, 10) * 14
            let fall = speed * (0.8 + noise(i, 11) * 0.4)
            let span = size.height + length
            let y = (noise(i, 12) * span + t * fall).truncatingRemainder(dividingBy: span) - length
            let x = noise(i, 13) * (size.width + span * slant) - y * slant
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - length * slant, y: y + length))
            g.stroke(drop, with: .color(.white.opacity(0.18 + noise(i, 14) * 0.22)), lineWidth: 1)
        }
    }

    func snow(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<80 {
            let r = 1.2 + noise(i, 15) * 2.3
            let span = size.height + r * 2
            let y = (noise(i, 16) * span + t * (20 + r * 12)).truncatingRemainder(dividingBy: span) - r
            let x = noise(i, 17) * size.width + sin(t * 0.7 + noise(i, 18) * 6) * 14
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(0.5 + noise(i, 19) * 0.4)))
        }
    }

    // Fog has no cloud shapes: thick bands of mist at every height drift
    // in turn left and right, over a haze that rises from the bottom.
    func fog(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.3)]),
                                     startPoint: CGPoint(x: 0, y: size.height * 0.3),
                                     endPoint: CGPoint(x: 0, y: size.height)))
        var layer = g
        layer.addFilter(.blur(radius: 22))
        for i in 0..<7 {
            let width = size.width * (0.9 + noise(i, 22) * 0.6)
            let travel = size.width + width
            let direction = i % 2 == 0 ? 1.0 : -1.0
            let shift = (noise(i, 23) * travel + direction * t * (5 + noise(i, 24) * 6))
            let x = (shift.truncatingRemainder(dividingBy: travel) + travel)
                .truncatingRemainder(dividingBy: travel) - width
            let y = size.height * (Double(i) / 7 + noise(i, 25) * 0.06)
            layer.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: 44 + noise(i, 26) * 30),
                            cornerRadius: 30),
                       with: .color(.white.opacity(0.22)))
        }
    }

    // A flash about every 7 s: one strike, a flicker, and a bolt from the top.
    func lightning(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let period = 7.0
        let cycle = Int(t / period)
        let phase = t.truncatingRemainder(dividingBy: period)
        let flash = phase < 0.1 ? 1 - phase / 0.1 : (phase > 0.18 && phase < 0.26 ? 0.6 : 0)
        guard flash > 0 else { return }
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.35 * flash)))
        var bolt = Path()
        var point = CGPoint(x: size.width * (0.2 + noise(cycle, 20) * 0.6), y: 0)
        bolt.move(to: point)
        for step in 0..<8 {
            point.x += (noise(cycle * 8 + step, 21) - 0.5) * 50
            point.y += size.height * 0.05
            bolt.addLine(to: point)
        }
        var glow = g
        glow.addFilter(.blur(radius: 4))
        glow.stroke(bolt, with: .color(.white.opacity(flash)), lineWidth: 4)
        g.stroke(bolt, with: .color(.white.opacity(flash)), lineWidth: 1.5)
    }
}

// The same number between 0 and 1 for the same particle every frame, so a
// drop keeps its lane and speed.
func noise(_ i: Int, _ salt: Int) -> Double {
    var h = UInt64(truncatingIfNeeded: i &* 374_761_393 &+ salt &* 668_265_263)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65535
}
