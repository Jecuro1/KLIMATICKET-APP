import SwiftUI
import KlimaCore

// Building blocks for "Reise mit Etappen" (docs/JOURNEYS.md) shared by the editor, the Fahrten list, the journey detail
// and the favourites.

/// "🚌 › 🚆 › 🚋" – the legs' modes in travel order, each symbol in its mode colour, joined by small chevrons. Decorative
/// (the rows speak the legs themselves).
struct TripJourneyModeStrip: View {
    let modes: [TransportMode]
    var font: Font = .caption.weight(.bold)
    /// Draws the symbols on small tinted plates (rows) instead of plain (captions).
    var plated = true

    @ScaledMetric(relativeTo: .caption) private var plate: CGFloat = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(modes.enumerated()), id: \.offset) { index, mode in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Image(systemName: mode.symbolName)
                    .font(font)
                    .foregroundStyle(plated ? Theme.onAccent : Theme.modeColor(mode))
                    .frame(width: plated ? plate : nil, height: plated ? plate : nil)
                    .background {
                        if plated {
                            RoundedRectangle(cornerRadius: plate * 0.3, style: .continuous)
                                .fill(Theme.modeColor(mode).gradient)
                        }
                    }
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

@MainActor
enum TripJourneyFormat {
    /// "3 Etappen"
    static func legCount(_ count: Int) -> String { count == 1 ? "1 Etappe" : "\(count) Etappen" }

    /// "Bus, Zug und Bim" (VoiceOver, captions).
    static func modeList(_ modes: [TransportMode]) -> String {
        let names = modes.map(\.displayName)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " und " + (names.last ?? "")
    }

    /// "umsteigen in Langen am Arlberg und Wien Hbf" – the transfer stops, spoken.
    static func transfers(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let shown = names.map { TripRow.short($0) }
        let list = shown.count > 1 ? shown.dropLast().joined(separator: ", ") + " und " + (shown.last ?? "") : shown[0]
        return "umsteigen in " + list
    }
}
