import SwiftUI
import SwiftData
import KlimaCore

/// Favoriten verwalten: reorder (Bearbeiten), rename, delete, usage counts and value per use.
/// Pushed inside an existing NavigationStack (Fahrten, Einstellungen, …).
struct FavoritesManagerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var renameTarget: FavoriteRouteEntity?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var successTick = 0
    @State private var warningTick = 0

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
        .ambientBackground()
        .navigationTitle("Favoriten")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(favorites.isEmpty)
            }
        }
        .alert("Favorit umbenennen", isPresented: $isRenaming) {
            TextField("Name, z. B. Arbeit", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Sichern") { applyRename() }
            Button("Abbrechen", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Ein kurzer Name für Schnellerfassung und Widget. Leer lassen, um die Strecke anzuzeigen.")
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
        TripListFavoriteRow(favorite: favorite) {
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
                beginRename(favorite)
            } label: {
                Label("Umbenennen", systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            Button { log(favorite) } label: { Label("Jetzt erfassen", systemImage: "plus.circle") }
            Button { openInEditor(favorite) } label: { Label("Mit Anpassungen erfassen", systemImage: "square.and.pencil") }
            Button { beginRename(favorite) } label: { Label("Umbenennen", systemImage: "pencil") }
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

    private func beginRename(_ favorite: FavoriteRouteEntity) {
        renameTarget = favorite
        renameText = favorite.title
        isRenaming = true
    }

    private func applyRename() {
        guard let target = renameTarget else { return }
        let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard newTitle != target.title else { return }
        target.title = newTitle
        target.touch()
        Repository(context: context, app: app).commit()
        successTick += 1
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(meta)

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
            Text(meta)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }

    private var meta: String {
        let usage = favorite.usageCount == 0 ? "Noch nicht genutzt" : "\(favorite.usageCount)× genutzt"
        return "\(usage) · \(Format.euroPrecise(valuePerUse)) je Fahrt"
    }

    private var accessibilityLabel: String {
        let route = "\(favorite.fromName) nach \(favorite.toName), \(favorite.mode.displayName)\(favorite.isRoundTrip ? ", hin und retour" : "")"
        return hasCustomTitle ? "\(favorite.title): \(route)" : route
    }
}
