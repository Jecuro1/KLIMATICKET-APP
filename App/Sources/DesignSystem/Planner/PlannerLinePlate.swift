import SwiftUI
import KlimaCore

/// Live lines wear the same Wegzeichen plates as the offline stop details (docs/ENRICH_SPEC.md D7): the plate text comes
/// from `LinePresentation.plate` (which delegates to `LinePlateText`), the look from `Shared/Wegzeichen`.
extension LineBadge {
    /// The badge of a live line („RJX“, „S4“, „760“, „T 3“ → plate „3“) with its VoiceOver title („RJX 19910“, „Bus 760“).
    init(line: Line, size: PlateSize = .s) {
        let plate = LinePresentation.plate(line, size: size.textSize)
        self.init(kind: LinePresentation.kind(line), text: plate.text, glyph: plate.glyph.map { .symbol($0.symbolName) },
                  spoken: LinePresentation.title(line))
    }

    /// The badge of a departure-board row.
    init(row: BoardRow) {
        self.init(kind: row.lineKind, text: row.plate, glyph: row.plateGlyph.map { .symbol($0.symbolName) }, spoken: row.lineTitle)
    }
}

/// A live line plate in a given size.
struct PlannerLinePlate: View {
    var badge: LineBadge
    var size: PlateSize = .m

    init(line: Line, size: PlateSize = .m) {
        badge = LineBadge(line: line, size: size)
        self.size = size
    }

    init(row: BoardRow, size: PlateSize = .m) {
        badge = LineBadge(row: row)
        self.size = size
    }

    init(badge: LineBadge, size: PlateSize = .m) {
        self.badge = badge
        self.size = size
    }

    var body: some View { LinePlate(badge, size: size) }
}

/// Palette helpers of the Fahrplan that are not plates.
enum PlannerPalette {
    /// Stroke colour of a leg on the map and the timeline rail (lighter in dark mode).
    static func stroke(for mode: TransportMode) -> Color { Theme.modeColor(mode) }
}
