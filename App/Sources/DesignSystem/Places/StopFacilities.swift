import KlimaCore
import SwiftUI

// MARK: stops – Ausstattung (docs/ENRICH_SPEC.md §1.11): what OpenStreetMap records about a stop, as an icon grid
// and as route chips. The wording and the status rules live in KlimaCore (`FacilityPresentation`); this file only draws.

/// „Ausstattung“ of the stop detail: one tile per facility with its status, and the ODbL source line.
struct StopFacilitiesSection: View {
    let facilities: [StopFacility]
    var buildDate: Date?

    var body: some View {
        let rows = FacilityPresentation.rows(facilities)
        VStack(alignment: .leading, spacing: 10) {
            StopSectionTitle(text: "Ausstattung")
            SurfaceCard(padding: 16, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 16) {
                        ForEach(rows) { FacilityTile(row: $0) }
                    }
                    Text(FacilityPresentation.sourceLine(buildDate: buildDate))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One facility: symbol, German label, what OSM says. „nicht erfasst“ is drawn hollow, never as a cross.
struct FacilityTile: View {
    let row: FacilityRow

    private var tint: Color {
        switch row.tone {
        case .positive: Theme.pine
        case .negative: Theme.textSecondary
        case .neutral: Theme.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle().fill(row.tone == .positive ? Theme.pine.opacity(0.16) : Theme.surfaceSecondary)
                if row.tone == .neutral {
                    Circle().strokeBorder(Theme.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                Image(systemName: row.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            Text(row.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.statusText)
                .font(.caption2)
                .foregroundStyle(row.tone == .neutral ? Theme.textTertiary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = row.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// Route card meta row: icon chips for the stop's facilities that OSM says are there, at most
/// `FacilityPresentation.routeChipLimit` (3).
struct FacilityRouteChips: View {
    let facilities: [StopFacility]

    var body: some View {
        let chips = FacilityPresentation.routeChips(facilities)
        HStack(spacing: 4) {
            ForEach(chips) { row in
                Image(systemName: row.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.pine)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.pine.opacity(0.14)))
                    .accessibilityElement()
                    .accessibilityLabel(row.accessibilityLabel)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
