import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// Three designs of the menu bar apps popup, to compare in the previews.
// Each one shows the same data and offers the same actions.

struct AppIcon: View {
    var item: MenuBarReport.Item
    var size: CGFloat

    var body: some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary).padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
    }
}

// The badge on an icon that macOS hides, because it does not fit next to
// the camera notch.
struct NotchBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.forward.app.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white, .orange)
            .accessibilityLabel("Hidden by the notch. Opens the app.")
    }
}

// The states before a list: no grant, and the first scan.
struct MenuBarGate: View {
    var report: MenuBarReport
    var actions: MenuBarActions

    var body: some View {
        if !report.access {
            VStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").font(.system(size: 26)).foregroundStyle(.blue)
                Text("Allow Accessibility").font(.system(size: 13, weight: .semibold))
                Text("The bar reads the menu bar icons of other apps with Accessibility.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.blue, in: .capsule)
                    .foregroundStyle(.white)
                    .contentShape(.capsule)
                    .onTapGesture(perform: actions.grantAccess)
                    .accessibilityAddTraits(.isButton)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        } else if report.items == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for menu bar apps…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        } else if report.items?.isEmpty == true {
            Text("No menu bar apps running").font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.vertical, 18).frame(maxWidth: .infinity)
        }
    }
}

// "Grid": the icons as Launchpad lays out apps, four to a row.
public struct GridMenuBarPanel: View {
    var report: MenuBarReport
    var actions: MenuBarActions

    public init(report: MenuBarReport, actions: MenuBarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            MenuBarGate(report: report, actions: actions)
            if let items = report.items, !items.isEmpty, report.access {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 6) {
                    ForEach(items) { tile($0) }
                }
                if !report.hidden.isEmpty {
                    HStack(spacing: 5) {
                        NotchBadge()
                        Text("Hidden by the notch. A click opens the app.")
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .statusPanelBackground(width: 320)
    }

    func tile(_ item: MenuBarReport.Item) -> some View {
        HoverRow(action: { actions.click(item.id) }) {
            VStack(spacing: 5) {
                AppIcon(item: item, size: 44)
                    .overlay(alignment: .topTrailing) { if item.hidden { NotchBadge().offset(x: 4, y: -4) } }
                // an app with two icons names each one on a second line
                let parts = item.title.components(separatedBy: " · ")
                VStack(spacing: 0) {
                    Text(parts[0]).font(.system(size: 11))
                    if parts.count > 1 {
                        Text(parts[1...].joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
        }
        .help(item.title)
    }
}

// "List": one row for each icon, by app name.
public struct ListMenuBarPanel: View {
    var report: MenuBarReport
    var actions: MenuBarActions

    public init(report: MenuBarReport, actions: MenuBarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            MenuBarGate(report: report, actions: actions)
            if report.access, let items = report.items, !items.isEmpty {
                VStack(spacing: 0) { ForEach(items) { row($0) } }
            }
        }
        .statusPanelBackground(width: 300)
    }

    func row(_ item: MenuBarReport.Item) -> some View {
        HoverRow(action: { actions.click(item.id) }) {
            HStack(spacing: 10) {
                AppIcon(item: item, size: 22)
                Text(item.title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 4)
                if item.hidden {
                    // macOS hides an icon with no room next to the notch
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .help("Hidden by the notch. A click opens the app.")
                        .accessibilityLabel("Hidden by the notch. Opens the app.")
                }
            }
        }
    }
}

// "Dock": the icons on one shelf, as the Dock holds apps. The name shows
// under the pointer.
public struct DockMenuBarPanel: View {
    var report: MenuBarReport
    var actions: MenuBarActions
    @State private var hovered: Int?

    public init(report: MenuBarReport, actions: MenuBarActions = .init()) {
        self.report = report
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 8) {
            MenuBarGate(report: report, actions: actions)
            if report.access, let items = report.items, !items.isEmpty {
                let name = items.first { $0.id == hovered }?.title ?? " "
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 7), spacing: 8) {
                    ForEach(items) { item in
                        AppIcon(item: item, size: 36)
                            .scaleEffect(hovered == item.id ? 1.2 : 1, anchor: .bottom)
                            .overlay(alignment: .topTrailing) { if item.hidden { NotchBadge().offset(x: 3, y: -3) } }
                            .animation(.snappy(duration: 0.15), value: hovered)
                            .contentShape(.rect)
                            .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
                            .onTapGesture { actions.click(item.id) }
                            .accessibilityElement()
                            .accessibilityLabel(item.title)
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(10)
                .background(.fill.quaternary, in: .rect(cornerRadius: 16))
            }
        }
        .statusPanelBackground(width: 348)
    }
}
