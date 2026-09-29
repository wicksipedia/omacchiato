import ApplicationServices
import AppKit
import CoreAudio
import CoreBluetooth
import CoreLocation
import CoreWLAN
import EventKit
import IOBluetooth
import IOKit.ps
import SystemConfiguration
import UniformTypeIdentifiers
// swiftc builds helper/ui into this module, and SwiftPM builds it as its own.
import SwiftUI
#if canImport(StatusGauge)
import StatusGauge
import PanelDesigns
import ActivityPanel
import AirPodsPanel
import BluetoothPanel
import BarPills
import DisplayPanel
import KeepAwakePanel
import SoundPanel
import StatsPanel
import UpdatesPanel
import AIUsagePanel
import CalendarPanel
import MenuBarPanel
import PRPanel
import RowsPanel
import StatusPanel
import ThemePanel
import WeatherPanel
#endif

// --- popups ----------------------------------------------------------------
// A popup is a SwiftUI view in its own window, so it goes away with the window.

struct PopupRow {
    var icon = ""
    var image: NSImage? // 16pt leading icon — Recent Items entries
    var text = ""
    var detail = "" // right-aligned, dim — menu shortcuts live here
    var subtitle = "" // follows the text, small and quiet: a title's second half
    var separator = false // a thin rule instead of content
    var hero = false // accent, bold — the title row
    var dim = false // the quiet action footer
    var highlight = false // today's week, the active device
    var slider: Double? // 0...1 draws a track instead of text
    var marker: Double? // 0...1 draws a tick across the slider track
    var inlineBar: Double? // 0...1 draws a track between the text and the detail
    var onSlide: ((Double) -> Void)?
    var action: (() -> Void)?
    var hover: (() -> Void)? // the pointer came onto the row
    var tint: NSColor? // overrides the hero/dim colour for one row
    var barTint: NSColor? // colours the inline bar alone, leaving the label
    var iconTint: NSColor? // overrides the accent colour of the icon
    var section: String? // plugin rows: "open" or "closed" starts a section, "end" ends one
    var open: Bool? // a section title after foldSections: whether its rows show
}

final class PopupWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

var popupWindow: PopupWindow?
var openPopup: String? // which bar item owns it
weak var popupOwner: BarSurface? // the bar that shows its pill lit

func closePopup() {
    if openPopup == "wifi" || openPopup == "status" { stopHotspotBrowse() }
    if openPopup == "activity" { stopActivitySampling() }
    setPopupKeys(false)
    popupWindow?.orderOut(nil)
    popupWindow = nil
    popupShownRows = []
    popupSelection = nil
    popupColumns = []
    cascadeWork?.cancel()
    openPopup = nil
    popupOwner?.view.needsDisplay = true
    popupOwner = nil
}

// Rows rebuild fully on each refresh: cheap to regenerate, and a stale row
// is worse than a redrawn one.
// The window resizes exactly on each refresh. Grow-only left the app-menu
// popup huge after a long menu, and the window is bottom-anchored, so the
// frame is recomputed to keep the top edge under the bar.
var popupTopY: CGFloat = 0
var popupAnchorX: CGFloat = 0
var popupAlignLeft = false
var popupScreen = NSRect.zero // the frame of the bar's screen, which holds the popup

func refreshPopup() {
    guard let name = openPopup, let window = popupWindow, let host = window.contentView as? PanelHost else { return }
    // A plugin that failed has no panel and no rows: close it.
    guard let view = panelView(name) else { closePopup(); return }
    host.rootView = view
    host.placeWindow()
}

func showPopup(_ name: String, under anchor: NSRect, on surface: BarSurface, alignLeft: Bool = false) {
    if openPopup == name { closePopup(); return }
    closePopup()
    guard let view = panelView(name) else { return }
    showPanel(name, view, under: anchor, on: surface, alignLeft: alignLeft)
}

