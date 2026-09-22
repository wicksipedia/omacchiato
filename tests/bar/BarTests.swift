import AppKit
import Testing
@testable import omacchiato_bar

// Serialized: some tests set the globals popupBarSource and NSTimeZone.default.
@MainActor @Suite(.serialized)
struct BarTests {
    @Test("windows on one frame keep the layout order")
    func parkedWindows() {
        #expect(layoutOrder([(1799, 12, "Voice Memos"), (1799, 12, "Notes")]) == ["Voice Memos", "Notes"])
    }

    @Test("the leftmost window comes first")
    func leftmostFirst() {
        #expect(layoutOrder([(900, 12, "Notes"), (6, 12, "Voice Memos")]) == ["Voice Memos", "Notes"])
    }

    @Test("a hand holds three apps, each once")
    func hand() {
        #expect(handOf(["a", "b", "a", "c", "d"]) == ["a", "b", "c"])
    }

    @Test("a long row ends in … inside its room, and a short row stays whole")
    func fitRow() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let cut = fit(String(repeating: "wide ", count: 60), font, 200)
        #expect(advance(cut, font) <= 200)
        #expect(cut.hasSuffix("…"))
        #expect(fit("short", font, 200) == "short")
    }

    @Test("a popup is no wider than popupMaxWidth")
    func popupWidth() {
        let view = PopupView(frame: .zero)
        view.rows = [PopupRow(text: String(repeating: "wide ", count: 60))]
        #expect(view.measure().width <= popupMaxWidth)
    }

    @Test("opening a section moves no bar")
    func barColumns() {
        let bars = [PopupRow(text: "a", detail: "1%", inlineBar: 0.1),
                    PopupRow(text: "a much longer label", detail: "100% · 3h", inlineBar: 0.9)]
        popupBarSource = bars
        defer { popupBarSource = [] }
        let view = PopupView(frame: .zero)
        view.rows = [bars[0]]
        let folded = view.barColumns()
        view.rows = bars
        #expect(folded == view.barColumns())
    }

    @Test("a closed section hides its rows and keeps its rule")
    func sections() {
        let rows = [PopupRow(text: "h", section: "closed"), PopupRow(text: "x"), PopupRow(separator: true),
                    PopupRow(text: "h2", section: "open"), PopupRow(text: "y")]
        #expect(foldSections("test", rows).map(\.text) == ["h", "", "h2", "y"])
    }

    @Test("plugin rows read subtitle, bar and bar_color")
    func pluginRows() throws {
        let row = try #require(pluginPopupRows(
            [["text": "claude", "subtitle": "max", "bar": 0.5, "bar_color": "red"]], of: BarPlugin()).first)
        #expect(row.subtitle == "max")
        #expect(row.inlineBar == 0.5)
        #expect(row.barTint != nil)
    }

    @Test("the month grid blanks other months' days and circles today")
    func monthGrid() throws {
        let cal = Calendar(identifier: .gregorian)
        let sep21 = try #require(cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12)))
        let month = monthRows(sep21)
        let weeks = Array(month.compactMap(\.columns).dropFirst())
        #expect(weeks.first == ["", "1", "2", "3", "4", "5", "6"])
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        let today = try #require(month.first { $0.columnAccent != nil })
        #expect(today.columns?[today.columnAccent!] == "21")
    }

    @Test("a week link counts the day the clocks change")
    func daylightSaving() throws {
        let zone = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: "Australia/Sydney"))
        defer { NSTimeZone.default = zone }
        let cal = Calendar(identifier: .gregorian)
        let before = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12)))
        let after = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        #expect(dayOffset(from: before, to: after) == 2)
    }

    @Test("menu shortcuts read the modifier mask")
    func shortcuts() {
        #expect(shortcutText("Q", 4) == "⌃⌘Q")
        #expect(shortcutText("Q", 1) == "⇧⌘Q")
        #expect(shortcutText("F", 8) == "F")
    }

    @Test("menu bar apps sort by name and tell two icons of one app apart")
    func menuBarApps() {
        let titles = menuBarTitles([("OneDrive", "OneDrive - SSW"), ("Bartender", ""),
                                    ("OneDrive", "OneDrive - TinaCMS"), ("Zed", ""), ("Zed", "")])
        #expect(titles.map(\.text) == ["Bartender", "OneDrive · SSW", "OneDrive · TinaCMS", "Zed 1", "Zed 2"])
    }

    @Test("the OmniWM dev build counts as OmniWM")
    func omniWM() {
        #expect(isOmniWM("com.barut.OmniWM"))
        #expect(isOmniWM("com.barut.OmniWM.dev"))
        #expect(!isOmniWM("com.example"))
        #expect(!isOmniWM(nil))
    }

    @Test("popup text on glass stays legible over white or black, on every theme")
    func glassContrast() throws {
        func luminance(_ c: NSColor) -> CGFloat {
            let c = c.usingColorSpace(.sRGB)!
            func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent)
                + 0.0722 * channel(c.blueComponent)
        }
        let themes = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../themes").standardized
        let names = try FileManager.default.contentsOfDirectory(atPath: themes.path)
            .filter { FileManager.default.fileExists(atPath: themes.appendingPathComponent("\($0)/sketchybar.sh").path) }
        #expect(!names.isEmpty)
        for name in names {
            let palette = loadPalette(themes.appendingPathComponent("\(name)/sketchybar.sh"))
            for backdrop in [NSColor.white, NSColor.black] {
                let glass = backdrop.blended(withFraction: popupGlassFill, of: palette.barBG)!
                let (a, b) = (luminance(palette.label), luminance(glass))
                let contrast = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                #expect(contrast >= 4.5, "\(name) over \(backdrop == .white ? "white" : "black"): \(contrast)")
            }
        }
    }

    @Test("a clear pill still takes clicks")
    func clickable() {
        #expect(NSColor.clear.clickable.alphaComponent > 0)
    }
}
