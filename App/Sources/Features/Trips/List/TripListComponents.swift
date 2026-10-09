import SwiftUI
import SwiftData
import KlimaCore

// Building blocks shared by the trip-list module (TripsView, TripDetailView, FavoritesManagerView).
// Everything here is prefixed `TripList` to stay collision-free with modules written in parallel.

// MARK: - Formatting

@MainActor
enum TripListFormat {
    /// Vienna calendar for every day label – the month sections, the ticket period and the time shown (Format.time) all
    /// use Austrian time, so "Heute"/"Gestern" must too (one instance: `Calendar.vienna` builds a new one per access).
    static let calendar = Calendar.vienna

    /// Row eyebrow: "Heute", "Gestern" or "Fr. 9." (the month is already given by the section header).
    static func dayLabel(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        let weekday = date.formatted(viennaStyle(.dateTime.weekday(.abbreviated)))
        let day = calendar.component(.day, from: date)
        return "\(weekday) \(day)."
    }

    /// Detail eyebrow: "Heute · 07:12" or "Fr., 9. Oktober 2026 · 07:12".
    static func detailDateLine(_ date: Date) -> String {
        let time = Format.time(date)
        if calendar.isDateInToday(date) { return "Heute · \(time)" }
        if calendar.isDateInYesterday(date) { return "Gestern · \(time)" }
        let day = date.formatted(viennaStyle(.dateTime.weekday(.abbreviated).day().month(.wide).year()))
        return "\(day) · \(time)"
    }

    /// de-AT in Austrian time (the default style would format in the device's time zone).
    private static func viennaStyle(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var style = style.locale(Format.locale)
        style.timeZone = Format.timeZone
        style.calendar = calendar
        return style
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
}

// MARK: - Search

/// Fahrten search: one folded key per trip (stations, note, mode, purpose), cached until the trip changes (`updatedAt`),
/// so a keystroke costs one `contains` per word and trip instead of six `localizedStandardContains` calls. The key holds
/// the names folded twice – plain (case, accents, "ß") for typing in progress ("Hauptbahn") and StationIndex-normalised,
/// so what the rows show and the usual spellings find the trip too: "Hbf", "Wien Hbf", "Poelten", "Sankt Anton".
@MainActor
final class TripSearchIndex {
    private var keys: [UUID: (stamp: Date, key: String)] = [:]

    /// The words of a query (StationIndex-normalised); every one must appear in a trip, in any order.
    static func tokens(_ query: String) -> [String] {
        StationIndex.normalize(query).split(separator: " ").map(String.init)
    }

    func matches(_ trip: TripEntity, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let key = key(for: trip)
        return tokens.allSatisfy { key.contains($0) }
    }

    private func key(for trip: TripEntity) -> String {
        let id = trip.id
        let stamp = trip.updatedAt
        if let entry = keys[id], entry.stamp == stamp { return entry.key }
        var parts = [trip.fromName, trip.toName, trip.note, trip.mode.displayName] + trip.via.map(\.name)   // MARK: via
        if let category = trip.category { parts.append(category.displayName) }
        if trip.isInduced { parts.append(MetaCategoryStyle.inducedTitle) }
        let text = parts.joined(separator: " ")
        let plain = text.lowercased().replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Format.locale)
        let key = StationIndex.normalize(text) + " | " + plain
        keys[id] = (stamp, key)
        return key
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
        let baseline = breakEvenBaseline()
        let copy = repository.repeatTrip(trip)
        app.showToast("checkmark.circle.fill", "Nochmal erfasst",
                      "Heute · \(TripListFormat.routeTitle(copy.fromName, copy.toName)) · \(Format.euroPrecise(copy.totalValue))")
        celebrateIfCrossed(baseline, adding: copy)
    }

    /// Exact copy on the same day (e.g. the same route twice that day), note included – one commit.
    func duplicate(_ trip: TripEntity) {
        let baseline = breakEvenBaseline()
        let copy = repository.repeatTrip(trip, on: trip.date, note: trip.note)
        app.showToast("plus.square.fill.on.square.fill", "Fahrt dupliziert",
                      "\(Format.relativeDay(copy.date)) · \(Format.euroPrecise(copy.totalValue))")
        celebrateIfCrossed(baseline, adding: copy)
    }

    /// Soft delete with "Rückgängig" on the toast (a full swipe deletes without asking).
    func delete(_ trip: TripEntity) {
        repository.deleteTrip(trip)
        let id = trip.id
        let app = app, context = context
        app.showToast("trash.fill", "Fahrt gelöscht", TripListFormat.routeTitle(trip.fromName, trip.toName),
                      actionTitle: "Rückgängig") {
            TripListActions(app: app, context: context).restore(tripID: id)
        }
    }