// A click on a pill opens its popup only when the popup has something to show.
func hasPopup(_ name: String) -> Bool {
    switch name {
    case "weather": return weatherReport != nil
    case "status", "clock", "menubar", "activity", "battery", "wifi", "bluetooth", "brightness": return true
    case "volume": return readVolume() != nil
    default: return pluginPanels[name] != nil || !popupRows(for: name).isEmpty
    }
}

// Every case returns a SwiftUI panel. The default case draws plugin and built-in rows as a menu.
// `demo = on` in bar-pills.conf swaps the popups that show private data
// for the sample data of the previews, so a screen recording can go public.
var demoMode: Bool { pillModes["demo"] == "on" }

func demoPanel(_ name: String) -> AnyView? {
    switch name {
    case "weather": return AnyView(WeatherPanel(report: .sample(116, temp: 21)).clipShape(.rect(cornerRadius: 16)))
    case "status": return statusPanel(pillModes["status_panel"], .onBattery, .init())
    case "wifi": return AnyView(WifiPanel(report: .onBattery))
    case "clock": return calendarPanel(pillModes["clock_panel"], .busy, .init())
    case "activity": return activityPanel(pillModes["activity_panel"], .building, .init())
    case "menubar": return menuBarPanel(pillModes["menubar_panel"], .busy, .init())
    default:
        guard let json = pluginPanels[name] else { return nil }
        if PRReport(json: json) != nil { return prPanel(pillModes[name + "_panel"], .busy, .init()) }
        if AIUsageReport(json: json) != nil { return aiUsagePanel(pillModes[name + "_panel"], .busy, .init()) }
        return nil
    }
}

func panelView(_ name: String) -> AnyView? {
    if demoMode, let view = demoPanel(name) { return view }
    switch name {
    case "weather":
        return weatherReport.map { AnyView(WeatherPanel(report: $0, refresh: updateWeather).clipShape(.rect(cornerRadius: 16))) }
    case "status":
        return statusPanel(pillModes["status_panel"], statusReport(), statusActions)
    case "menubar":
        return menuBarPanel(pillModes["menubar_panel"], menuBarReport(), menuBarActions)
    case "activity":
        return activityPanel(pillModes["activity_panel"], activityReport(), activityActions)
    case "volume": return soundReport().map { AnyView(SoundPanel(report: $0, actions: soundActions)) }
    case "brightness": return AnyView(DisplayPanel(report: displayReport(), actions: displayActions))
    case "bluetooth": return AnyView(BluetoothPanel(report: bluetoothReport(), actions: bluetoothActions))
    case "battery": return AnyView(BatteryPanel(report: statusReport(), actions: statusActions))
    case "wifi": return AnyView(WifiPanel(report: statusReport(), actions: statusActions))
    case "apple", "appmenu":
        return cascadePanel(name)
    case "clock":
        return calendarPanel(pillModes["clock_panel"], calendarReport(), calendarActions)
    default:
        guard let json = pluginPanels[name] else { return rowsPanel(popupRows(for: name)) }
        if let report = StatsReport(json: json) {
            var actions = StatsActions()
            actions.open = { url in
                if url.scheme == "x-apple.systempreferences" { NSWorkspace.shared.open(url) }
                closePopup()
            }
            return AnyView(StatsPanel(report: report, actions: actions))
        }
        if let report = KeepAwakeReport(json: json) {
            var actions = KeepAwakeActions()
            actions.openSettings = openBatterySettings
            return AnyView(KeepAwakePanel(report: report, actions: actions))
        }
        if let report = UpdatesReport(json: json) {
            var actions = UpdatesActions()
            actions.update = { closePopup(); runInTerminal($0) }
            actions.refresh = { refreshPlugin(name) }
            return AnyView(UpdatesPanel(report: report, actions: actions))
        }
        if let report = AirPodsReport(json: json) {
            return AnyView(AirPodsPanel(report: report, actions: airPodsActions(plugin: name, settings: report.settings)))
        }
        if let report = PRReport(json: json) {
            var actions = PRActions()
            actions.open = { url in
                if url.scheme == "https" { NSWorkspace.shared.open(url) }
                closePopup()
            }
            actions.openAll = { actions.open(URL(string: "https://github.com/pulls")!) }
            actions.refresh = { refreshPlugin(name) }
            return prPanel(pillModes[name + "_panel"], report, actions)
        }
        guard let report = AIUsageReport(json: json) else { return nil }
        var actions = aiUsageActions(report: json["report"] as? String)
        actions.refresh = { refreshPlugin(name) }
        return aiUsagePanel(pillModes[name + "_panel"], report, actions)
    }
}

