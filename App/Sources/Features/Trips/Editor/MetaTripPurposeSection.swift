import SwiftUI
import SwiftData
import KlimaCore

/// Where a preselected purpose in the trip editor came from.
enum MetaCategorySource: Equatable {
    /// Most recent trip on the same route.
    case route
    /// The favourite whose route is in the form.
    case favorite
}

// MARK: - Model helpers

extension TripEditorModel {
    /// Changes whenever the inputs of the purpose suggestion change (route, mode, direction).
    var metaSuggestionKey: String {
        "\(resolvedFromName.lowercased())|\(resolvedToName.lowercased())|\(mode.rawValue)|\(isRoundTrip)"
    }

    /// Chip tap: selects the purpose, or clears it when it is already selected.
    func metaSelect(_ tapped: TripCategory) {
        category = category == tapped ? nil : tapped
        categorySource = nil
        categoryWasChosen = true
    }

    /// Preselects the purpose of a matching favourite, otherwise of the most recent trip on the same route
    /// (as a visible, deselectable suggestion). Never overrides a choice the user made.
    func metaApplySuggestion(favorites: [FavoriteRouteEntity], trips: [TripEntity]) {
        guard !categoryWasChosen else { return }
        if let favorite = favorites.first(where: { tripEdMatches($0) }),
           let favoriteCategory = TripCategory(rawValue: favorite.categoryRaw) {
            category = favoriteCategory
            categorySource = .favorite
            return
        }
        let records = trips.filter { !$0.categoryRaw.isEmpty && $0.deletedAt == nil }.map(\.record)
        if let suggestion = CategoryStats.suggestedCategory(fromName: resolvedFromName, toName: resolvedToName,
                                                            in: records, excludingID: editingTrip?.id) {
            category = suggestion
            categorySource = .route
        } else if categorySource != nil {
            // The previous suggestion belonged to another route.
            category = nil
            categorySource = nil
        }
    }
}

// MARK: - Section

/// "Wofür warst du unterwegs?": optional purpose as horizontal Liquid Glass chips (deselectable, suggested from the
/// route's last trip or the favourite) and the honest-balance switch "Ohne KlimaTicket wäre ich nicht gefahren".
struct MetaTripPurposeSection: View {
    let model: TripEditorModel

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapTick = 0

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, Theme.Spacing.screen)
            chips
            inducedCard
                .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .padding(.top, 6)
        .sensoryFeedback(.selection, trigger: tapTick) { _, _ in haptics }
        .metaScreenshotScrollTarget("addTripCategory")
    }

    // MARK: Header

    private var header: some View {
        // One line when it fits; kicker above the hint at large Dynamic Type sizes.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                kicker
                Spacer(minLength: Theme.Spacing.xs)
                hint
                    .fixedSize()
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                kicker
                hint
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.categorySource)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.category)
    }

    private var kicker: some View {
        Kicker(text: "Wofür unterwegs?")
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var hint: some View {
        switch model.categorySource {
        case .route?:
            Label("Wie zuletzt", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Vorschlag: wie zuletzt auf dieser Strecke")
        case .favorite?:
            Label {
                Text("Vom Favoriten")
            } icon: {
                Image(systemName: "star.fill").foregroundStyle(Theme.gold)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Vorschlag vom Favoriten")
        case nil:
            if model.category == nil {
                Text("Optional")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Chips

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(TripCategory.allCases) { category in
                            MetaCategoryChip(category: category, isSelected: model.category == category) {
                                select(category)
                            }
                            .id(category)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
            .scrollClipDisabled()
            .onAppear { reveal(model.category, in: proxy, animated: false) }
            .onChange(of: model.category) { _, newValue in reveal(newValue, in: proxy, animated: true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kategorie")
    }

    /// Keeps a selected purpose further right (Urlaub, Besuch …) in view.
    private func reveal(_ category: TripCategory?, in proxy: ScrollViewProxy, animated: Bool) {
        guard let category, let index = TripCategory.allCases.firstIndex(of: category), index > 2 else { return }
        if animated && !reduceMotion {
            withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(category, anchor: .center) }
        } else {
            proxy.scrollTo(category, anchor: .center)
        }
    }

    private func select(_ category: TripCategory) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3, extraBounce: 0.06)) {
            model.metaSelect(category)
        }
        tapTick += 1
    }

    // MARK: Honest balance switch

    private var inducedCard: some View {
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            Toggle(isOn: inducedBinding) {
                TripEdRowLabel(symbol: MetaCategoryStyle.inducedSymbol, tint: MetaCategoryStyle.inducedColor,
                               title: "Ohne KlimaTicket wäre ich nicht gefahren",
                               subtitle: "Zählt als Mehrwert statt Ersparnis")
            }
            .tint(Theme.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
            .accessibilityHint("Die Fahrt zählt dann in der ehrlichen Bilanz als Mehrwert, nicht als echte Ersparnis.")
        }
    }

    private var inducedBinding: Binding<Bool> {
        Binding(
            get: { model.isInduced },
            set: { isOn in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { model.isInduced = isOn }
                tapTick += 1
            }
        )
    }
}
