import SwiftUI
import KlimaCore

// Via stops ("Über …", Zwischenhalte) wherever a route is shown – docs/VIA.md §5. One wording everywhere:
// "über Feldkirch", "über Landeck-Zams und Feldkirch"; round trips come back in reverse order.

@MainActor
enum ViaText {
    /// "über Feldkirch", "über Landeck-Zams und Feldkirch" (short names like the rows: "Hbf", no "am Arlberg"); nil without vias.
    static func subtitle(_ vias: [TripVia]) -> String? { subtitle(names: vias.map(\.name)) }

    static func subtitle(names: [String]) -> String? {
        let names = names.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return "über " + FareEstimator.viaList(names.map(TripRow.short))
    }

    /// The return leg of a round trip passes the vias in reverse: "zurück über Feldkirch und Landeck-Zams".
    static func returnSubtitle(_ vias: [TripVia]) -> String? {
        subtitle(names: vias.reversed().map(\.name)).map { "zurück " + $0 }
    }

    /// "Innsbruck Hbf → Feldkirch → Bregenz" (short names).
    static func chain(from: String, via: [TripVia], to: String) -> String {
        ([from] + via.map(\.name) + [to]).map(TripRow.short).joined(separator: " → ")
    }

    /// For VoiceOver: "Innsbruck Hauptbahnhof über Feldkirch nach Bregenz".
    static func spoken(from: String, via: [TripVia], to: String) -> String {
        guard !via.isEmpty else { return "\(from) nach \(to)" }
        return "\(from) über \(FareEstimator.viaList(via.map(\.name))) nach \(to)"
    }
}

/// "über Feldkirch" caption under a route – a small dot on a line, then the text. Hidden without vias.
struct ViaCaption: View {
    var vias: [TripVia]
    var font: Font = .caption
    var color: Color = Theme.textSecondary

    var body: some View {
        if let text = ViaText.subtitle(vias) {
            HStack(spacing: 5) {
                ViaGlyph(color: color)
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        }
    }
}

/// Tiny via mark (a stop on a line) for tight places – pills, chips – where "über …" does not fit.
struct ViaGlyph: View {
    var color: Color = Theme.textSecondary
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 10

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.45))
                .frame(width: size * 1.3, height: 1.5)
            Circle()
                .fill(color)
                .frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size * 1.3, height: size)
        .accessibilityHidden(true)
    }
}

/// Route pill text that degrades gracefully: "Innsbruck Hbf → Bregenz · über Feldkirch" when it fits, else the route
/// with the via glyph, else the plain route.
struct ViaRouteLabel: View {
    var route: String
    var vias: [TripVia]
    var font: Font = .subheadline.weight(.semibold)
    var color: Color = Theme.textPrimary

    var body: some View {
        if let via = ViaText.subtitle(vias) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(route).foregroundStyle(color)
                    Text(via).foregroundStyle(Theme.textSecondary).font(.caption)
                }
                HStack(spacing: 5) {
                    Text(route).foregroundStyle(color)
                    ViaGlyph(color: Theme.textSecondary)
                }
                Text(route).foregroundStyle(color)
            }
            .font(font)
            .lineLimit(1)
        } else {
            Text(route)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}
