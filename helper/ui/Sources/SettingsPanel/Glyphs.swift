import SwiftUI

// Every Nerd Font glyph by name, from Nerd Fonts' glyphnames.json, which
// install.sh downloads. A name reads "<set>-<words>", as md-coffee.
public struct Glyph: Identifiable, Hashable {
    public var name: String
    public var char: String
    public var id: String { name }

    public init(name: String, char: String) {
        self.name = name
        self.char = char
    }
}

// The bar loads the list once and sets it here. Empty means no list, and
// the picker falls back to the short list of common icons.
public enum GlyphLibrary {
    public static var glyphs: [Glyph] = []
}

public func loadGlyphs(_ data: Data) -> [Glyph] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return json.compactMap { name, value in
        guard let char = (value as? [String: Any])?["char"] as? String else { return nil }
        return Glyph(name: name, char: char)
    }
    .sorted { $0.name < $1.name }
}

// Every word of the query must be in the name. Shorter names first, so
// "coffee" puts md-coffee before md-coffee_maker.
public func searchGlyphs(_ glyphs: [Glyph], _ query: String, limit: Int = 300) -> [Glyph] {
    let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
    let hits = words.isEmpty ? glyphs : glyphs.filter { glyph in words.allSatisfy { glyph.name.contains($0) } }
    return Array(hits.sorted { ($0.name.count, $0.name) < ($1.name.count, $1.name) }.prefix(limit))
}

// A search field over the glyphs, and a grid to pick one. With no glyph
// list, the grid shows the short list of common icons.
struct GlyphPicker: View {
    var glyphs = GlyphLibrary.glyphs
    var selected: String = ""
    var pick: (String) -> Void
    @State private var query = ""

    var shown: [Glyph] {
        glyphs.isEmpty
            ? SettingsReport.PluginFields.glyphs.map { Glyph(name: $0.1, char: $0.0) }
            : searchGlyphs(glyphs, query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !glyphs.isEmpty {
                TextField("Search icons, such as coffee or github", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
                    ForEach(shown) { glyph in
                        Button { pick(glyph.char) } label: {
                            SettingsGlyph(glyph: glyph.char, size: 16)
                                .frame(width: 34, height: 30)
                                .background(selected == glyph.char ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                                                   : AnyShapeStyle(.fill.quaternary),
                                            in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(glyph.name)
                        .accessibilityLabel(glyph.name)
                    }
                }
            }
            .frame(width: 8 * 38, height: 220)
            if !glyphs.isEmpty {
                Text(query.isEmpty ? "\(glyphs.count) icons" : "\(searchGlyphs(glyphs, query, limit: .max).count) found")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// Puts the glyph where the cursor is, or over the selected text. With no
// cursor, it goes at the end.
func insertGlyph(_ glyph: String, into text: String, at selection: TextSelection?) -> String {
    guard let selection, case .selection(let range) = selection.indices,
          range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return text + glyph }
    var out = text
    out.replaceSubrange(range, with: glyph)
    return out
}
