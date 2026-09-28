import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Sample menu bars for the Xcode previews and the settings window. The icons come from this Mac, and an
// app it does not have gets the empty icon.
extension MenuBarReport {
    public static func item(_ id: Int, _ title: String, _ path: String, hidden: Bool = false) -> Item {
        let icon = FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
        return Item(id: id, title: title, app: title, icon: icon, hidden: hidden)
    }

    public static let busy = MenuBarReport(items: [
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

    public static let few = MenuBarReport(items: [
        item(0, "1Password", "/Applications/1Password.app"),
        item(1, "Ghostty", "/Applications/Ghostty.app"),
    ])

    public static let scanning = MenuBarReport(items: nil)
    public static let none = MenuBarReport(items: [])
    public static let noAccess = MenuBarReport(items: nil, access: false)
}
