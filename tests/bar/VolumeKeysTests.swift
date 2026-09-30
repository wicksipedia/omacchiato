import CoreGraphics
import Testing
@testable import omacchiato_bar

@Suite struct VolumeKeysTests {
    @Test("a volume key steps in sixteenths and stops at the ends")
    func steps() {
        #expect(nextVolume(50, up: true, fine: false) == 56)
        #expect(nextVolume(56, up: false, fine: false) == 50)
        #expect(nextVolume(100, up: true, fine: false) == 100)
        #expect(nextVolume(0, up: false, fine: false) == 0)
        #expect(nextVolume(3, up: false, fine: false) == 0)
    }

    @Test("rounding to whole percents does not lose a step")
    func noDrift() {
        var v = 0
        for _ in 0..<16 { v = nextVolume(v, up: true, fine: false) }
        #expect(v == 100)
        for _ in 0..<16 { v = nextVolume(v, up: false, fine: false) }
        #expect(v == 0)
    }

    @Test("Shift+Option steps in sixty-fourths")
    func fine() {
        #expect(nextVolume(50, up: true, fine: true) == 52)
    }
}

@Suite struct VolumePillTests {
    @Test("a mode other than muted draws the pill again, so a change of mode shows at once")
    func modes() {
        #expect(volumePill(percent: 44, muted: false, mode: "muted").drawing == false)
        #expect(volumePill(percent: 44, muted: false, mode: nil) == (true, "󰖀", "44%", false))
        #expect(volumePill(percent: 44, muted: false, mode: "icon").drawing)
        #expect(volumePill(percent: 44, muted: true, mode: "muted") == (true, "󰝟", "", true))
    }
}

@Suite struct HUDPositionTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 260, height: 50)

    @Test("the HUD sits top right under the bar by default, or where hud_position puts it")
    func positions() {
        #expect(hudOrigin(screen: screen, size: size, position: nil, barHeight: 34) == CGPoint(x: 730, y: 708))
        #expect(hudOrigin(screen: screen, size: size, position: "top-left", barHeight: 34) == CGPoint(x: 10, y: 708))
        #expect(hudOrigin(screen: screen, size: size, position: "top-center", barHeight: 34) == CGPoint(x: 370, y: 708))
        #expect(hudOrigin(screen: screen, size: size, position: "center", barHeight: 34) == CGPoint(x: 370, y: 375))
        #expect(hudOrigin(screen: screen, size: size, position: "bottom-center", barHeight: 34) == CGPoint(x: 370, y: 80))
        #expect(hudOrigin(screen: screen, size: size, position: "nonsense", barHeight: 34) == CGPoint(x: 730, y: 708))
    }
}
