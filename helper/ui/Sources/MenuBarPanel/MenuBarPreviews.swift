#if DEBUG
import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

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
