import SwiftUI
import SwiftData
import KlimaCore

// Building blocks shared by the trip-list module (TripsView, TripDetailView, FavoritesManagerView).
// Everything here is prefixed `TripList` to stay collision-free with modules written in parallel.

// MARK: - Formatting

@MainActor
enum TripListFormat {
    /// Row eyebrow: "Heute", "Gestern" or "Fr. 9." (the month is already given by the section header).
    static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(Format.locale))
        let day = calendar.component(.day, from: date)
        return "\(weekday) \(day)."
    }

    /// Detail eyebrow: "Heute · 07:12" or "Fr., 9. Oktober 2026 · 07:12".
    static func detailDateLine(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = Format.time(date)
        if calendar.isDateInToday(date) { return "Heute · \(time)" }
        if calendar.isDateInYesterday(date) { return "Gestern · \(time)" }
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year().locale(Format.locale))
        return "\(day) · \(time)"
    }

    /// "Ticketjahr 2026/27" (or "Ticketjahr 2026" when the validity stays within one calendar year).
    static func periodLabel(_ ticket: TicketEntity) -> String {
        let calendar = Calendar.vienna
        let startYear = calendar.component(.year, from: ticket.startDate)
        let endYear = calendar.component(.year, from: ticket.endDate)
        if startYear == endYear { return "Ticketjahr \(startYear)" }
        return "Ticketjahr \(startYear)/\(String(format: "%02d", endYear % 100))"
    }

    /// Period label, disambiguated with the ticket name when two tickets share a year.
    static func periodTitle(_ ticket: TicketEntity, among tickets: [TicketEntity]) -> String {
        let label = periodLabel(ticket)
        let sameYear = tickets.filter { periodLabel($0) == label }.count
        return sameYear > 1 ? "\(label) · \(ticket.name)" : label
    }

    /// Category plaque ("S", "U", "Bus", "Bim") – only when known; trains without a category get none.
    static func badge(for mode: TransportMode) -> String? {
        switch mode {
        case .sBahn: return "S"
        case .metro: return "U"
        case .bus: return "Bus"
        case .tram: return "Bim"
        default: return nil
        }
    }

    /// "St. Anton → Innsbruck Hbf"
    static func routeTitle(_ fromName: String, _ toName: String, roundTrip: Bool = false) -> String {
        "\(TripRow.short(fromName)) \(roundTrip ? "⇄" : "→") \(TripRow.short(toName))"
    }

    /// "1 Fahrt" / "87 Fahrten"
    static func tripCount(_ count: Int) -> String {
        count == 1 ? "1 Fahrt" : "\(Format.number(Double(count))) Fahrten"
    }

    /// "Hauptbahnhof · Tirol", "Bahnhof · Vorarlberg", "Bushaltestelle · Warth · Vorarlberg".
    static func stationSubtitle(_ station: Station?) -> String? {
        station?.rowSubtitle
    }

    /// Search over station names, notes and the mode name (case- and diacritic-insensitive).
    static func matches(_ trip: TripEntity, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return trip.fromName.localizedStandardContains(query)
            || trip.toName.localizedStandardContains(query)
            || trip.note.localizedStandardContains(query)
            || trip.mode.displayName.localizedStandardContains(query)
    }
}

// MARK: - Actions (all writes go through Repository)

/// Trip actions shared by the list (swipe / context menu) and the detail screen.
@MainActor
struct TripListActions {
    let app: AppState
    let context: ModelContext

    private var repository: Repository { Repository(context: context, app: app) }

    /// Opens the add-trip sheet in edit mode.
    func edit(_ trip: TripEntity) {
        let draft = TripDraft(fromStationID: trip.fromStationID, toStationID: trip.toStationID,
                              fromName: trip.fromName, toName: trip.toName, mode: trip.mode,
                              date: trip.date, isRoundTrip: trip.isRoundTrip, editingTripID: trip.id)
        app.presentAddTrip(draft)
    }

    /// "Nochmal fahren" – logs the same trip for today.
    func repeatToday(_ trip: TripEntity) {
        let before = paidOffState()
        let copy = repository.repeatTrip(trip)
        app.showToast("checkmark.circle.fill", "Nochmal erfasst",
                      "Heute · \(TripListFormat.routeTitle(copy.fromName, copy.toName)) · \(Format.euroPrecise(copy.totalValue))")
        celebrateIfCrossed(before: before)
    }

    /// Exact copy on the same day (e.g. the same route twice that day).
    func duplicate(_ trip: TripEntity) {
        let before = paidOffState()
        let repo = repository
        let copy = repo.repeatTrip(trip, on: trip.date)
        if !trip.note.isEmpty {
            copy.note = trip.note
            repo.updateTrip(copy)
        }
        app.showToast("plus.square.fill.on.square.fill", "Fahrt dupliziert",
                      "\(Format.relativeDay(copy.date)) · \(Format.euroPrecise(copy.totalValue))")
        celebrateIfCrossed(before: before)
    }

    func delete(_ trip: TripEntity) {
        repository.deleteTrip(trip)
        app.showToast("trash.fill", "Fahrt gelöscht", TripListFormat.routeTitle(trip.fromName, trip.toName))
    }

