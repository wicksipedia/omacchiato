import Testing
import BarPills

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
}
