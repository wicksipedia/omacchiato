import SwiftUI

// What the menu bar apps popup shows: the status icons of the apps that
// run, read over Accessibility. The notch hides an icon that does not fit,
// and a click on a hidden icon opens its app instead.
public struct MenuBarReport {
    public struct Item: Identifiable {
        public var id: Int                  // the bar's index of the scanned icon
        public var title: String            // the app's name, and the label when the app has more than one icon
        public var app: String
        public var icon: NSImage?
        public var hidden: Bool

        public init(id: Int, title: String, app: String, icon: NSImage? = nil, hidden: Bool = false) {
            self.id = id
            self.title = title
            self.app = app
            self.icon = icon
            self.hidden = hidden
        }
    }

    public var items: [Item]?               // nil until the first scan ends
    public var access: Bool                 // the Accessibility grant

    public init(items: [Item]?, access: Bool = true) {
        self.items = items
        self.access = access
    }

    public var hidden: [Item] { (items ?? []).filter(\.hidden) }
}

public struct MenuBarActions {
    public var click: (Int) -> Void = { _ in }
    public var grantAccess: () -> Void = {}

    public init() {}
}
