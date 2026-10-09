import SwiftUI
import KlimaCore

// "Kategorien & ehrliche Bilanz" – shared look of trip purposes (editor, list, favourites, statistics).
// Everything non-private is prefixed `Meta` to stay collision-free with modules written in parallel.

/// Colour, wording and symbols of a trip purpose. `nil` = "Ohne Kategorie".
/// Colours come from the Alpine palette; they are only used for symbols and fills – text stays in the text tokens.
enum MetaCategoryStyle {
    static func color(_ category: TripCategory?) -> Color {
        switch category {
        case .commute: Theme.glacier
        case .business: Theme.dusk
        case .education: Theme.modeColor(.sBahn)   // Bergsee
        case .leisure: Theme.pine
        case .holiday: Theme.dawn
        case .visit: Theme.alpenglow
        case .errand: Theme.gold
        case .other: Theme.modeColor(.other)
        case nil: Theme.textTertiary
        }
    }

    static func name(_ category: TripCategory?) -> String { category?.displayName ?? "Ohne Kategorie" }

    static func symbol(_ category: TripCategory?) -> String { category?.symbolName ?? "circle.dashed" }

    /// "… deines Werts auf dem Arbeitsweg" / "… deiner Fahrten in der Freizeit".
    static func phrase(_ category: TripCategory?) -> String {
        switch category {
        case .commute: "auf dem Arbeitsweg"
        case .business: "auf Dienstreisen"
        case .education: "für die Ausbildung"
        case .leisure: "in der Freizeit"
        case .holiday: "im Urlaub"
        case .visit: "bei Besuchen"
        case .errand: "für Erledigungen"
        case .other: "für Sonstiges"
        case nil: "ohne Kategorie"
        }
    }

    /// Symbol + wording for trips marked "Ohne KlimaTicket wäre ich nicht gefahren".
    static let inducedSymbol = "sparkles"
    static let inducedTitle = "Mehrwert-Fahrt"
    static var inducedColor: Color { Theme.gold }
}

// MARK: - Icon tile

/// Rounded square with the purpose symbol on its colour (like `ModeIcon`); dashed outline for "Ohne Kategorie".
struct MetaCategoryIcon: View {
    var category: TripCategory?
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
        let color = MetaCategoryStyle.color(category)
        Image(systemName: MetaCategoryStyle.symbol(category))
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(category == nil ? Theme.textSecondary : Theme.onAccent)
            .frame(width: size, height: size)
            .background {
                if category == nil {
                    shape.fill(Theme.surfaceSecondary)
                        .overlay { shape.strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])) }
                } else {
                    shape.fill(LinearGradient(colors: [color, color.mix(with: .black, by: 0.2)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// Liquid Glass capsule with the purpose symbol (in its colour) and name. Tinted and outlined when selected.
struct MetaCategoryChip: View {
    var category: TripCategory
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        let color = MetaCategoryStyle.color(category)
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? color : Theme.textSecondary)
                    .symbolEffect(.bounce, value: isSelected)
                Text(category.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(color.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Tippen entfernt die Kategorie" : "")
    }
}

// MARK: - Pill

/// Calm capsule label "💼 Arbeitsweg" / "✨ Mehrwert-Fahrt" (trip detail).
struct MetaCategoryPill: View {
    var title: String
    var symbol: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.16), in: .capsule)
        .overlay { Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flow layout

/// Left-aligned wrapping layout for chips (favourite editor).
struct MetaFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
