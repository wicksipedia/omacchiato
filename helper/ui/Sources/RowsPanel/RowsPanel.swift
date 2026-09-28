import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// A popup made of rows, drawn as a macOS menu: the built-in menus (Apple,
// the app menus, volume, Bluetooth) and every plugin that prints rows.
public struct PanelRow {
    public var icon = ""                    // a Nerd Font glyph
    public var image: NSImage?
    public var text = ""
    public var detail = ""                  // right-aligned and quiet
    public var subtitle = ""                // follows the text, small and quiet
    public var separator = false
    public var hero = false
    public var dim = false
    public var highlight = false            // the current choice, such as the output device
    public var slider: Double?              // 0...1
    public var bar: Double?                 // 0...1
    public var marker: Double?              // 0...1, a tick across the slider or the bar
    public var tint: Color?
    public var barTint: Color?
    public var iconTint: Color?
    public var open: Bool?                  // a section title: whether its rows show
    public var submenu = false              // opens a menu of its own
    public var back = false                 // goes back to the menu above
    public var action: (() -> Void)?
    public var onSlide: ((Double) -> Void)?

    public init() {}
}

public struct RowsPanel: View {
    var rows: [PanelRow]
    var selected: Int?                      // the index that the arrow keys selected
    var maxHeight: CGFloat

    public init(rows: [PanelRow], selected: Int? = nil, maxHeight: CGFloat = 800) {
        self.rows = rows
        self.selected = selected
        self.maxHeight = maxHeight
    }

    public var body: some View {
        Clamp(minWidth: 220, maxWidth: 520, maxHeight: maxHeight) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows.indices, id: \.self) { i in
                            if rows[i].separator {
                                Divider().padding(.horizontal, 10).padding(.vertical, 5)
                            } else {
                                RowView(row: rows[i], selected: i == selected).id(i)
                            }
                        }
                    }
                    .padding(5)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selected) { _, i in
                    if let i { proxy.scrollTo(i) }
                }
            }
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: 14)
            Color.clear.glassEffect(.regular, in: shape)
            shape.fill(.background.opacity(0.6))
        }
    }
}

// The size of the rows, between limits. A longer row truncates, and more
// rows than fit on the screen scroll.
struct Clamp: Layout {
    var minWidth: CGFloat
    var maxWidth: CGFloat
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = Swift.min(Swift.max(child.sizeThatFits(.unspecified).width, minWidth), maxWidth)
        let height = child.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: Swift.min(height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

// A menu item. The item under the pointer, or the one the arrow keys
// selected, fills with the accent colour and its text turns white.
struct RowView: View {
    var row: PanelRow
    var selected: Bool
    @State private var hovered = false

    var action: (() -> Void)? { row.slider == nil ? row.action : nil }
    var lit: Bool { (hovered || selected) && action != nil }

    var body: some View {
        Group {
            if let value = row.slider {
                HStack(spacing: 10) {
                    lead
                    DrawnSlider(value: value, tint: row.tint ?? .accentColor, marker: row.marker, onSlide: row.onSlide)
                    Text(row.text).font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(.secondary).frame(minWidth: 36, alignment: .trailing)
                }
            } else if row.hero {
                // a section title, as a menu names a group of items
                HStack {
                    Text(row.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 12)
                    trail
                }
            } else {
                HStack(spacing: 6) {
                    lead
                    // one label column, so the bars start together
                    label.frame(width: row.bar == nil ? nil : 84, alignment: .leading)
                    if let bar = row.bar {
                        Track(value: bar, tint: row.barTint ?? row.tint ?? .accentColor, marker: row.marker)
                            .frame(minWidth: 80)
                    } else {
                        Spacer(minLength: 16)
                    }
                    trail
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    @ViewBuilder var lead: some View {
        if row.back {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).frame(width: 14)
        }
        if let image = row.image {
            Image(nsImage: image).resizable().frame(width: 16, height: 16)
        }
        if !row.icon.isEmpty {
            Group {
                if let glyph = glyphImage(row.icon, size: 13) {
                    Image(nsImage: glyph).renderingMode(.template)
                } else {
                    Text(row.icon).font(.system(size: 13))
                }
            }
            .foregroundStyle(lit ? AnyShapeStyle(.white)
                             : AnyShapeStyle(row.iconTint ?? (row.highlight ? .accentColor : .secondary)))
            .frame(width: 18)
        }
    }

    var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.text)
                .font(.system(size: 13, weight: row.back ? .semibold : .regular))
                .foregroundStyle(lit ? AnyShapeStyle(.white)
                                 : row.tint.map { AnyShapeStyle($0) }
                                 ?? (row.dim && action == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
                .lineLimit(1)
                .truncationMode(.tail)
            if !row.subtitle.isEmpty {
                Text(row.subtitle).font(.system(size: 11))
                    .foregroundStyle(lit ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary)).lineLimit(1)
            }
        }
        .layoutPriority(1)
    }

    // Shortcuts and numbers, then the mark of a submenu, a section or the current choice.
    @ViewBuilder var trail: some View {
        if !row.detail.isEmpty {
            Text(row.detail).font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(lit ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                .lineLimit(1).fixedSize()
        }
        if row.submenu {
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        } else if let open = row.open {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                .rotationEffect(.degrees(open ? 90 : 0))
        } else if row.highlight && row.icon.isEmpty && row.image == nil && !row.back {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                .foregroundStyle(lit ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
        }
    }
}

struct Track: View {
    var value: Double
    var tint: Color
    var marker: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                if value > 0 { Capsule().fill(tint).frame(width: Swift.max(6, w * Swift.min(1, value))) }
                if let marker {
                    Capsule().fill(.primary).frame(width: 2, height: 12).offset(x: w * Swift.min(1, Swift.max(0, marker)) - 1)
                }
            }
        }
        .frame(height: 6)
    }
}

// Drawn by hand: the popup window never becomes key, and a system Slider
// in a window that is not key draws grey. The knob follows the pointer at
// once, and the bar sets the value behind it.
struct DrawnSlider: View {
    var value: Double
    var tint: Color
    var marker: Double?
    var onSlide: ((Double) -> Void)?
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shown = dragging ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary).frame(height: 6)
                Capsule().fill(tint).frame(width: Swift.max(6, w * shown), height: 6)
                if let marker {
                    Capsule().fill(.primary).frame(width: 2, height: 12).offset(x: w * marker - 1)
                }
                Circle().fill(.white).shadow(radius: 1, y: 0.5).frame(width: 16, height: 16)
                    .offset(x: Swift.min(Swift.max(0, w * shown - 8), w - 16))
            }
            .frame(height: 16)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let f = Swift.min(1, Swift.max(0, g.location.x / w))
                    dragging = f
                    onSlide?(f)
                }
                .onEnded { _ in dragging = nil })
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            onSlide?(Swift.min(1, Swift.max(0, value + (direction == .increment ? 0.05 : -0.05))))
        }
    }
}
