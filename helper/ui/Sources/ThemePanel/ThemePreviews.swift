#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The previews read the real themes in the repository, wallpapers included.
extension ThemeReport {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../../../../themes").standardized

    static let single = ThemeReport(directory: repo, spec: "catppuccin-latte")
    static let paired = ThemeReport(directory: repo, spec: "light:catppuccin-latte,dark:tokyo-night", darkNow: true)
    // No theme.conf yet, and no wallpapers: the desktop falls back to the theme's own colours.
    static let bare = ThemeReport(themes: single.themes.map { var t = $0; t.wallpaper = nil; return t },
                                  light: nil, dark: nil)
}

#Preview("One theme") { ThemePicker(report: .single).padding(20).frame(width: 520) }
#Preview("Day and night, at night") { ThemePicker(report: .paired).padding(20).frame(width: 520) }
#Preview("No theme, no wallpapers") { ThemePicker(report: .bare).padding(20).frame(width: 520) }
#Preview("Dark") { ThemePicker(report: .paired).padding(20).frame(width: 520).preferredColorScheme(.dark) }

#Preview("Every desktop") {
    Desk {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow { ForEach(ThemeReport.single.themes.prefix(3)) { ThemeMockup(theme: $0).frame(width: 360) } }
            GridRow { ForEach(ThemeReport.single.themes.dropFirst(3)) { ThemeMockup(theme: $0).frame(width: 360) } }
        }
    }
}
#endif
