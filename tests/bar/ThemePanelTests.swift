import Foundation
import Testing
@testable import ThemePanel

@Suite struct ThemePanelTests {
    @Test("theme.conf holds one theme for the whole day, or a day and a night theme")
    func choice() {
        #expect(ThemeReport.choice("gruvbox")! == ("gruvbox", "gruvbox"))
        #expect(ThemeReport.choice("light:catppuccin-latte,dark:tokyo-night")! == ("catppuccin-latte", "tokyo-night"))
        #expect(ThemeReport.choice(" dark:tokyo-night ")! == ("tokyo-night", "tokyo-night"))
        #expect(ThemeReport.choice("") == nil)
    }

    @Test("Apply writes one name when both halves hold the same theme")
    func spec() {
        #expect(ThemeReport.spec(light: "gruvbox", dark: "gruvbox") == "gruvbox")
        #expect(ThemeReport.spec(light: "catppuccin-latte", dark: "tokyo-night") == "light:catppuccin-latte,dark:tokyo-night")
    }

    @Test("a theme reads its colours from the files theme-set reads")
    func load() throws {
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../themes").standardized
        let report = ThemeReport(directory: themes, spec: "tokyo-night")
        let theme = try #require(report.theme("tokyo-night"))
        #expect(theme.title == "Tokyo Night")
        #expect(theme.dark)
        #expect(theme.terminal.palette.count == 16)
        #expect(theme.border.glow)
        #expect(!(try #require(report.theme("catppuccin-latte"))).dark)
    }
}
