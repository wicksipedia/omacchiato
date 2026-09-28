import SwiftUI
import ImageIO

// What the theme picker shows: each theme in `themes/`, read from the
// same files theme-set reads, so a preview matches what Apply does, and
// the saved choice from theme.conf: one theme, or one by day and one at night.
public struct ThemeReport {
    public var themes: [Theme]
    public var light: String?               // the day theme in theme.conf
    public var dark: String?                // the night theme; the same name when one theme serves both
    public var darkNow: Bool                // the macOS appearance, which picks the half on show

    public init(themes: [Theme], light: String?, dark: String?, darkNow: Bool = false) {
        self.themes = themes
        self.light = light
        self.dark = dark
        self.darkNow = darkNow
    }

    // Read every theme in a directory, such as ~/.local/share/omacchiato/themes,
    // and the `theme` value of theme.conf.
    public init(directory: URL, spec: String, darkNow: Bool = false) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let choice = Self.choice(spec)
        self.init(themes: names.sorted().compactMap { Theme(directory: directory.appendingPathComponent($0)) },
                  light: choice?.light, dark: choice?.dark, darkNow: darkNow)
    }

    public func theme(_ name: String?) -> Theme? { themes.first { $0.name == name } }

    // `name`, or `light:<name>,dark:<name>`, as theme-set takes it.
    public static func choice(_ spec: String) -> (light: String, dark: String)? {
        let spec = spec.trimmingCharacters(in: .whitespaces)
        guard !spec.isEmpty else { return nil }
        guard spec.contains(":") else { return (spec, spec) }
        var halves: [String: String] = [:]
        for half in spec.split(separator: ",") {
            let pair = half.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { halves[pair[0]] = pair[1] }
        }
        guard let light = halves["light"] ?? halves["dark"], let dark = halves["dark"] ?? halves["light"] else { return nil }
        return (light, dark)
    }

    public static func spec(light: String, dark: String) -> String {
        light == dark ? light : "light:\(light),dark:\(dark)"
    }
}

public struct Theme: Identifiable {
    public var name: String                 // the directory name, which theme-set takes
    public var bar: Bar
    public var border: Border
    public var terminal: Terminal
    public var wallpaper: NSImage?
    public var id: String { name }

    public struct Bar {
        public var background: Color
        public var item: Color
        public var accent: Color
        public var label: Color
        public var muted: Color
    }

    public struct Border {
        public var active: Color
        public var inactive: Color
        public var gradient: Color?
        public var glow: Bool
    }

    public struct Terminal {
        public var background: Color
        public var foreground: Color
        public var cursor: Color
        public var palette: [Color]         // color0 to color15
    }

    // "tokyo-night" reads "Tokyo Night"
    public var title: String {
        name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    public var dark: Bool { terminal.background.luminance < 0.5 }

    public init(name: String, bar: Bar, border: Border, terminal: Terminal, wallpaper: NSImage? = nil) {
        self.name = name
        self.bar = bar
        self.border = border
        self.terminal = terminal
        self.wallpaper = wallpaper
    }

    public init?(directory: URL) {
        let exports = Self.exports(directory.appendingPathComponent("sketchybar.sh"))
            .merging(Self.exports(directory.appendingPathComponent("borders.sh"))) { a, _ in a }
        let toml = Self.toml(directory.appendingPathComponent("colors.toml"))
        guard let background = toml["background"], let foreground = toml["foreground"],
              let accent = exports["ACCENT"] else { return nil }
        let palette = (0..<16).map { toml["color\($0)"] ?? foreground }
        name = directory.lastPathComponent
        bar = Bar(background: exports["BAR_COLOR"] ?? background, item: exports["ITEM_BG"] ?? .clear,
                  accent: accent, label: exports["LABEL_COLOR"] ?? foreground, muted: exports["MUTED"] ?? palette[8])
        border = Border(active: exports["ACTIVE_COLOR"] ?? accent, inactive: exports["INACTIVE_COLOR"] ?? palette[8],
                        gradient: exports["GRADIENT_COLOR"], glow: Self.flag(directory.appendingPathComponent("borders.sh"), "GLOW"))
        terminal = Terminal(background: background, foreground: foreground,
                            cursor: toml["cursor"] ?? foreground, palette: palette)
        let backgrounds = directory.appendingPathComponent("backgrounds")
        let first = ((try? FileManager.default.contentsOfDirectory(atPath: backgrounds.path)) ?? []).sorted().first
        wallpaper = first.flatMap { Self.thumbnail(backgrounds.appendingPathComponent($0)) }
    }

    // `export KEY=0xAARRGGBB` lines
    static func exports(_ url: URL) -> [String: Color] {
        var out: [String: Color] = [:]
        for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.replacingOccurrences(of: "export ", with: "").split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[1].hasPrefix("0x"), let v = UInt32(parts[1].dropFirst(2), radix: 16)
            else { continue }
            out[String(parts[0]).trimmingCharacters(in: .whitespaces)] = Color(argb: v)
        }
        return out
    }

    static func flag(_ url: URL, _ key: String) -> Bool {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").contains("\(key)=1")
    }

    // `key = "#rrggbb"` lines
    static func toml(_ url: URL) -> [String: Color] {
        var out: [String: Color] = [:]
        for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[1].hasPrefix("\"#"),
                  let v = UInt32(parts[1].dropFirst(2).prefix(6), radix: 16) else { continue }
            out[parts[0]] = Color(argb: 0xff00_0000 | v)
        }
        return out
    }

    // A small copy of the wallpaper: some are several MB, and the preview is a few hundred points wide.
    static func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 900,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

public struct ThemeActions {
    public var apply: (_ light: String, _ dark: String) -> Void = { _, _ in }

    public init() {}
}

extension Color {
    init(argb v: UInt32) {
        self.init(.sRGB, red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255,
                  blue: Double(v & 0xff) / 255, opacity: Double(v >> 24 & 0xff) / 255)
    }

    var luminance: Double {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}