    /// The favourite that already covers this route (same stations, mode and direction type), if any.
    func existingFavorite(for trip: TripEntity, in favorites: [FavoriteRouteEntity]) -> FavoriteRouteEntity? {
        favorites.first { fav in
            fav.deletedAt == nil && fav.fromName == trip.fromName && fav.toName == trip.toName
                && fav.modeRaw == trip.modeRaw && fav.isRoundTrip == trip.isRoundTrip
        }
    }

    func addFavorite(_ trip: TripEntity, favorites: [FavoriteRouteEntity]) {
        if let existing = existingFavorite(for: trip, in: favorites) {
            app.showToast("star.circle.fill", "Schon ein Favorit", existing.displayTitle)
            return
        }
        let favorite = repository.addFavorite(from: trip)
        app.showToast("star.circle.fill", "Als Favorit gespeichert",
                      TripListFormat.routeTitle(favorite.fromName, favorite.toName, roundTrip: favorite.isRoundTrip))
    }

    /// One-tap logging of a favourite ("Schnellerfassung").
    func log(_ favorite: FavoriteRouteEntity) {
        let before = paidOffState()
        let trip = repository.logFavorite(favorite)
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", "\(favorite.displayTitle) · \(Format.euroPrecise(trip.totalValue))")
        celebrateIfCrossed(before: before)
    }

    // MARK: Break-even

    private func paidOffState() -> (ticketID: UUID, isPaidOff: Bool)? {
        let repo = repository
        guard let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID) else { return nil }
        let snapshot = Analytics.make(ticket: ticket, trips: repo.liveTrips(), catalog: app.catalog)
        return (ticket.id, snapshot.summary.isPaidOff)
    }

    /// Raises the global celebration flag when this action pushed the active ticket over its summit.
    private func celebrateIfCrossed(before: (ticketID: UUID, isPaidOff: Bool)?) {
        guard let before, !before.isPaidOff,
              let after = paidOffState(), after.ticketID == before.ticketID, after.isPaidOff,
              !app.settings.celebratedBreakEvenTicketIDs.contains(after.ticketID.uuidString) else { return }
        app.celebrateBreakEven = true
    }
}

// MARK: - Row (Rail-Editorial layout in Alpine-Glass dress)

/// "HEUTE / 07:12" · vertical 2-stop route glyph · stations · amount + category plaque + mode icon.
struct TripListRow: View {
    let trip: TripEntity

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var dateColumnWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .subheadline) private var stationSpacing: CGFloat = 7

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.s))
        layout {
            dateColumn
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                stations
                Spacer(minLength: Theme.Spacing.xs)
                trailing
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Zeigt die Details der Fahrt")
    }

    @ViewBuilder
    private var dateColumn: some View {
        if isStacked {
            Text("\(TripListFormat.dayLabel(trip.date)) · \(Format.time(trip.date))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: TripListFormat.dayLabel(trip.date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Format.time(trip.date))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: dateColumnWidth, alignment: .leading)
        }
    }

    private var stations: some View {
        VStack(alignment: .leading, spacing: stationSpacing) {
            Text(TripRow.short(trip.fromName))
                .foregroundStyle(Theme.textPrimary)
            Text(TripRow.short(trip.toName))
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.leading, 21)
        .background(alignment: .leading) { glyph }
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
    }

    /// DS RouteGlyph, sized so its two stops sit exactly on the two station lines at any text size.
    private var glyph: some View {
        GeometryReader { geo in
            let line = max(0, (geo.size.height - stationSpacing) / 2)
            RouteGlyph(color: Theme.modeColor(trip.mode), endColor: Theme.summit, height: line + stationSpacing + 11)
                .offset(y: line / 2 - 5.5)
        }
        .frame(width: 11)
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(Format.euroPrecise(trip.totalValue))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            HStack(spacing: 5) {
                if trip.isRoundTrip {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let badge = TripListFormat.badge(for: trip.mode) {
                    TripListModeBadge(text: badge)
                }
                ModeIcon(mode: trip.mode, size: 22)
            }
        }
        .fixedSize()
    }

    private var accessibilityLabel: String {
        "\(trip.fromName) nach \(trip.toName), \(trip.mode.displayName)\(trip.isRoundTrip ? ", hin und retour" : "")"
    }

    private var accessibilityValue: String {
        var parts = [Format.euroPrecise(trip.totalValue), Format.relativeDay(trip.date), Format.time(trip.date)]
        if !trip.note.isEmpty { parts.append("Notiz: \(trip.note)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Small pieces

/// Outlined category plaque ("S", "U", "Bus", "Bim") from Rail Editorial.
struct TripListModeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.kicker)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.textTertiary, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Tinted capsule label ("Hin & Retour", "Offizieller ÖBB-Preis", "Eigener Preis").
struct TripListPill: View {
    let title: String
    let symbol: String
    var foreground: Color = Theme.accentText
    var fill: Color = Theme.accent

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill.opacity(0.14), in: .capsule)
    }
}

/// Frosted list-row background (insetGrouped clips it into the rounded section card); opaque with Reduce Transparency.
struct TripListCardBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Theme.sheetBackground
        } else {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Theme.surface.opacity(0.6)
            }
        }
    }
}
