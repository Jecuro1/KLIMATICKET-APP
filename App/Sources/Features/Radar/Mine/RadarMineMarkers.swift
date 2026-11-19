import SwiftUI
import KlimaCore

// MARK: radar2-radarmine – the small views of „Meine Fahrzeuge“ on the map and in the top bar (docs/RADAR_MINE.md §9): the chip „Meine“, the stop of
// „Wo bleibt mein Bus?“, a numbered arrival whose position comes from the board (dashed outline: not the radar's marker), and the dot of the invented
// place in demo scenes. Colours from Theme tokens only; the gold star and the numbers sit on white so they read on light, dark and the „Dunkel“ map.

/// „Meine“ at the start of the mode chips: gold while your lines are highlighted.
struct RadarMineChip: View {
    var mine: RadarMineModel
    var action: () -> Void

    var body: some View {
        Chip(title: RadarMineText.chip, symbol: mine.highlightOn ? "star.fill" : RadarMineText.chipSymbol,
             isSelected: mine.isOpen || mine.highlightOn, tint: mine.highlightOn ? Theme.gold : Theme.accent, action: action)
            .accessibilityLabel(RadarMineText.chipSpoken)
            .accessibilityValue(mine.isOpen ? "offen" : (mine.highlightOn ? "deine Linien hervorgehoben" : ""))
            .accessibilityHint(mine.isOpen ? "Schließt die Ansicht" : "Öffnet Linien, In der Nähe und Haltestelle")
            .haptic(.selection, trigger: mine.isOpen)
    }
}

/// The stop of the stop page: its name on a glass capsule over a dot with the bus glyph.
struct RadarMineStopMarker: View {
    var name: String

    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
            Image(systemName: "bus.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.snow)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: .circle)
                .overlay(Circle().strokeBorder(Theme.snow, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Haltestelle \(name)")
    }
}

/// A numbered arrival drawn from the board's position: a small circle in the mode's colour with its number, a dashed white outline (the position
/// is the board's, not a radar marker). Grey when the position is older than two minutes.
struct RadarMineBoardPin: View {
    var number: Int
    var mode: TransportMode
    var isStale: Bool

    var body: some View {
        Text(verbatim: String(number))
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.snow)
            .frame(width: 24, height: 24)
            .background(isStale ? Theme.textTertiary : Theme.modeColor(mode), in: .circle)
            .overlay(Circle().strokeBorder(Theme.snow, style: StrokeStyle(lineWidth: 2, dash: [3, 2])))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(.circle)
    }
}

/// The invented place of the demo scenes, in the look of the system's location dot.
struct RadarMineUserDot: View {
    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Theme.snow, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .accessibilityLabel(RadarMineText.demoPlace)
    }
}

/// The number of an arrival in its row, in the look of its map pin.
struct RadarMineNumberBadge: View {
    var number: Int
    var mode: TransportMode
    var fromBoard: Bool

    var body: some View {
        Text(verbatim: String(number))
            .font(.caption.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(fromBoard ? Theme.snow : Theme.textPrimary)
            .frame(minWidth: 20, minHeight: 20)
            .background(fromBoard ? Theme.modeColor(mode) : Theme.gold, in: .circle)
            .overlay {
                if fromBoard { Circle().strokeBorder(Theme.snow, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])) }
            }
            .accessibilityHidden(true)
    }
}