func airPodsActions(plugin name: String, settings: URL?) -> AirPodsActions {
    var actions = AirPodsActions()
    actions.openSettings = {
        if let settings, settings.scheme == "x-apple.systempreferences" { NSWorkspace.shared.open(settings) }
        closePopup()
    }
    actions.setMode = { runPluginCommand(name, $0.run) }
    return actions
}

// A plugin's command in a terminal window, as a row's "terminal" runs it.
func runInTerminal(_ command: String) {
    guard !command.isEmpty else { return }
    DispatchQueue.global(qos: .userInitiated).async {
        _ = shell("/usr/bin/open", ["-na", terminalApp, "--args",
                                    "--title=omacchiato-plugin", "--command=\(command)"])
    }
}

// A panel button that runs a plugin's command: the same path as a row's
// "run". The command is argv to sh, and the plugin runs again after it.
func runPluginCommand(_ name: String, _ command: String) {
    guard let plugin = barPlugins.first(where: { $0.name == name }), !command.isEmpty else { return }
    DispatchQueue.global(qos: .userInitiated).async {
        _ = shell("/bin/sh", ["-c", command], env: pluginEnv(plugin))
        runPlugin(plugin)
    }
}

func aiUsageActions(report command: String?) -> AIUsageActions {
    var actions = AIUsageActions()
    actions.open = { url in
        if url.scheme == "https" { NSWorkspace.shared.open(url) }
        closePopup()
    }
    actions.openReport = {
        closePopup()
        if let command { runInTerminal(command) }
    }
    return actions
}

final class PanelHost: NSHostingView<AnyView> {
    // The popup window never becomes key, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // A panel can change its own size, as when a section opens.
    override func layout() {
        super.layout()
        if let window, window.frame.size != fittingSize { placeWindow() }
    }

    // Fits the window to the panel: top edge under the bar, side at the pill.
    func placeWindow() {
        guard let window else { return }
        let size = fittingSize
        let screen = popupScreen
        let x = min(max(screen.minX + 6, popupAlignLeft ? popupAnchorX : popupAnchorX - size.width),
                    screen.maxX - size.width - 6)
        window.setFrame(NSRect(x: x, y: popupTopY - size.height, width: size.width, height: size.height), display: true)
    }

    // A global monitor stops once this app is active, and a bar click makes
    // the app active, so this uses a tracking area instead. Remove only this
    // area; SwiftUI's own hover area shares the view.
    private var hullArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hullArea.map(removeTrackingArea)
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hullArea = area
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        scheduleHullCheck()
    }
}

func showPanel(_ name: String, _ view: AnyView, under anchor: NSRect, on surface: BarSurface, alignLeft: Bool = false) {
    let host = PanelHost(rootView: view)
    popupTopY = surface.window.frame.minY - 4
    popupScreen = surface.screen.frame
    popupAnchorX = alignLeft ? anchor.minX : anchor.maxX
    popupAlignLeft = alignLeft
    let window = PopupWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.contentView = host
    host.placeWindow()
    window.alphaValue = 0
    window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = dur(0.12)
        window.animator().alphaValue = 1
    }
    popupWindow = window
    openPopup = name
    popupOwner = surface
    surface.view.needsDisplay = true
    setPopupKeys(!popupShownRows.isEmpty)
}

