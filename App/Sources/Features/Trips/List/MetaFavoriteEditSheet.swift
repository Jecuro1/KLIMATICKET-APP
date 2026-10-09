import SwiftUI
import SwiftData
import KlimaCore

/// "Favorit bearbeiten": short name and purpose of a favourite. Trips logged from it (overview, widget, Siri)
/// carry that purpose, so quick logs land in the right category without opening the editor.
struct MetaFavoriteEditSheet: View {
    let favorite: FavoriteRouteEntity

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title: String
    @State private var category: TripCategory?
    @State private var tapTick = 0
    @FocusState private var isNameFocused: Bool

    init(favorite: FavoriteRouteEntity) {
        self.favorite = favorite
        _title = State(initialValue: favorite.title)
        _category = State(initialValue: TripCategory(rawValue: favorite.categoryRaw))
    }

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    routeCard
                    nameSection
                    categorySection
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { MetaSheetBackdrop() }
            .navigationTitle("Favorit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .accessibilityLabel("Sichern")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: tapTick) { _, _ in haptics }
    }

    // MARK: Sections

    private var routeCard: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: favorite.mode, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(TripListFormat.routeTitle(favorite.fromName, favorite.toName, roundTrip: favorite.isRoundTrip))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                ViaCaption(vias: favorite.via, font: .subheadline)   // MARK: via
                Text(routeMeta)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.formGroup, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var routeMeta: String {
        let value = favorite.fareEUR * (favorite.isRoundTrip ? 2 : 1)
        var parts = [favorite.mode.displayName, "\(Format.euroPrecise(value)) je Fahrt"]
        if favorite.usageCount > 0 { parts.append("\(favorite.usageCount)× genutzt") }
        return parts.joined(separator: " · ")
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Kicker(text: "Name")
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            HStack(spacing: Theme.Spacing.s) {
                TripEdIconTile(symbol: "character.cursor.ibeam", tint: Theme.glacier)
                TextField("z. B. Arbeit", text: $title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                if !title.isEmpty {
                    Button {
                        title = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Name löschen")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 10)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.formGroup, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.formGroup, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            }
            Text("Kurz für Schnellerfassung und Widget. Leer lassen, um die Strecke anzuzeigen.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Kategorie")
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.Spacing.xs)
                Text(category == nil ? "Optional" : "Tippen zum Entfernen")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            GlassEffectContainer(spacing: Theme.Spacing.xs) {
                MetaFlowLayout(spacing: Theme.Spacing.xs, lineSpacing: 10) {
                    ForEach(TripCategory.allCases) { item in
                        MetaCategoryChip(category: item, isSelected: category == item) {
                            select(item)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kategorie")
            Label {
                Text("Fahrten aus Schnellerfassung, Widget und Siri bekommen diese Kategorie – so stimmt deine Statistik „Wofür du fährst“ ohne Extra-Tipp.")
            } icon: {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.gold)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
        }
    }

    // MARK: Actions

    private func select(_ item: TripCategory) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3, extraBounce: 0.06)) {
            category = category == item ? nil : item
        }
        tapTick += 1
    }

    private func save() {
        isNameFocused = false
        Repository(context: context, app: app).metaUpdateFavorite(favorite, title: title, category: category)
        let subtitle = category.map { "\(favorite.displayTitle) · \($0.displayName)" } ?? favorite.displayTitle
        app.showToast("star.circle.fill", "Favorit gesichert", subtitle)
        dismiss()
    }
}

/// Calm sheet surface with a faint "Morgendämmerung" wash (DESIGN.md §2); opaque with Reduce Transparency.
struct MetaSheetBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.sheetBackground
            if !reduceTransparency {
                LinearGradient(colors: [Theme.glacier.opacity(colorScheme == .dark ? 0.16 : 0.12), Theme.glacier.opacity(0)],
                               startPoint: .top, endPoint: .center)
                RadialGradient(colors: [Theme.dawn.opacity(colorScheme == .dark ? 0.12 : 0.16), Theme.dawn.opacity(0)],
                               center: .topTrailing, startRadius: 0, endRadius: 380)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
