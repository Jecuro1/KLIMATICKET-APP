import SwiftUI
import SwiftData
import KlimaCore

/// "Schnell erfassen": the "Neue Fahrt" call to action followed by horizontally scrolling favourite chips.
/// One tap on a chip logs the trip right away (toast with value + new amortisation). Long press offers
/// "Bearbeiten & erfassen", "Letzte Fahrt löschen" (undo of the last quick log) and "Entfernen".
struct DashQuickLogSection: View {
    var favorites: [FavoriteRouteEntity]
    /// Current summary, used for the toast ("jetzt 76 % amortisiert").
    var summary: SavingsSummary?
    /// Whether a trip logged right now falls into the shown ticket period.
    var ticketIsCurrent: Bool
    var showsNewTripButton: Bool = true

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    /// Favourite id → id of the trip most recently quick-logged from it (for "Letzte Fahrt löschen").
    @State private var lastLoggedTripIDs: [UUID: UUID] = [:]
    @State private var removalTick = 0

    var body: some View {
        let hapticsEnabled = app.settings.hapticsEnabled
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if showsNewTripButton {
                    newTripButton
                }
                if favorites.isEmpty {
                    favoriteHint
                } else {
                    ForEach(favorites) { favorite in
                        favoriteButton(favorite)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schnell erfassen")
        .sensoryFeedback(.warning, trigger: removalTick) { _, _ in hapticsEnabled }
    }

    // MARK: Items

    private var newTripButton: some View {
        Button {
            app.presentAddTrip()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Theme.onAccent.opacity(0.2), in: .circle)
                Text("Neue Fahrt")
                    .font(.headline)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.leading, 7)
            .padding(.trailing, Theme.Spacing.l)
            .padding(.vertical, 7)
            .background(Theme.ctaGradient, in: .capsule)
            .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 6)
            .contentShape(.capsule)
        }
        .buttonStyle(DashPressableStyle())
        .accessibilityHint("Öffnet das Formular zum Erfassen einer Fahrt")
    }

    private func favoriteButton(_ favorite: FavoriteRouteEntity) -> some View {
        Button {
            logFavorite(favorite)
        } label: {
            DashFavoriteChipLabel(favorite: favorite)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contextMenu { menu(for: favorite) }
        .accessibilityLabel("\(favorite.displayTitle) erfassen")
        .accessibilityValue(voiceOverValue(for: favorite))
        .accessibilityHint("Erfasst die Fahrt sofort")
        .accessibilityAction(named: "Bearbeiten und erfassen") {
            app.presentAddTrip(draft(for: favorite))
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    @ViewBuilder
    private func menu(for favorite: FavoriteRouteEntity) -> some View {
        Button("Bearbeiten & erfassen", systemImage: "square.and.pencil") {
            app.presentAddTrip(draft(for: favorite))
        }
        if lastLoggedTripIDs[favorite.id] != nil {
            Button("Letzte Fahrt löschen", systemImage: "arrow.uturn.backward", role: .destructive) {
                undoLastLog(of: favorite)
            }
        }
        Divider()
        Button("Entfernen", systemImage: "star.slash", role: .destructive) {
            remove(favorite)
        }
    }

    /// Shown instead of chips when there are no favourites yet.
    private var favoriteHint: some View {
        Button {
            app.presentAddTrip()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 36, height: 36)
                    .background(Theme.gold.opacity(0.16), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Favorit anlegen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Beim Erfassen „Als Favorit speichern“")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, Theme.Spacing.m)
            .padding(.vertical, 6)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityHint("Öffnet das Formular – dort kannst du die Strecke als Favorit speichern")
    }

    // MARK: Actions

    private func logFavorite(_ favorite: FavoriteRouteEntity) {
        let repository = Repository(context: context, app: app)
        let trip = withAnimation(.smooth) { repository.logFavorite(favorite) }
        lastLoggedTripIDs[favorite.id] = trip.id
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", toastSubtitle(adding: trip.totalValue))
    }

    private func undoLastLog(of favorite: FavoriteRouteEntity) {
        guard let tripID = lastLoggedTripIDs[favorite.id] else { return }
        lastLoggedTripIDs[favorite.id] = nil
        let descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == tripID && $0.deletedAt == nil })
        guard let trip = (try? context.fetch(descriptor))?.first else { return }
        withAnimation(.smooth) { Repository(context: context, app: app).deleteTrip(trip) }
        app.showToast("arrow.uturn.backward.circle.fill", "Fahrt gelöscht", favorite.displayTitle)
    }

    private func remove(_ favorite: FavoriteRouteEntity) {
        lastLoggedTripIDs[favorite.id] = nil
        withAnimation(.smooth) { Repository(context: context, app: app).deleteFavorite(favorite) }
        removalTick += 1
    }

    /// The editor applies the favourite like its own favourites row (`TripEditorModel.apply(favorite:)`): stations, mode,
    /// round trip, category – and the stored fare when there is no estimate (a custom place such as „Lech“ would
    /// otherwise open with „–“ and „Gib einen Normalpreis ein.“ although the chip shows € 5,80).
    private func draft(for favorite: FavoriteRouteEntity) -> TripDraft {
        var draft = TripDraft()
        draft.fromStationID = favorite.fromStationID
        draft.toStationID = favorite.toStationID
        draft.fromName = favorite.fromName
        draft.toName = favorite.toName
        draft.mode = favorite.mode
        draft.isRoundTrip = favorite.isRoundTrip
        draft.favorite = favorite
        draft.date = Date()
        return draft
    }

    private func toastSubtitle(adding value: Double) -> String {
        let amount = "+ " + Format.euroPrecise(value)
        guard ticketIsCurrent, let summary, summary.ticketPrice > 0 else { return amount }
        if summary.isPaidOff { return amount + " · reiner Gewinn" }
        let fraction = (summary.totalValue + value) / summary.ticketPrice
        return amount + " · jetzt " + Format.percent(fraction) + " amortisiert"
    }

    private func voiceOverValue(for favorite: FavoriteRouteEntity) -> String {
        let legs: Double = favorite.isRoundTrip ? 2 : 1
        var parts = [ViaText.spoken(from: favorite.fromName, via: favorite.via, to: favorite.toName), favorite.mode.displayName]   // MARK: via
        if favorite.isRoundTrip { parts.append("hin und retour") }
        parts.append(Format.euroPrecise(favorite.fareEUR * legs))
        return parts.joined(separator: ", ")
    }
}

/// Chip content: mode icon · "St. Anton → Innsbruck Hbf" · badge + meta · price · round "+" knob.
struct DashFavoriteChipLabel: View {
    let favorite: FavoriteRouteEntity

    private var legs: Double { favorite.isRoundTrip ? 2 : 1 }
    private var badge: String? { DashModeBadge.label(for: favorite.mode) }

    var body: some View {
        HStack(spacing: 10) {
            ModeIcon(mode: favorite.mode, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                route
                meta
            }
            Text(Format.euroPrecise(favorite.fareEUR * legs))
                .font(DashStyle.smallNumber)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, 2)
            Image(systemName: "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 30, height: 30)
                .background(Theme.ctaGradient, in: .circle)
        }
        .lineLimit(1)
        .padding(.vertical, 6)
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .contentShape(.capsule)
    }

    private var route: some View {
        HStack(spacing: 4) {
            Text(TripRow.short(favorite.fromName))
            Image(systemName: favorite.isRoundTrip ? "arrow.left.arrow.right" : "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
            Text(TripRow.short(favorite.toName))
            if !favorite.title.isEmpty, !favorite.viaRaw.isEmpty {   // MARK: via – the meta line holds the title: glyph only
                ViaGlyph(color: Theme.textTertiary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
    }

    private var meta: some View {
        HStack(spacing: 5) {
            if let badge {
                DashModeBadge(text: badge)
            }
            Text(metaText)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var metaText: String {
        var parts: [String] = []
        if !favorite.title.isEmpty {
            parts.append(favorite.title)
        } else if let via = ViaText.subtitle(favorite.via) {   // MARK: via – "über Feldkirch" in place of the mode name
            parts.append(via)
        } else if badge == nil {
            parts.append(favorite.mode.displayName)
        }
        if favorite.distanceKm > 0 { parts.append(Format.km(favorite.distanceKm * legs)) }
        return parts.joined(separator: " · ")
    }
}
