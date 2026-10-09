import SwiftUI
import SwiftData
import KlimaCore

/// Favoriten verwalten: reorder (Bearbeiten), edit name & purpose, delete, usage counts and value per use.
/// Pushed inside an existing NavigationStack (Fahrten, Einstellungen, …).
struct FavoritesManagerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    /// Favourite in the "Favorit bearbeiten" sheet (name + purpose).
    @State private var editTarget: FavoriteRouteEntity?
    @State private var successTick = 0
    @State private var warningTick = 0
    /// Captured on first appearance (see `backdrop`).
    @State private var isInSettingsSheet: Bool?

    var body: some View {
        List {
            if favorites.isEmpty {
                emptySection
            } else {
                favoritesSection
            }
            addSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .background { backdrop }
        .onAppear {
            if isInSettingsSheet == nil { isInSettingsSheet = app.isShowingSettings }
        }
        .navigationTitle("Favoriten")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(favorites.isEmpty)
            }
        }
        .sheet(item: $editTarget) { favorite in
            MetaFavoriteEditSheet(favorite: favorite)
        }
        .task {
            // CI screenshot "favoriteEdit": open the editor of the first favourite.
            guard LaunchMode.screenshotScreen == "favoriteEdit", editTarget == nil else { return }
            try? await Task.sleep(for: .milliseconds(600))
            editTarget = favorites.first
        }
        .sensoryFeedback(.success, trigger: successTick, condition: { _, _ in hapticsEnabled })
        .sensoryFeedback(.warning, trigger: warningTick, condition: { _, _ in hapticsEnabled })
    }

    // MARK: Sections

    private var favoritesSection: some View {
        Section {
            ForEach(favorites) { favorite in
                favoriteRow(favorite)
            }
            .onMove(perform: moveFavorites)
            .onDelete(perform: deleteFavorites)
        } header: {
            Kicker(text: headerText)
                .textCase(nil)
        } footer: {
            Text("Die ersten Favoriten erscheinen in der Schnellerfassung, im Widget und bei Siri. Mit „Bearbeiten“ änderst du die Reihenfolge.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func favoriteRow(_ favorite: FavoriteRouteEntity) -> some View {
        TripListFavoriteRow(favorite: favorite, onEdit: { beginEdit(favorite) }) {
            log(favorite)
        }
        .listRowBackground(TripListCardBackground())
        .listRowSeparatorTint(Theme.separator)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(favorite)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                beginEdit(favorite)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            Button { log(favorite) } label: { Label("Jetzt erfassen", systemImage: "plus.circle") }
            Button { openInEditor(favorite) } label: { Label("Mit Anpassungen erfassen", systemImage: "square.and.pencil") }
            Button { beginEdit(favorite) } label: { Label("Name & Kategorie", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { delete(favorite) } label: { Label("Löschen", systemImage: "trash") }
        }
    }

    private var emptySection: some View {
        Section {
            EmptyStateView(symbol: "star",
                           title: "Noch keine Favoriten",
                           message: "Speichere Strecken, die du oft fährst – dann erfasst du sie mit einem Tipp, im Widget oder per Siri.")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var addSection: some View {
        Section {
            Button {
                presentEditor()
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 34, height: 34)
                        .background(Theme.ctaGradient, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Neuen Favoriten anlegen")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Erfasse eine Fahrt und aktiviere „Als Favorit speichern“.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .contentShape(Rectangle())
            }
            .listRowBackground(TripListCardBackground())
        } footer: {
            Text("Oder wische in der Fahrtenliste eine Fahrt nach rechts und tippe auf „Favorit“.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Inside the Settings sheet a calm surface with a pale sky (DESIGN.md §2 – no full sky mesh in sheets),
    /// otherwise the alpine sky. Frozen on first appearance so it does not flip while the sheet closes for the editor.
    @ViewBuilder
    private var backdrop: some View {
        if isInSettingsSheet ?? app.isShowingSettings {
            ZStack(alignment: .top) {
                Theme.sheetBackground
                AmbientBackground(style: .standard, glow: 0.6)
                    .opacity(0.55)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black.opacity(0.65), location: 0.22),
                                               .init(color: .clear, location: 0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            AmbientBackground()
        }
    }

    private var headerText: String {
        let uses = favorites.reduce(0) { $0 + $1.usageCount }
        let count = favorites.count == 1 ? "1 Favorit" : "\(favorites.count) Favoriten"
        return "\(count) · \(uses)× genutzt"
    }

    // MARK: Actions

    private var hapticsEnabled: Bool { app.settings.hapticsEnabled }

    private func log(_ favorite: FavoriteRouteEntity) {
        TripListActions(app: app, context: context).log(favorite)
        successTick += 1
    }

    private func openInEditor(_ favorite: FavoriteRouteEntity) {
        let draft = TripDraft(fromStationID: favorite.fromStationID, toStationID: favorite.toStationID,
                              fromName: favorite.fromName, toName: favorite.toName, mode: favorite.mode,
                              isRoundTrip: favorite.isRoundTrip)
        presentEditor(draft)
    }

    /// The add-trip sheet is presented from RootView – when this screen lives inside the Settings sheet,
    /// close that first (SwiftUI shows only one sheet at a time).
    private func presentEditor(_ draft: TripDraft = TripDraft()) {
        guard app.isShowingSettings else {
            app.presentAddTrip(draft)
            return
        }
        app.isShowingSettings = false
        let appState = app
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            appState.presentAddTrip(draft)
        }
    }

    private func beginEdit(_ favorite: FavoriteRouteEntity) {
        editTarget = favorite
    }

    private func delete(_ favorite: FavoriteRouteEntity) {
        let title = favorite.displayTitle
        withAnimation(.snappy) {
            Repository(context: context, app: app).deleteFavorite(favorite)
        }
        app.showToast("trash.fill", "Favorit gelöscht", title)
        warningTick += 1
    }

    private func deleteFavorites(at offsets: IndexSet) {
        let items = offsets.map { favorites[$0] }
        let repository = Repository(context: context, app: app)
        withAnimation(.snappy) {
            for item in items { repository.deleteFavorite(item) }
        }
        warningTick += 1
    }

    /// Persists the new order as consecutive sortIndex values (touch() keeps sync last-writer-wins correct).
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        var ordered = favorites
        ordered.move(fromOffsets: source, toOffset: destination)
        var changed = false
        for (index, favorite) in ordered.enumerated() where favorite.sortIndex != index {
            favorite.sortIndex = index
            favorite.touch()
            changed = true
        }
        if changed { Repository(context: context, app: app).commit() }
    }
}

// MARK: - Row

/// Mode icon · name + plaque · route · "12× genutzt · € 47,00 je Fahrt" · round "+" (one tap = logged).
private struct TripListFavoriteRow: View {
    let favorite: FavoriteRouteEntity
    var onEdit: () -> Void = {}
    let onLog: () -> Void

    @Environment(\.editMode) private var editMode

    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }
    private var valuePerUse: Double { favorite.fareEUR * (favorite.isRoundTrip ? 2 : 1) }
    private var hasCustomTitle: Bool { !favorite.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ModeIcon(mode: favorite.mode, size: 42)
                details
                Spacer(minLength: Theme.Spacing.xs)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isEditing { onEdit() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(spokenMeta)
            .accessibilityHint(isEditing ? "" : "Öffnet Name und Kategorie")
            .accessibilityAddTraits(isEditing ? [] : .isButton)
            .accessibilityAction { if !isEditing { onEdit() } }

            if !isEditing {
                Button(action: onLog) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(favorite.displayTitle) jetzt erfassen")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .animation(.snappy, value: isEditing)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(hasCustomTitle ? favorite.title : TripListFormat.routeTitle(favorite.fromName, favorite.toName, roundTrip: favorite.isRoundTrip))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let badge = TripListFormat.badge(for: favorite.mode) {
                    TripListModeBadge(text: badge)
                }
            }
            if hasCustomTitle {
                Text(TripListFormat.routeTitle(favorite.fromName, favorite.toName, roundTrip: favorite.isRoundTrip))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            metaLine
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }

    private var category: TripCategory? { TripCategory(rawValue: favorite.categoryRaw) }

    /// "💼 Arbeitsweg · 12× genutzt · € 47,00 je Fahrt" (purpose symbol in its colour).
    private var metaLine: Text {
        guard let category else { return Text(meta) }
        let symbol = Text(Image(systemName: category.symbolName)).foregroundStyle(MetaCategoryStyle.color(category))
        return Text("\(symbol) \(category.displayName) · \(meta)")
    }

    private var meta: String {
        let usage = favorite.usageCount == 0 ? "Noch nicht genutzt" : "\(favorite.usageCount)× genutzt"
        return "\(usage) · \(Format.euroPrecise(valuePerUse)) je Fahrt"
    }

    private var spokenMeta: String {
        guard let category else { return meta }
        return "\(category.displayName), \(meta)"
    }

    private var accessibilityLabel: String {
        let route = "\(favorite.fromName) nach \(favorite.toName), \(favorite.mode.displayName)\(favorite.isRoundTrip ? ", hin und retour" : "")"
        return hasCustomTitle ? "\(favorite.title): \(route)" : route
    }
}
