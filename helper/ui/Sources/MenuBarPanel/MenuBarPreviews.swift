#if DEBUG
import SwiftUI

// Sample menu bars for the previews. The icons come from this Mac, and an
// app it does not have gets the empty icon.
extension MenuBarReport {
    static func item(_ id: Int, _ title: String, _ path: String, hidden: Bool = false) -> Item {
        let icon = FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
        return Item(id: id, title: title, app: title, icon: icon, hidden: hidden)
    }

    static let busy = MenuBarReport(items: [
        item(0, "1Password", "/Applications/1Password.app"),
        item(1, "CleanShot X", "/Applications/CleanShot X.app"),
        item(2, "Elgato Camera Hub", "/Applications/Elgato Camera Hub.app"),
        item(3, "Karabiner-Elements", "/Applications/Karabiner-Elements.app"),
        item(4, "Microsoft Teams", "/Applications/Microsoft Teams.app"),
        item(5, "OneDrive · Personal", "/Applications/OneDrive.app"),
        item(6, "OneDrive · TinaCMS", "/Applications/OneDrive.app"),
        item(7, "OrbStack", "/Applications/OrbStack.app", hidden: true),
        item(8, "Home Assistant", "/Applications/Home Assistant.app", hidden: true),
        item(9, "DisplayLink Manager", "/Applications/DisplayLink Manager.app", hidden: true),
    ])

    static let few = MenuBarReport(items: [
        item(0, "1Password", "/Applications/1Password.app"),
        item(1, "Ghostty", "/Applications/Ghostty.app"),
    ])

    static let scanning = MenuBarReport(items: nil)
    static let none = MenuBarReport(items: [])
    static let noAccess = MenuBarReport(items: nil, access: false)
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

#Preview("Grid") { Desk { GridMenuBarPanel(report: .busy) } }
#Preview("List") { Desk { ListMenuBarPanel(report: .busy) } }
#Preview("Dock") { Desk { DockMenuBarPanel(report: .busy) } }

#Preview("Grid: every state") {
    Desk {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow { GridMenuBarPanel(report: .few); GridMenuBarPanel(report: .scanning) }
            GridRow { GridMenuBarPanel(report: .none); GridMenuBarPanel(report: .noAccess) }
        }
    }
}

#Preview("List: every state") {
    Desk {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow { ListMenuBarPanel(report: .few); ListMenuBarPanel(report: .scanning) }
            GridRow { ListMenuBarPanel(report: .none); ListMenuBarPanel(report: .noAccess) }
        }
    }
}

#Preview("Dock: every state") {
    Desk {
        Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow { DockMenuBarPanel(report: .few); DockMenuBarPanel(report: .scanning) }
            GridRow { DockMenuBarPanel(report: .none); DockMenuBarPanel(report: .noAccess) }
        }
    }
}

#Preview("Grid, dark") { Desk { GridMenuBarPanel(report: .busy) }.preferredColorScheme(.dark) }
#endif
