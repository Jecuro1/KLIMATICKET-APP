import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Filter

/// Purpose filter of the trip list (in addition to the mode chips).
enum MetaTripFilter: Hashable {
    case all
    case category(TripCategory)
    case uncategorized
    /// "Ohne KlimaTicket wäre ich nicht gefahren".
    case induced

    func matches(_ trip: TripEntity) -> Bool {
        switch self {
        case .all: true
        case .category(let category): trip.categoryRaw == category.rawValue
        case .uncategorized: trip.categoryRaw.isEmpty
        case .induced: trip.isInduced
        }
    }

    var isActive: Bool { self != .all }

    var title: String {
        switch self {
        case .all: "Kategorie"
        case .category(let category): category.displayName
        case .uncategorized: "Ohne Kategorie"
        case .induced: "Mehrwert-Fahrten"
        }
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .category(let category): category.symbolName
        case .uncategorized: "circle.dashed"
        case .induced: MetaCategoryStyle.inducedSymbol
        }
    }

    var tint: Color {
        switch self {
        case .all: Theme.textSecondary
        case .category(let category): MetaCategoryStyle.color(category)
        case .uncategorized: Theme.textSecondary
        case .induced: MetaCategoryStyle.inducedColor
        }
    }

    /// " mit Arbeitsweg" etc. for the "nothing found" message.
    var resultPhrase: String {
        switch self {
        case .all: ""
        case .category(let category): " der Kategorie „\(category.displayName)“"
        case .uncategorized: " ohne Kategorie"
        case .induced: ", die du ohne KlimaTicket nicht gemacht hättest,"
        }
    }
}

/// Counts per purpose of the trips in the selected period (menu entries with numbers).
struct MetaTripFilterCounts {
    struct Entry: Identifiable {
        let category: TripCategory
        let count: Int
        var id: String { category.rawValue }
    }

    var byCategory: [Entry]
    var uncategorized: Int
    var induced: Int

    init(trips: [TripEntity]) {
        var counts: [String: Int] = [:]
        var uncategorized = 0, induced = 0
        for trip in trips {
            if trip.categoryRaw.isEmpty { uncategorized += 1 } else { counts[trip.categoryRaw, default: 0] += 1 }
            if trip.isInduced { induced += 1 }
        }
        byCategory = TripCategory.allCases.compactMap { category in
            counts[category.rawValue].map { Entry(category: category, count: $0) }
        }
        self.uncategorized = uncategorized
        self.induced = induced
    }

    /// Worth showing the menu: at least one trip has a purpose or is marked as extra value.
    var hasPurposes: Bool { !byCategory.isEmpty || induced > 0 }
}

// MARK: - Filter chip (menu)

/// Leading glass chip of the filter row: "⚲ Kategorie ⌄", or the active purpose ("💼 Arbeitsweg ⌄") tinted.
struct MetaCategoryFilterMenu: View {
    @Binding var selection: MetaTripFilter
    let counts: MetaTripFilterCounts

    var body: some View {
        Menu {
            Picker("Kategorie", selection: $selection) {
                Label("Alle Kategorien", systemImage: "square.grid.2x2")
                    .tag(MetaTripFilter.all)
                Section("Kategorien") {
                    ForEach(counts.byCategory) { entry in
                        Label("\(entry.category.displayName) · \(entry.count)", systemImage: entry.category.symbolName)
                            .tag(MetaTripFilter.category(entry.category))
                    }
                    if counts.uncategorized > 0 {
                        Label("Ohne Kategorie · \(counts.uncategorized)", systemImage: "circle.dashed")
                            .tag(MetaTripFilter.uncategorized)
                    }
                }
                if counts.induced > 0 {
                    Section("Ehrliche Bilanz") {
                        Label("Mehrwert-Fahrten · \(counts.induced)", systemImage: MetaCategoryStyle.inducedSymbol)
                            .tag(MetaTripFilter.induced)
                    }
                }
            }
        } label: {
            chipLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .glassEffect(selection.isActive ? .regular.tint(selection.tint.opacity(0.22)).interactive() : .regular.interactive(),
                     in: .capsule)
        .accessibilityLabel("Nach Kategorie filtern")
        .accessibilityValue(selection.isActive ? selection.title : "Alle Kategorien")
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: selection.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selection.isActive ? selection.tint : Theme.textPrimary)
            Text(selection.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay {
            if selection.isActive {
                Capsule().strokeBorder(selection.tint.opacity(0.55), lineWidth: 1)
            }
        }
        .contentShape(.capsule)
    }
}

// MARK: - Row glyphs

/// Subtle purpose marks in a trip row: the purpose symbol in its colour, ✨ for extra-value trips.
struct MetaTripRowPurpose: View {
    var category: TripCategory?
    var isInduced: Bool

    var body: some View {
        if category != nil || isInduced {
            HStack(spacing: 3) {
                if isInduced {
                    Image(systemName: MetaCategoryStyle.inducedSymbol)
                        .foregroundStyle(MetaCategoryStyle.inducedColor)
                }
                if let category {
                    Image(systemName: category.symbolName)
                        .foregroundStyle(MetaCategoryStyle.color(category))
                }
            }
            .font(.caption.weight(.semibold))
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Quick purpose menu (context menu of a trip)

/// "Kategorie" submenu: set or clear the purpose and toggle "Ohne KlimaTicket nicht gefahren" without opening the editor.
struct MetaTripPurposeMenu: View {
    let trip: TripEntity
    var onChange: (_ category: TripCategory?, _ isInduced: Bool) -> Void

    var body: some View {
        Menu {
            Picker("Kategorie", selection: categoryBinding) {
                ForEach(TripCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.symbolName)
                        .tag(Optional(category))
                }
                Label("Ohne Kategorie", systemImage: "circle.dashed")
                    .tag(TripCategory?.none)
            }
            Divider()
            Toggle(isOn: inducedBinding) {
                Label("Ohne KlimaTicket nicht gefahren", systemImage: MetaCategoryStyle.inducedSymbol)
            }
        } label: {
            Label(trip.category.map { "Kategorie: \($0.displayName)" } ?? "Kategorie", systemImage: "tag")
        }
    }

    private var categoryBinding: Binding<TripCategory?> {
        Binding(get: { trip.category }, set: { onChange($0, trip.isInduced) })
    }

    private var inducedBinding: Binding<Bool> {
        Binding(get: { trip.isInduced }, set: { onChange(trip.category, $0) })
    }
}
