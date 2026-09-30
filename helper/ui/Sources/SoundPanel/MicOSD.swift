import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the bar shows when the microphone mutes or unmutes, from the
// shortcut or from anywhere else.
public struct MicOSD: View {
    var muted: Bool
    var device: String

    public init(muted: Bool, device: String) {
        self.muted = muted
        self.device = device
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(muted ? PanelColors.red : PanelColors.accent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(muted ? "Microphone Off" : "Microphone On").font(.system(size: 13, weight: .semibold))
                Text(device).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
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
