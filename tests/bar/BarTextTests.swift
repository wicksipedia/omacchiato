import Testing
import AppKit
@testable import BarPills

@Suite struct BarTextTests {
    @Test("a colour emoji gets a halo; a Nerd Font glyph or a letter, which take the theme colour, do not")
    func colourEmoji() {
        #expect(isColorEmoji("🌙"))
        #expect(isColorEmoji("☀️"))   // U+2600 with the emoji variation selector
        #expect(isColorEmoji("⛅️"))
        #expect(!isColorEmoji("\u{F036D}"))
        #expect(!isColorEmoji("☀"))    // with no selector it draws as text
        #expect(!isColorEmoji("A"))
        #expect(!isColorEmoji(""))
    }

    @Test("a halo is drawn once into a small image and reused, not drawn into the bar")
    func haloCached() {
        let font = NSFont.systemFont(ofSize: 14)
        let first = haloImage("🌙", font, .black)
        #expect(haloImage("🌙", font, .black) === first)
        #expect(first.size.width < 40 && first.size.height < 40)
        #expect(haloImage("🌙", font, .white) !== first)
    }
}

