#if DEBUG
import SwiftUI

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

private struct Desk<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .background(LinearGradient(colors: [.teal, .blue, .indigo],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

#Preview("One theme") { Desk { ThemePanel(report: .single) } }
#Preview("Day and night, at night") { Desk { ThemePanel(report: .paired) } }
#Preview("No theme, no wallpapers") { Desk { ThemePanel(report: .bare) } }
#Preview("Dark") { Desk { ThemePanel(report: .paired) }.preferredColorScheme(.dark) }

#Preview("Every desktop") {
    Desk {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow { ForEach(ThemeReport.single.themes.prefix(3)) { ThemeMockup(theme: $0).frame(width: 360) } }
            GridRow { ForEach(ThemeReport.single.themes.dropFirst(3)) { ThemeMockup(theme: $0).frame(width: 360) } }
        }
    }
}
#endif
