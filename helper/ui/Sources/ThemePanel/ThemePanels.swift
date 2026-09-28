import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// The theme picker: a desktop in the theme under view across the top, the
// day and night halves of the choice, and the themes as cards. A card
// sets the half that is selected, and Apply saves both through theme-set.
// One theme in both halves is one theme all day.
public struct ThemePanel: View {
    var report: ThemeReport
    var actions: ThemeActions
    @State private var slot: DaySlot
    @State private var day: String?
    @State private var night: String?

    public init(report: ThemeReport, actions: ThemeActions = .init()) {
        self.report = report
        self.actions = actions
        let fallback = report.themes.first?.name
        _slot = State(initialValue: report.darkNow ? .night : .day)
        _day = State(initialValue: report.light ?? fallback)
        _night = State(initialValue: report.dark ?? fallback)
    }

    var shown: String? { slot == .day ? day : night }
    var changed: Bool { day != report.light || night != report.dark }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let theme = report.theme(shown) {
                // the panel's padding is 12 and its corners 22: the desktop runs edge to edge
                ThemeMockup(theme: theme, top: 22, bottom: 0)
                    .id(theme.name)
                    .transition(.opacity)
                    .padding([.horizontal, .top], -12)
            }
            SlotPicker(slot: $slot, day: report.theme(day), night: report.theme(night))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(report.themes) { card($0) }
            }
            HStack {
                Text(day == night ? "One theme all day." : "Follows the macOS appearance.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                ApplyButton(enabled: changed) {
                    if let day, let night { actions.apply(day, night) }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: shown)
        .statusPanelBackground(width: 440)
    }

    func card(_ theme: Theme) -> some View {
        let on = theme.name == shown
        return VStack(spacing: 4) {
            ThemeMockup(theme: theme)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
                .overlay(alignment: .bottomTrailing) {
                    // which half of the day the theme holds
                    HStack(spacing: 2) {
                        if theme.name == day { badge("sun.max.fill", .orange) }
                        if theme.name == night { badge("moon.fill", .indigo) }
                    }
                    .padding(3)
                }
            Text(theme.title).font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(on ? .primary : .secondary)
        }
        .contentShape(.rect)
        .onTapGesture {
            if slot == .day { day = theme.name } else { night = theme.name }
        }
        .help(theme.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(color, in: .circle)
    }
}
