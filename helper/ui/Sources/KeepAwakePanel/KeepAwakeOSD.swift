import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the bar shows when keep awake turns on or off, from any source.
public struct KeepAwakeOSD: View {
    var on: Bool
    var detail: String       // "Until 5:30 PM", "Until turned off", "Timer ended"

    public init(on: Bool, detail: String) {
        self.on = on
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: on ? "cup.and.saucer.fill" : "moon.zzz.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? AnyShapeStyle(PanelColors.hudAccent) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(on ? "Keeping Awake" : "Sleep Allowed").font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 260)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