    /// Undo of `delete`. Looks the trip up again – after "Alle Daten löschen" it is gone, and nothing happens.
    func restore(tripID: UUID) {
        let descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate { $0.id == tripID && $0.deletedAt != nil })
        guard let trip = (try? context.fetch(descriptor))?.first else { return }
        withMotion(Motion.smooth) { repository.restoreTrip(trip) }
        app.showToast("arrow.uturn.backward.circle.fill", "Fahrt wiederhergestellt",
                      TripListFormat.routeTitle(trip.fromName, trip.toName))
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
        let favorite = repository.metaAddFavorite(from: trip)
        app.showToast("star.circle.fill", "Als Favorit gespeichert",
                      TripListFormat.routeTitle(favorite.fromName, favorite.toName, roundTrip: favorite.isRoundTrip))
    }

    /// One-tap logging of a favourite ("Schnellerfassung").
    func log(_ favorite: FavoriteRouteEntity) {
        let baseline = breakEvenBaseline()
        let trip = repository.logFavorite(favorite)
        // A Kombi-Vorlage logs every leg: the favourite's value is the whole journey.
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", "\(favorite.displayTitle) · \(Format.euroPrecise(favorite.valuePerLog))")
        celebrateIfCrossed(baseline, adding: trip, value: favorite.valuePerLog)
    }

    // MARK: Break-even

    private struct BreakEvenBaseline {
        var ticketID: UUID
        var period: TicketPeriod
        var value: Double
    }

    /// The active ticket's value before a write: one fetch of its period's trips, no analytics pass (and none after the
    /// write either – the new trip's value is simply added).
    private func breakEvenBaseline() -> BreakEvenBaseline? {
        let repo = repository
        guard let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID) else { return nil }
        let period = ticket.period
        guard period.price > 0 else { return nil }
        let value = repo.periodTrips(ticket).reduce(0) { $0 + $1.totalValue }
        return BreakEvenBaseline(ticketID: ticket.id, period: period, value: value)
    }

    /// Raises the global celebration flag when `trip` (worth `value`, default its own) pushed the active ticket over its
    /// summit (own share).
    private func celebrateIfCrossed(_ baseline: BreakEvenBaseline?, adding trip: TripEntity, value: Double? = nil) {
        guard let baseline, baseline.value < baseline.period.price, baseline.period.contains(trip.date),
              baseline.value + (value ?? trip.totalValue) >= baseline.period.price,
              !app.settings.celebratedBreakEvenTicketIDs.contains(baseline.ticketID.uuidString) else { return }
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
                // MARK: via – "über Feldkirch" under the stations (DesignSystem/ViaDisplay.swift)
                VStack(alignment: .leading, spacing: 3) {
                    stations
                    let via = trip.via
                    if !via.isEmpty { ViaCaption(vias: via).padding(.leading, 21) }
                }
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
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
                MetaTripRowPurpose(category: trip.category, isInduced: trip.isInduced)
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
        "\(ViaText.spoken(from: trip.fromName, via: trip.via, to: trip.toName)), \(trip.mode.displayName)\(trip.isRoundTrip ? ", hin und retour" : "")"   // MARK: via
    }

    private var accessibilityValue: String {
        var parts = [Format.euroPrecise(trip.totalValue), Format.relativeDay(trip.date), Format.time(trip.date)]
        if let category = trip.category { parts.append(category.displayName) }
        if trip.isInduced { parts.append("\(MetaCategoryStyle.inducedTitle), ohne KlimaTicket nicht gefahren") }
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

/// List-row card: a tinted, non-blurred surface over the sky (insetGrouped clips it into the rounded section card).
/// No material per row – a dozen live backdrop blurs on screen made scrolling the history stutter; opaque with
/// Reduce Transparency. `isHighlighted`: a glacier wash for the trip that was just logged (fades out, opacity only).
struct TripListCardBackground: View {
    var isHighlighted = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if reduceTransparency {
                Theme.sheetBackground
            } else {
                Theme.sheetBackground.opacity(colorScheme == .dark ? 0.62 : 0.5)
                Theme.surface
            }
            Theme.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
                .opacity(isHighlighted ? 1 : 0)
        }
    }
}

// MARK: - Long-press preview

/// Context-menu preview of a trip (long press in Fahrten): date, value, route and mode at a glance – what the detail
/// shows on top, without its map. Self-contained (no environment beyond colour scheme), opaque.
struct TripListPreviewCard: View {
    let trip: TripEntity

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Kicker(text: TripListFormat.detailDateLine(trip.date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Theme.Spacing.xs)
                ModeIcon(mode: trip.mode, size: 30)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("€")
                    .font(.system(.title2, design: .rounded, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.number(trip.totalValue, decimals: 2))
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if trip.isRoundTrip {
                    Text("Hin & Retour")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
            }
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                RouteGlyph(color: Theme.modeColor(trip.mode), endColor: Theme.summit, height: 52)
                VStack(alignment: .leading, spacing: 10) {
                    Text(trip.fromName)
                    Text(trip.toName)
                }
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Text(meta)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.l)
        .frame(width: 320, alignment: .leading)
        .background(Theme.sheetBackground)
    }

    /// "Zug · 106 km · 2. Klasse · Arbeitsweg"
    private var meta: String {
        var parts = [trip.mode.displayName]
        if trip.distanceKm > 0 { parts.append(Format.km(trip.distanceKm)) }
        if trip.mode == .train || trip.mode == .sBahn { parts.append(trip.travelClass.displayName) }
        if let category = trip.category { parts.append(category.displayName) }
        if trip.isInduced { parts.append(MetaCategoryStyle.inducedTitle) }
        return parts.joined(separator: " · ")
    }
}
