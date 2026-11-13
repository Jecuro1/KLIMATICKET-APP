import SwiftUI
import KlimaCore

// MARK: anschluss – the guard in the tab bar accessory (docs/CONNECTION_GUARD.md §8): a small capsule with the swap glyph and
// one word („knapper“, „wackelt“, „wohl verpasst“, „verpasst“, „fällt aus“) while the change is worse than „Sicher“. VoiceOver
// reads the whole phrase („Anschluss wahrscheinlich verpasst“). Draws nothing when the change is safe or there is no guard.

struct ConnectionGuardBadge: View {
    let tripID: String
    private var service: ConnectionGuardService { .shared }

    var body: some View {
        if service.watches(tripID: tripID), let state = service.assessment?.state,
           let word = GuardText.badgeCompact(state), let phrase = GuardText.badge(state) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.caption2.weight(.bold))
                Text(word)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(GuardStyle.textColor(state))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(GuardStyle.color(state).opacity(0.16), in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phrase)
            .motionTransition(.pop)
            .id(state)
        }
    }
}
