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
