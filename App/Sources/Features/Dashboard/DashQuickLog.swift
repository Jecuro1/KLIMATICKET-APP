import SwiftUI
import SwiftData
import KlimaCore

/// "Schnell erfassen": the "Neue Fahrt" call to action followed by horizontally scrolling favourite chips.
/// One tap on a chip logs the trip right away: its "+" turns into a green check, the glass tints for a moment and the
/// toast confirms with value + new amortisation and offers "Rückgängig" (one haptic – the toast's; a milestone plays
/// `.milestone`, the break-even leaves it to the celebration). Long press offers "Bearbeiten & erfassen",
/// "Letzte Fahrt löschen" and "Entfernen" (also with "Rückgängig"); the QuickLog tip explains both once.
struct DashQuickLogSection: View {
    var favorites: [FavoriteRouteEntity]
    /// Current summary, used for the toast ("jetzt 76 % amortisiert") and the milestone haptic.
    var summary: SavingsSummary?
    /// The shown ticket – the break-even celebration plays once per ticket.
    var ticketID: UUID? = nil
    /// Whether a trip logged right now falls into the shown ticket period.
    var ticketIsCurrent: Bool
    var showsNewTripButton: Bool = true

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    /// Favourite id → id of the trip most recently quick-logged from it (for "Letzte Fahrt löschen").
    @State private var lastLoggedTripIDs: [UUID: UUID] = [:]
    /// Favourites whose "+" shows the check right now.
    @State private var justLogged: Set<UUID> = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if showsNewTripButton {
                    newTripButton
                }
                if favorites.isEmpty {
                    favoriteHint
                } else {
                    ForEach(favorites) { favorite in
                        favoriteButton(favorite, isFirst: favorite.id == favorites.first?.id)
                            .carouselItem()
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Theme.Spacing.xs)
        }
        .carouselScrolling()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schnell erfassen")
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
        .buttonStyle(.pressable)
        .accessibilityHint("Öffnet das Formular zum Erfassen einer Fahrt")
    }

    @ViewBuilder
    private func favoriteButton(_ favorite: FavoriteRouteEntity, isFirst: Bool) -> some View {
        let isLogged = justLogged.contains(favorite.id)
        let chip = Button {
            logFavorite(favorite)
        } label: {
            DashFavoriteChipLabel(favorite: favorite, isLogged: isLogged)
        }
        .buttonStyle(.plain)
        // The glass itself confirms: a green tint for a moment (system glass reacts to the touch on its own).
        .glassEffect(isLogged ? .regular.tint(Theme.positive.opacity(0.24)).interactive() : .regular.interactive(),
                     in: .capsule)
        .contextMenu { menu(for: favorite) }
        .accessibilityLabel("\(favorite.displayTitle) erfassen")
        .accessibilityValue(isLogged ? "Erfasst" : voiceOverValue(for: favorite))
        .accessibilityHint("Erfasst die Fahrt sofort")
        .accessibilityAction(named: "Bearbeiten und erfassen") {
            app.presentAddTrip(draft(for: favorite))
        }
        .motionTransition(.pop)
        if isFirst {
            chip.popoverTip(KBTips.QuickLog(), arrowEdge: .top)
        } else {
            chip
        }
    }

    @ViewBuilder
    private func menu(for favorite: FavoriteRouteEntity) -> some View {
        Button("Bearbeiten & erfassen", systemImage: "square.and.pencil") {
            KBTips.used(KBTips.QuickLog())
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
        let trip = withMotion(Motion.smooth) { repository.logFavorite(favorite) }
        lastLoggedTripIDs[favorite.id] = trip.id
        KBTips.used(KBTips.QuickLog())
        flashCheck(on: favorite.id)
        let undo = DashQuickLogUndo(app: app, context: context)
        let tripID = trip.id, favoriteID = favorite.id
        let added = favorite.valuePerLog   // MARK: trips – every leg of a Kombi-Vorlage (= trip.totalValue for one route)
        let haptic = toastHaptic(adding: added)
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", toastSubtitle(adding: added),
                      actionTitle: "Rückgängig", haptic: haptic ?? .success) {
            undo.undo(tripID: tripID, favoriteID: favoriteID)
        }
        // `showToast` maps nil to the default haptic: silence this toast here, the break-even celebration plays its own.
        if haptic == nil, app.toast?.title == "Fahrt erfasst" { app.toast?.haptic = nil }
    }

    /// The "+" turns into a check for 1.4 s; a second tap meanwhile logs again (and keeps the check).
    private func flashCheck(on id: UUID) {
        withMotion(Motion.bouncy) { _ = justLogged.insert(id) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withMotion(Motion.smooth) { _ = justLogged.remove(id) }
        }
    }

    private func undoLastLog(of favorite: FavoriteRouteEntity) {
        guard let tripID = lastLoggedTripIDs[favorite.id] else { return }
        lastLoggedTripIDs[favorite.id] = nil
        DashQuickLogUndo(app: app, context: context).undo(tripID: tripID, favoriteID: favorite.id)
    }

    /// "Favorit entfernt · Rückgängig" (the toast plays the warning haptic).
    private func remove(_ favorite: FavoriteRouteEntity) {
        lastLoggedTripIDs[favorite.id] = nil
        let repository = Repository(context: context, app: app)
        withMotion(Motion.smooth) { repository.deleteFavorite(favorite) }
        app.showToast("trash.fill", "Favorit entfernt", favorite.displayTitle, actionTitle: "Rückgängig") {
            withMotion(Motion.smooth) { repository.restoreFavorites([favorite]) }
        }
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

    /// One haptic per action: `.success`; `.milestone` when the trip crosses 25 / 50 / 75 % (the hero pops); none when
    /// it reaches the summit for the first time – the break-even celebration plays its own.
    private func toastHaptic(adding value: Double) -> Haptic? {
        guard ticketIsCurrent, let summary, summary.ticketPrice > 0, !summary.isPaidOff else { return .success }
        let before = summary.totalValue / summary.ticketPrice
        let after = (summary.totalValue + value) / summary.ticketPrice
        if after >= 1 {
            let celebrated = ticketID.map { app.settings.celebratedBreakEvenTicketIDs.contains($0.uuidString) } ?? true
            return celebrated ? .milestone : nil
        }
        let step = { (fraction: Double) in min(3, Int(SummitFigures.percent(fraction) / 25)) }
        return step(after) > step(before) ? .milestone : .success
    }

    private func voiceOverValue(for favorite: FavoriteRouteEntity) -> String {
        let legs: Double = favorite.isRoundTrip ? 2 : 1
        var parts = [ViaText.spoken(from: favorite.fromName, via: favorite.via, to: favorite.toName), favorite.mode.displayName]   // MARK: via
        if favorite.isRoundTrip { parts.append("hin und retour") }
        parts.append(Format.euroPrecise(favorite.fareEUR * legs))
        return parts.joined(separator: ", ")
    }
}

