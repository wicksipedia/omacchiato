#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

extension PanelRow {
    static func make(_ text: String, detail: String = "", icon: String = "", hero: Bool = false, dim: Bool = false,
                     highlight: Bool = false, separator: Bool = false, slider: Double? = nil, bar: Double? = nil,
                     marker: Double? = nil, tint: Color? = nil, open: Bool? = nil, submenu: Bool = false,
                     back: Bool = false, action: Bool = true) -> PanelRow {
        var row = PanelRow()
        row.text = text
        row.detail = detail
        row.icon = icon
        row.hero = hero
        row.dim = dim
        row.highlight = highlight
        row.separator = separator
        row.slider = slider
        row.bar = bar
        row.marker = marker
        row.tint = tint
        row.open = open
        row.submenu = submenu
        row.back = back
        row.action = action && !hero ? {} : nil
        return row
    }

    static let rule = make("", separator: true)
}

private let update: [PanelRow] = [
    .make("Omacchiato Update", hero: true),
    .make("Show the menu bar apps popup as a panel", dim: true, action: false),
    .make("Show the pull request popup as a panel", dim: true, action: false),
    .make("Give each usage ring its own colour", dim: true, action: false),
    .rule,
    .make("Update Now", icon: "\u{f01b}"),
]

private let keepAwake: [PanelRow] = [
    .make("Keeping Awake", hero: true),
    .make("Vorssaint", detail: "1h 45m", action: false),
    .make("caffeinate", detail: "12m", action: false),
]

private let volume: [PanelRow] = [
    .make("64%", icon: "\u{f057e}", slider: 0.64),
    .rule,
    .make("MacBook Pro Speakers", highlight: true),
    .make("AirPods Pro"),
    .make("Studio Display Speakers"),
    .rule,
    .make("Sound Settings…", dim: true),
]

private let airpods: [PanelRow] = [
    .make("AirPods Pro", hero: true),
    .make("Left", detail: "80%", bar: 0.8, tint: .green, action: false),
    .make("Right", detail: "15%", bar: 0.15, tint: .red, action: false),
    .make("Case", detail: "100%", bar: 1, tint: .green, action: false),
    .rule,
    .make("Noise Control", open: true),
    .make("Transparency", icon: "\u{f0470}", highlight: true),
    .make("Noise Cancellation", icon: "\u{f07f4}"),
]

private let appMenu: [PanelRow] = [
    .make("File", highlight: true, back: true),
    .make("New Window", detail: "⌘N"),
    .make("New Tab", detail: "⌘T"),
    .make("Open Recent", submenu: true),
    .rule,
    .make("Close Window", detail: "⇧⌘W"),
    .make("Close All Windows and Quit the App With a Very Long Name", detail: "⌥⇧⌘W"),
]

private let menus: [PanelRow] = ["Ghostty", "File", "Edit", "View", "Window", "Help"].map { .make($0, submenu: true) }

private let file: [PanelRow] = [
    .make("New Window", detail: "⌘N"),
    .make("New Tab", detail: "⌘T"),
    .make("Open Recent", submenu: true),
    .rule,
    .make("Close Window", detail: "⇧⌘W"),
]

private let recent: [PanelRow] = [
    .make("omacchiato"),
    .make("wicksipedia.com"),
    .rule,
    .make("Clear Menu"),
]

#Preview("Update") { Desk { RowsPanel(rows: update) } }
#Preview("Keep Awake") { Desk { RowsPanel(rows: keepAwake) } }
#Preview("Volume") { Desk { RowsPanel(rows: volume) } }
#Preview("AirPods") { Desk { RowsPanel(rows: airpods) } }
#Preview("App Menu, keys") { Desk { RowsPanel(rows: appMenu, selected: 2) } }
#Preview("Submenus") {
    Desk { CascadePanel(columns: [menus, file, recent], open: [1, 2, nil], selected: 1) }
}
#Preview("Long, scrolls") { Desk { RowsPanel(rows: Array(repeating: appMenu, count: 8).flatMap { $0 }, maxHeight: 400) } }
#Preview("Volume, dark") { Desk { RowsPanel(rows: volume) }.preferredColorScheme(.dark) }
#endif
