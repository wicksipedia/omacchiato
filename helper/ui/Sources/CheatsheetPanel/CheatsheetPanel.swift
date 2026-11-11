import SwiftUI

public struct CheatEntry: Equatable, Sendable {
    public let group: String
    public let key: String
    public let action: String

    public init(group: String, key: String, action: String) {
        self.group = group
        self.key = key
        self.action = action
    }
}

/// The bar's window types the search into `filter`.
@Observable public final class CheatsheetModel {
    public var entries: [CheatEntry]
    public var filter = ""

    public init(entries: [CheatEntry]) { self.entries = entries }

    public var visible: [CheatEntry] {
        guard !filter.isEmpty else { return entries }
        let f = filter.lowercased()
        return entries.filter {
            $0.key.lowercased().contains(f) || $0.action.lowercased().contains(f)
                || $0.group.lowercased().contains(f)
        }
    }
}

/// Writes a chord such as "Control+Option+Command+Shift+Left Arrow" with the
/// Mac key symbols. Super is Caps Lock held, so it shows as ⇪.
public func chordSymbols(_ chord: String) -> String {
    let symbols = ["Super": "⇪", "Hyper": "⇪⇧", "Control": "⌃", "Option": "⌥", "Command": "⌘", "Shift": "⇧",
                   "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
                   "Left Arrow": "←", "Right Arrow": "→", "Up Arrow": "↑", "Down Arrow": "↓",
                   "Enter": "↩", "Return": "↩", "Tab": "⇥", "TAB": "⇥", "Esc": "⎋", "ESCAPE": "⎋",
                   "Grave": "`", "Page Up": "⇞", "Page Down": "⇟", "Home": "↖", "End": "↘",
                   "Space": "Space", "Period": ".", "Comma": ","]
    var parts = chord.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    // a chord on the plus key ends in "+", which splits into two empty parts
    if chord.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
    let mods = parts.dropLast().map { symbols[$0] ?? $0 }.joined()
    let key = parts.last.map { symbols[$0] ?? $0 } ?? ""
    return mods + (key.count > 1 && !mods.isEmpty ? " " : "") + key.replacingOccurrences(of: "-", with: "–")
}

struct CheatColumnSection: Identifiable {
    let id: Int
    let title: String
    let rows: [CheatEntry]
}

/// Splits the sections into columns of even height. A section that does not
/// fit continues at the top of the next column under the same title.
func cheatColumns(_ entries: [CheatEntry], count: Int) -> [[CheatColumnSection]] {
    var sections: [(String, [CheatEntry])] = []
    for e in entries {
        if sections.last?.0 == e.group { sections[sections.count - 1].1.append(e) } else { sections.append((e.group, [e])) }
    }
    // a title takes about the height of two rows, with its gap
    let total = sections.reduce(0) { $0 + $1.1.count + 2 }
    let per = max(1, Int((Double(total) / Double(count)).rounded(.up)))
    var columns: [[CheatColumnSection]] = [[]]
    var used = 0
    var id = 0
    for (title, rows) in sections {
        var rest = rows[...]
        while !rest.isEmpty {
            if used + 3 > per, columns.count < count { columns.append([]); used = 0 }
            let take = columns.count < count ? max(1, min(rest.count, per - used - 2)) : rest.count
            columns[columns.count - 1].append(CheatColumnSection(id: id, title: title, rows: Array(rest.prefix(take))))
            id += 1
            used += take + 2
            rest = rest.dropFirst(take)
        }
    }
    return columns.filter { !$0.isEmpty }
}

public struct CheatsheetView: View {
    var model: CheatsheetModel
    var columnCount: Int

    public init(model: CheatsheetModel, columns: Int = 3) {
        self.model = model
        self.columnCount = columns
    }

    public var body: some View {
        let visible = model.visible
        VStack(alignment: .leading, spacing: 18) {
            header(matches: visible.count)
            if visible.isEmpty {
                Text("No shortcuts match “\(model.filter)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack(alignment: .top, spacing: 36) {
                    ForEach(Array(cheatColumns(visible, count: columnCount).enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(column) { section in sectionView(section) }
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .padding(24)
        .fixedSize()
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func header(matches: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
                Text("⇪ is Super: hold Caps Lock").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                if model.filter.isEmpty {
                    Text("Type to search").foregroundStyle(.tertiary)
                } else {
                    Text(model.filter)
                    Text(matches == 1 ? "1 match" : "\(matches) matches").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 220, alignment: .leading)
            .background(.quaternary, in: .capsule)
        }
    }

    private func sectionView(_ section: CheatColumnSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, entry in
                    GridRow {
                        Keycap(chordSymbols(entry.key))
                            .gridColumnAlignment(.trailing)
                        Text(entry.action.prefix(1).uppercased() + entry.action.dropFirst())
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.action): \(entry.key)")
                }
            }
        }
    }
}

struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .frame(minWidth: 26)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }
}