/// "Rückgängig" of a quick log: looks the trip up again (it may already be gone – deleted elsewhere, "Alle Daten
/// löschen") and removes it through the Repository, giving the favourite its use back.
@MainActor
private struct DashQuickLogUndo {
    let app: AppState
    let context: ModelContext

    func undo(tripID: UUID, favoriteID: UUID) {
        let tripQuery = FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == tripID && $0.deletedAt == nil })
        guard let trip = (try? context.fetch(tripQuery))?.first else { return }
        let favoriteQuery = FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate<FavoriteRouteEntity> { $0.id == favoriteID })
        let favorite = (try? context.fetch(favoriteQuery))?.first
        let route = "\(TripRow.short(trip.fromName)) → \(TripRow.short(trip.toName))"
        withMotion(Motion.smooth) { Repository(context: context, app: app).undoLogFavorite(trip, favorite: favorite) }
        app.showToast("arrow.uturn.backward.circle.fill", "Erfassung zurückgenommen", route, haptic: .warning)
    }
}

/// Chip content: mode icon · "St. Anton → Innsbruck Hbf" · badge + meta · price · round "+" knob.
struct DashFavoriteChipLabel: View {
    let favorite: FavoriteRouteEntity
    /// Just logged: the "+" knob turns into a green check.
    var isLogged: Bool = false

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
            Image(systemName: isLogged ? "checkmark" : "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .symbolReplaceTransition()
                .symbolBounce(on: isLogged)
                .frame(width: 30, height: 30)
                .background(isLogged ? AnyShapeStyle(Theme.positive) : AnyShapeStyle(Theme.ctaGradient), in: .circle)
                .accessibilityHidden(true)
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
