import CoreGraphics
import Testing
@testable import omacchiato_bar

struct FullscreenTests {
    let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)

    @Test("a fullscreen window below the notch covers the display")
    func fullscreen() {
        #expect(coversDisplay(CGRect(x: 0, y: 38, width: 1800, height: 1131), display, inset: 38))
    }

    @Test("a tiled window with side gaps does not")
    func tiled() {
        #expect(!coversDisplay(CGRect(x: 4, y: 38, width: 1792, height: 1129), display, inset: 38))
    }

    @Test("a full-size window that Defi parks one point onto the display does not")
    func parked() {
        #expect(!coversDisplay(CGRect(x: 1799, y: 38, width: 1800, height: 1131), display, inset: 38))
        #expect(!coversDisplay(CGRect(x: -1799, y: 38, width: 1800, height: 1131), display, inset: 38))
    }

    @Test("a window on another display does not")
    func elsewhere() {
        #expect(!coversDisplay(CGRect(x: 1800, y: 0, width: 1800, height: 1169), display, inset: 38))
    }
}
