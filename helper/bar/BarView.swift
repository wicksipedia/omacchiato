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
import ActivityPanel
import BarPills
import AIUsagePanel
import CalendarPanel
import MenuBarPanel
import PRPanel
import RowsPanel
import StatusPanel
import ThemePanel
import WeatherPanel
#endif

// --- view -----------------------------------------------------------------

// Icons come from the running app and are cached by name: a redraw must
// not walk the process list.
var iconCache: [String: NSImage] = [:]
func appIcon(_ name: String) -> NSImage? {
    if let cached = iconCache[name] { return cached }
    guard let icon = NSWorkspace.shared.runningApplications
        .first(where: { $0.localizedName == name })?.icon else { return nil }
    iconCache[name] = icon
    return icon
}

let barHeight: CGFloat = 34
let padLeft: CGFloat = 10
let pillHeight: CGFloat = 26
let radius: CGFloat = 4
// `left_gap` and `right_gap` in bar-pills.conf set the space between pills
let leftGap = max(0, CGFloat(Double(pillModes["left_gap"] ?? "") ?? 6))
let rightGap = max(0, CGFloat(Double(pillModes["right_gap"] ?? "") ?? 6))
// horizontal breathing room inside a pill, each side
let pillPad: CGFloat = 6

// The absolute path to btop. login(1) execs with the system PATH, which has
// no Homebrew prefix, so plain "btop" fails with "No such file or
// directory". This path goes to Ghostty as --command, not -e: -e asks for
// confirmation every time, by design, closing the hole where any process
// could tell the terminal what to run (GHSA-q9fg-cpmh-c78x).
let btopBin = ["/opt/homebrew/bin/btop", "/usr/local/bin/btop"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "btop"

// install.sh resolves apps.local.conf overrides and writes the result
// here, under ~/.config, next to the other daemon configs. A launchd
// agent cannot read the repo when the clone sits under ~/Documents.
let terminalApp: String = {
    let config = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/omacchiato/apps.conf")
    guard let text = try? String(contentsOf: config, encoding: .utf8) else { return "Ghostty" }
    for line in text.split(separator: "\n") where line.hasPrefix("TERMINAL=") {
        return line.dropFirst("TERMINAL=".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
    return "Ghostty"
}()

final class BarView: NSView {
    weak var surface: BarSurface?
    let marquee = Marquee()
    let ticker = Ticker()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(marquee)
        addSubview(ticker)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    var chipRects: [(String, NSRect, [String])] = []
    // the pill a popup hangs under, and the larger area that takes its clicks
    var itemRects: [(String, pill: NSRect, hit: NSRect)] = []
    var mediaRects: [(String, NSRect)] = []
    var appleRect: NSRect = .zero

    override var isFlipped: Bool { false }

    // bar-pills.conf: `media` and `media_notch` cap the title in characters,
    // and `media_notch_fill = no` stops the pill growing up to the notch.
    private func mediaMaxWidth(notchRoom: CGFloat?, _ titleFont: NSFont) -> CGFloat {
        let chrome = MediaPill.chrome(pillHeight: pillHeight)
        func chars(_ key: String, _ fallback: Int) -> CGFloat {
            chrome + advance(String(repeating: "0", count: Int(pillModes[key] ?? "") ?? fallback), titleFont)
        }
        guard let room = notchRoom else { return chars("media", 28) }
        return pillModes["media_notch_fill"] == "no" ? min(room, chars("media_notch", 20)) : room
    }

    private func mediaSize(_ titleFont: NSFont, maxWidth: CGFloat) -> CGFloat {
        guard model.media.running, !model.media.title.isEmpty else { return 0 }
        return MediaPill(title: model.media.title).layout(font: titleFont, maxWidth: maxWidth, pillHeight: pillHeight).width
    }

    private func drawMedia(at origin: CGFloat, _ titleFont: NSFont, maxWidth: CGFloat) {
        let media = MediaPill(title: model.media.title, art: mediaArt)
        let width = media.layout(font: titleFont, maxWidth: maxWidth, pillHeight: pillHeight).width
        let pill = NSRect(x: origin, y: (barHeight - pillHeight) / 2, width: width, height: pillHeight)
        let title = media.draw(in: pill, font: titleFont, maxWidth: maxWidth, radius: radius,
                               placeholderFont: nerdFont("Bold", 12), colors: pillColors)
        marquee.show(model.media.title, font: titleFont, color: palette.label, in: title)
        mediaRects.append(("title", NSRect(x: pill.minX, y: 0, width: pill.width, height: barHeight)))
    }

    private var pillColors: PillColors {
        PillColors(background: palette.itemBG, accent: palette.accent, label: palette.label, muted: palette.muted)
    }

    override func draw(_ dirtyRect: NSRect) {
        chipRects.removeAll()
        itemRects.removeAll()
        mediaRects.removeAll()
        let chipFont = menuBarFont(.medium)
        let appFont = menuBarFont(.bold)
        let iconFont = nerdFont("Bold", 14)
        guard let surface else { return }

        // Chips are grouped per display, in one bracket.
        // Undocked, the guest set (11-19) parks on this one display.
        // Filtering hides its empty slots, which would otherwise render
        // as duplicate digits, and keeps an empty primary slot so the row
        // still holds 1..9.
        // Docked, each surface's own list is already the right set.
        // Filtering it here once left the laptop showing only two icons.
        let shown = surfaces.count > 1 ? surface.workspaces
            : surface.workspaces.filter {
                $0.count == 1 || model.occupied.contains($0) || $0 == model.focused
            }
        // apple pill: the system menu the hidden native menu bar carried
        let appleGlyph = "\u{f179}"
        let appleFont = nerdFont("Bold", 15)
        let appleW = inkBox(appleGlyph, appleFont).width + pillPad * 2
        let apple = NSRect(x: padLeft, y: (barHeight - pillHeight) / 2, width: appleW, height: pillHeight)
        fillPill(apple, "apple")
        drawIcon(appleGlyph, appleFont, palette.accent, centeredIn: apple)
        appleRect = NSRect(x: apple.minX, y: 0, width: appleW, height: barHeight)

        let hands = shown.map { ws -> [(String, NSImage)] in
            switch workspaceIconConfig.icon(for: ws) {
            case .some(.glyph), .some(.image): return []
            default: break
            }
            return (model.wsApps[ws] ?? []).compactMap { name in appIcon(name).map { (name, $0) } }
        }
        // Each display marks the workspace it is showing, not the
        // globally focused one. Docked, the focused workspace never
        // matched the other screen's bar, which then had no "you are
        // here" marker.
        let chips = shown.enumerated().map { i, ws -> WorkspaceChip in
            let face: WorkspaceChip.Face
            switch workspaceIconConfig.icon(for: ws) {
            case .some(.glyph(let glyph)): face = .glyph(glyph)
            case .some(.image(let icon)): face = .image(icon)
            case .some(.unavailable), .none:
                let cards = hands[i]
                face = cards.isEmpty ? .digit(String(ws.suffix(1)))
                    : .hand(cards.map(\.1), ring: ws == model.focused ? cards.firstIndex { $0.0 == model.focusedApp } : nil)
            }
            return WorkspaceChip(face: face, focused: ws == model.focused, shown: ws == surface.visible)
        }
        let slots = drawWorkspaces(chips, x: apple.maxX + leftGap, barHeight: barHeight, pillHeight: pillHeight,
                                   radius: radius, digitFont: chipFont, glyphFont: iconFont, colors: pillColors)
        for (i, ws) in shown.enumerated() { chipRects.append((ws, slots[i], hands[i].map(\.0))) }
        let bracket = NSRect(x: apple.maxX + leftGap, y: 0, width: chips.reduce(0) { $0 + $1.width }, height: barHeight)

        // front-app pill — clickable: it drops the app's real menus
        var leftEdge = bracket.maxX
        appPillRect = .zero
        if !model.frontApp.isEmpty {
            let textW = advance(model.frontApp, appFont)
            let pill = NSRect(x: bracket.maxX + leftGap, y: (barHeight - pillHeight) / 2,
                              width: textW + pillPad * 2, height: pillHeight)
            fillPill(pill, "appmenu")
            drawText(model.frontApp, appFont, palette.accent, centeredIn: pill)
            appPillRect = pill
            leftEdge = pill.maxX
        }

        // media: centred where there is room. Where a notch owns the middle,
        // it joins the left cluster and runs up to the notch.
        let notchX = surface.screen.auxiliaryTopLeftArea.map { $0.maxX - surface.screen.frame.minX }
        let mediaX = leftEdge + leftGap
        let mediaMax = mediaMaxWidth(notchRoom: notchX.map { $0 - leftGap - mediaX }, chipFont)
        let mediaW = mediaSize(chipFont, maxWidth: mediaMax)
        if mediaW > 0 {
            drawMedia(at: notchX != nil ? mediaX : (bounds.width - mediaW) / 2, chipFont, maxWidth: mediaMax)
        } else {
            marquee.hide()
        }

        // right cluster: laid out from the right edge inwards, so a pill
        // changing width never shifts the ones outside it
        var cursor = bounds.maxX - padLeft
        var tickerShown = false
        for name in rightOrder.reversed() {
            guard let item = rightItems[name], item.drawing else { continue }
            if let gauge = item.gauge {
                let side = pillHeight - 2
                // the ring's ink is 0.89 of the gauge's side, so trim the rest from the pill
                let ink = side * 0.89
                let pill = NSRect(x: cursor - ink - pillPad * 2, y: (barHeight - pillHeight) / 2,
                                  width: ink + pillPad * 2, height: pillHeight)
                let hitMaxX = cursor == bounds.maxX - padLeft ? bounds.maxX : pill.maxX + rightGap / 2
                let hitArea = NSRect(x: pill.minX - rightGap / 2, y: 0,
                                     width: hitMaxX - pill.minX + rightGap / 2, height: bounds.height)
                NSColor.clear.clickable.setFill()
                hitArea.fill()
                fillPill(pill, name)
                gauge.draw(in: pill.insetBy(dx: pillPad - (side - ink) / 2, dy: 1),
                           colors: .init(ink: palette.label, low: palette.red, charging: palette.green))
                itemRects.append((name, pill, hitArea))
                cursor = pill.minX - rightGap
                continue
            }
            let parts = ([BarPart(icon: item.icon, iconColor: item.iconColor, label: item.label)] + item.parts)
                .filter { !($0.icon.isEmpty && $0.label.isEmpty) }
            guard !parts.isEmpty else { continue }
            let labelFont = chipFont
            // Icons and labels are sized by their ink, so a side bearing
            // cannot change the gap to the next pill.
            let sizes = parts.map { part -> (icon: CGFloat, gap: CGFloat, label: CGFloat) in
                let hasIcon = !part.icon.isEmpty
                let hasLabel = !part.label.isEmpty && !(hasIcon && iconOnly.contains(name))
                return (hasIcon ? inkBox(part.icon, iconFont).width : 0,
                        hasIcon && hasLabel ? 7 : 0,
                        hasLabel ? inkBox(part.label, labelFont).width : 0)
            }
            let partGap: CGFloat = 10
            let width = pillPad * 2 + partGap * CGFloat(parts.count - 1)
                + sizes.reduce(0) { $0 + $1.icon + $1.gap + $1.label }
            let pill = NSRect(x: cursor - width, y: (barHeight - pillHeight) / 2,
                              width: width, height: pillHeight)
            // The bar window only catches clicks where it has ink, so a
            // near miss in a gap fell through to the window below. This
            // hit area covers half of each gap and, for the last pill,
            // runs to the screen edge.
            let hitMaxX = cursor == bounds.maxX - padLeft ? bounds.maxX : pill.maxX + rightGap / 2
            let hitArea = NSRect(x: pill.minX - rightGap / 2, y: 0,
                                 width: hitMaxX - pill.minX + rightGap / 2, height: bounds.height)
            NSColor.clear.clickable.setFill()
            hitArea.fill()
            fillPill(pill, name)
            var x = pill.minX + pillPad
            for (part, size) in zip(parts, sizes) {
                if size.icon > 0 {
                    drawIcon(part.icon, iconFont, part.iconColor ?? palette.label,
                             centeredIn: NSRect(x: x, y: pill.minY, width: size.icon, height: pill.height))
                }
                // a tabular digit such as "1" has empty space on each side
                let labelX = x + size.icon + size.gap - (size.label > 0 ? inkBox(part.label, labelFont).minX : 0)
                if size.label > 0, part.label == item.label, !item.tickerText.isEmpty, !tickerShown {
                    ticker.show(item.label, item.tickerText, item.tickerTail, font: labelFont,
                                colors: (item.labelColor ?? palette.label, palette.yellow),
                                in: NSRect(x: labelX, y: pill.minY, width: size.label, height: pill.height),
                                slide: CFTimeInterval(dur(0.4)))
                    tickerShown = true
                } else if size.label > 0 {
                    drawText(part.label, labelFont, item.labelColor ?? palette.label,
                             leftAt: labelX, midY: pill.midY)
                }
                x += size.icon + size.gap + size.label + partGap
            }
            itemRects.append((name, pill, hitArea))
            cursor = pill.minX - rightGap
        }
        if !tickerShown { ticker.hide() }
    }


    // The pill of the open popup gets a soft fill, as a macOS menu bar item does.
    private func fillPill(_ pill: NSRect, _ name: String) {
        palette.itemBG.setFill()
        NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius).fill()
        guard openPopup == name, popupOwner === surface else { return }
        palette.label.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: pill.insetBy(dx: -2, dy: 0), xRadius: 6, yRadius: 6).fill()
    }

    // Tracking areas, not a poll and not a global monitor: a global
    // monitor stops delivering once this app is itself active, which is
    // exactly what clicking the bar makes it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseExited(with event: NSEvent) { scheduleHullCheck() }

    private func hit(_ event: NSEvent) -> String? {
        let p = convert(event.locationInWindow, from: nil)
        return itemRects.first(where: { $0.hit.contains(p) })?.0
    }

    var appPillRect = NSRect.zero

    // A click on an item and omacchiato-popup both open its popup through here.
    func showItemPopup(_ name: String) {
        guard let surface else { return }
        switch name {
        case "apple", "appmenu":
            let rect = name == "apple" ? appleRect : appPillRect
            guard rect != .zero else { return }
            appMenuStack.removeAll()
            // Clicking the bar deactivates the front app, which makes its
            // menu items read disabled and presses land nowhere. Hand
            // focus straight back; our popup, which never becomes key,
            // stays open.
            NSWorkspace.shared.runningApplications
                .first { $0.localizedName == model.frontApp }?
                .activate()
            // both sit at the left edge, so a right-aligned popup would hang off the screen
            showPopup(name, under: window?.convertToScreen(convert(rect, to: nil)) ?? rect,
                      on: surface, alignLeft: true)
        default:
            guard let rect = itemRects.first(where: { $0.0 == name })?.pill else { return }
            showPopup(name, under: window?.convertToScreen(convert(rect, to: nil)) ?? rect, on: surface)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if appPillRect != .zero, appPillRect.contains(p), surface != nil {
            showItemPopup("appmenu")
            return
        }
        if appleRect.contains(p), surface != nil {
            showItemPopup("apple")
            return
        }
        if let (ws, slot, apps) = chipRects.first(where: { $0.1.contains(p) }) {
            DispatchQueue.global(qos: .userInitiated).async {
                if apps.isEmpty { focusWorkspace(ws) }
                else { focusApp(apps[handIndex(at: p.x, in: slot, count: apps.count)], on: ws) }
            }
            return
        }
        if let part = mediaRects.first(where: { $0.1.contains(p) })?.0 {
            closePopup()
            if part == "title", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        guard let name = hit(event) else {
            closePopup()
            return
        }
        if name == "clock", let link = soonMeetingLink {
            closePopup()
            NSWorkspace.shared.open(link)
            return
        }
        // an item with a popup toggles it; the rest still act directly
        if hasPopup(name), surface != nil {
            showItemPopup(name)
            return
        }
        closePopup()
        // a plugin pill: clicking asks for a fresh value now
        if let plugin = barPlugins.first(where: { $0.name == name }) { runPlugin(plugin) }
    }

    // Middle click: the quick toggle of a pill, with no popup.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if mediaRects.contains(where: { $0.1.contains(p) }) {
            musicCommand("playpause")
            return
        }
        switch hit(event) {
        case "volume":
            toggleMute() // the CoreAudio listener repaints
        case "wifi", "status":
            toggleWifiPower()
        default: break
        }
    }

    // A trackpad flick delivers dozens of precise events plus a momentum
    // tail. Stepping on each one raced through the whole range, so momentum
    // is dropped and precise deltas accumulate until a notch's worth of
    // travel passes. A clicky wheel already arrives one notch at a time.
    private var scrollAccum: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let onChips = chipRects.contains { $0.1.contains(p) }
        let onMedia = mediaRects.contains { $0.1.contains(p) }
        guard let name = onChips ? "workspaces" : onMedia ? "media" : hit(event) else { return }
        if !event.momentumPhase.isEmpty { return }
        if event.phase == .began { scrollAccum = 0 }
        scrollAccum += event.scrollingDeltaY
        let notch: CGFloat = event.hasPreciseScrollingDeltas ? 20 : 1
        if abs(scrollAccum) < notch { return }
        let step = scrollAccum > 0 ? 5 : -5
        scrollAccum = 0
        switch name {
        case "workspaces":
            let op = step > 0 ? "next" : "prev"
            DispatchQueue.global(qos: .userInitiated).async {
                _ = shell("\(NSHomeDirectory())/.local/bin/omacchiato-ws", [op], timeout: omniTimeout)
            }
        case "media":
            musicCommand(step > 0 ? "next track" : "previous track")
        case "volume":
            guard let v = readVolume() else { return }
            writeVolume(v.percent + step) // the CoreAudio listener repaints
        case "brightness":
            var value: Float = 0
            guard DSGetBrightness(builtinDisplayID(), &value) == 0 else { return }
            // one continuous scale: the backlight down to 0, then shade
            if step < 0, value <= 0.001 {
                setShade(shade + 0.08)
            } else if step > 0, shade > 0.001 {
                setShade(shade - 0.08) // come out of shade before raising the backlight
            } else {
                _ = DSSetBrightness(builtinDisplayID(), min(1, max(0, value + Float(step) / 100)))
                updateBrightness()
            }
        default: break
        }
    }
}