// The rows of an open row popup, and the one the arrow keys selected.
var popupShownRows: [PopupRow] = []
var popupSelection: Int?

// Keep in sync with the look of a row in RowsPanel.
func panelRow(_ row: PopupRow) -> PanelRow {
    var out = PanelRow()
    // App menus use › for a submenu and ‹ to go back.
    out.submenu = row.icon == "›"
    out.back = row.icon == "‹"
    out.icon = out.submenu || out.back ? "" : row.icon
    out.image = row.image
    out.text = row.text
    out.detail = row.detail
    out.subtitle = row.subtitle
    out.separator = row.separator
    out.hero = row.hero
    out.dim = row.dim
    out.highlight = row.highlight
    out.slider = row.slider
    out.bar = row.inlineBar
    out.marker = row.marker
    out.tint = row.tint.map { Color(nsColor: $0) }
    out.barTint = row.barTint.map { Color(nsColor: $0) }
    out.iconTint = row.iconTint.map { Color(nsColor: $0) }
    out.open = row.open
    out.action = row.action
    out.onHover = row.hover
    out.onSlide = row.onSlide
    return out
}

// A popup of rows as a panel. The screen height caps it, and more rows scroll.
func rowsPanel(_ rows: [PopupRow]) -> AnyView? {
    popupShownRows = rows
    guard !rows.isEmpty else { return nil }
    if let i = popupSelection, !rows.indices.contains(i) { popupSelection = nil }
    let limit = (NSScreen.main?.visibleFrame.height ?? 800) - 40
    return AnyView(RowsPanel(rows: rows.map(panelRow), selected: popupSelection, maxHeight: limit))
}

// True when the key belongs to the popup.
func popupKey(_ code: Int) -> Bool {
    switch code {
    case 53: // Esc
        closePopup()
    case 125, 126: // ↓, ↑
        let clickable = popupShownRows.indices.filter {
            popupShownRows[$0].action != nil && popupShownRows[$0].slider == nil
        }
        popupSelection = nextSelection(clickable, from: popupSelection, by: code == 125 ? 1 : -1)
        refreshPopup()
    case 124: // →, into the selected submenu
        guard let i = popupSelection, popupShownRows.indices.contains(i),
              popupShownRows[i].icon == "›", let action = popupShownRows[i].action else { return false }
        action()
    case 123: // ←, out of a submenu
        guard popupColumns.count > 1, let top = appMenuStack.popLast() else { return false }
        popupSelection = popupColumns[popupColumns.count - 2].firstIndex { $0.icon == "›" && $0.text == top.title }
        refreshPopup()
    case 36, 76: // Return, Enter
        // with no row selected, Return still reaches the front app
        guard let i = popupSelection, popupShownRows.indices.contains(i),
              let action = popupShownRows[i].action else { return false }
        action()
    default:
        return false
    }
    return true
}

// A tap takes these keys only while a popup is open, so the front app
// keeps its focus. A key with a modifier passes through.
var popupKeyTap: CFMachPort?

func setPopupKeys(_ on: Bool) {
    if on, popupKeyTap == nil {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = popupKeyTap, !popupShownRows.isEmpty { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                guard modifiers.isEmpty, !popupShownRows.isEmpty,
                      popupKey(Int(event.getIntegerValueField(.keyboardEventKeycode))) else {
                    return Unmanaged.passUnretained(event)
                }
                return nil
            }, userInfo: nil)
        else {
            tlog("popup keys: no event tap, so no Accessibility grant")
            return
        }
        popupKeyTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }
    if let tap = popupKeyTap { CGEvent.tapEnable(tap: tap, enable: on) }
}

// The next row to select among the rows that take a click, wrapping at the ends.
func nextSelection(_ rows: [Int], from current: Int?, by delta: Int) -> Int? {
    guard !rows.isEmpty else { return nil }
    guard let current, let at = rows.firstIndex(of: current) else {
        return delta > 0 ? rows.first : rows.last
    }
    return rows[(at + delta + rows.count) % rows.count]
}
