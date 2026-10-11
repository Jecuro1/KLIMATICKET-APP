import SwiftUI
import SwiftData
import KlimaCore
#if canImport(SafariServices)
import SafariServices
#endif

/// One connection in detail (docs/OEBB_LIVE.md §E3 „Detail“, UX §4.3, mock 12): times with realtime, the map, the value
/// card with the price source, the timeline with platforms, changes and notices – and „Fahrt erfassen“ in one tap.
struct ConnectionDetailView: View {
    let rowID: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse) private var trips: [TripEntity]

    @State private var polylines: [String: [GeoPoint]] = [:]
    @State private var price = PlannerPriceState()
    @State private var expanded: Set<String> = []
    @State private var showsMap = false
    @State private var showsShop = false
    @State private var showsPriceInfo = false
    @State private var loggedTrips: [TripEntity] = []
    @State private var confirmsFuture = false
    @State private var logTick = 0
    @State private var calendarFile: URL?

    var body: some View {
        let model = app.planner
        Group {
            if let row = model.row(id: rowID) {
                content(row, model: model)
            } else {
                ContentUnavailableView("Verbindung nicht mehr da", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                       description: Text("Such die Verbindung noch einmal."))
            }
        }
        .ambientBackground(.standard, glow: 0.4)
        .navigationBarTitleDisplayMode(.inline)
        .zoomDestination(id: rowID)
    }

    // MARK: Content

    private func content(_ row: ConnectionRow, model: PlannerModel) -> some View {
        let journey = row.journey
        let amount = displayQuote(row)
        return ScrollView {
            VStack(spacing: Theme.Spacing.s) {
                headerCard(row)
                    .reveal(order: 0)
                valueCard(row, amount: amount, model: model)
                    .reveal(order: 1)
                ForEach(journeyNotices(journey)) { NoticeRow(notice: $0, compact: false) }
                    .reveal(order: 2)
                timelineCard(row)
                    .reveal(order: 3)
                footer(row)
                    .reveal(order: 4)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, 120)
        }
        .revealScope()
        .safeAreaInset(edge: .bottom) { actionBar(row, amount: amount, model: model) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText(row)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Teilen")
                if let calendarFile {
                    ShareLink(item: calendarFile) { Image(systemName: "calendar.badge.plus") }
                        .accessibilityLabel("In den Kalender")
                }
            }
        }
        .sheet(isPresented: $showsMap) { ConnectionMapSheet(route: mapRoute(row)) }
        .sheet(isPresented: $showsShop) { if let url = journey.shopURL { PlannerSafariSheet(url: url) } }
        .confirmationDialog("Diese Fahrt liegt in der Zukunft.", isPresented: $confirmsFuture, titleVisibility: .visible) {
            Button("Trotzdem erfassen") { logNow(row, amount: amount, model: model) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Erfasse sie am besten nach der Ankunft.")
        }
        .task(id: journey.id) { await loadExtras(row, model: model) }
        .task(id: scenePhase) { await refreshLoop(model) }
        .haptic(.success, trigger: logTick)
    }

    // MARK: Header

    private func headerCard(_ row: ConnectionRow) -> some View {
        let s = row.summary
        let isLive = s.departure.state != .scheduled || s.arrival.state != .scheduled
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: dayText(s.plannedDeparture))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    timeBlock(s.plannedDeparture, s.departure)
                    Image(systemName: "arrow.right").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    timeBlock(s.plannedArrival, s.arrival)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("\(s.durationText) · \(s.changesText)")
                        .font(.system(size: 17)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    liveChip(s, isLive: isLive)
                }
                ConnectionMapView(route: mapRoute(row), onExpand: { showsMap = true })
                    .padding(.top, 2)
            }
        }
    }

    private func timeBlock(_ planned: Date?, _ label: RealtimeLabel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(planned.map(Format.time) ?? "–")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(label.state == .cancelled ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(label.state == .cancelled, color: Theme.negativeText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if label.state == .late || label.state == .veryLate, let text = label.text {
                Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(PlannerRealtimeStyle.text(label.state))
            }
        }
    }

    private func liveChip(_ s: ConnectionSummary, isLive: Bool) -> some View {
        let worst = [s.departure, s.arrival].max { rank($0.state) < rank($1.state) } ?? s.departure
        let text: String
        switch worst.state {
        case .scheduled: text = "Fahrplan"
        case .onTime: text = "Live · pünktlich"
        case .late, .veryLate: text = "Live · +\(worst.delayMinutes ?? 0) min"
        case .cancelled: text = "Fällt aus"
        }
        return HStack(spacing: 5) {
            if isLive { LiveDot(state: worst.state, size: 7) }
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(PlannerRealtimeStyle.text(worst.state))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PlannerRealtimeStyle.dot(worst.state).opacity(0.14), in: .capsule)
    }

    private func rank(_ state: RealtimeState) -> Int {
        switch state { case .scheduled: 0; case .onTime: 1; case .late: 2; case .veryLate: 3; case .cancelled: 4 }
    }

    // MARK: Value

    private func valueCard(_ row: ConnectionRow, amount: Double?, model: PlannerModel) -> some View {
        let coverage = row.coverage?.overall ?? .unknown
        let snapshot = valueSnapshot(extra: counts(coverage) ? amount : nil)
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.card) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Image(systemName: coverage == .notCovered ? "ticket" : "ticket.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(coverage == .notCovered ? Theme.negativeText : Theme.positive)
                    .frame(width: 52, height: 52)
                    .background((coverage == .notCovered ? Theme.negative : Theme.positive).opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let amount {
                            Text(Format.euroPrecise(amount))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(coverage == .notCovered ? Theme.textPrimary : Theme.positiveText)
                                .numericValue(amount)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(valueCaption(coverage)).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    }
                    HStack(spacing: 6) {
                        Text(valueSubcaption(row, coverage: coverage)).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if let badge = price.badge ?? row.price.badge { PriceSourceBadge(source: badge) }
                        if let quote = price.quote ?? row.price.quote {
                            Button { showsPriceInfo = true } label: {
                                Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                                    .frame(width: 32, height: 32).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Woher kommt der Preis?")
                            .popover(isPresented: $showsPriceInfo) { PriceInfoPopover(quote: quote).presentationCompactAdaptation(.popover) }
                        }
                    }
                }
                Spacer(minLength: 0)
                if let snapshot {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(Format.percent(snapshot.before)).foregroundStyle(Theme.textSecondary)
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
                            Text(Format.percent(snapshot.after)).foregroundStyle(Theme.accentText)
                        }
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        Text("amortisiert").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func counts(_ coverage: CoverageResult) -> Bool { coverage == .covered || coverage == .surcharge || coverage == .partial }

    private func valueCaption(_ coverage: CoverageResult) -> String {
        switch coverage {
        case .covered, .surcharge, .partial: "gespart"
        case .notCovered: "Ticket nötig"
        default: "Normalpreis"
        }
    }

    private func valueSubcaption(_ row: ConnectionRow, coverage: CoverageResult) -> String {
        switch coverage {
        case .partial:
            if let name = row.coverage?.lastCoveredStopName { return "Gültig bis \(DisplayNames.name(name)) · Normalpreis" }
            return "Teilstrecke · Normalpreis"
        case .notCovered: return "Nicht im \(app.planner.ticketName) enthalten"
        case .unknown, .notApplicable: return "Gültigkeit prüfen · Normalpreis"
        case .discount: return row.coverage?.legs.compactMap(\.badge).first ?? "Ermäßigt · Normalpreis"
        default: return "Normalpreis"
        }
    }

    private struct ValueSnapshot { var before: Double; var after: Double }

    /// Amortisation before and after this connection counts (only with a ticket and a price that counts).
    private func valueSnapshot(extra: Double?) -> ValueSnapshot? {
        guard let extra, extra > 0, let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return nil }
        let summary = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog).summary
        guard summary.ticketPrice > 0 else { return nil }
        return ValueSnapshot(before: summary.amortizedFraction, after: (summary.totalValue + extra) / summary.ticketPrice)
    }

    private func displayQuote(_ row: ConnectionRow) -> Double? {
        (price.quote ?? row.price.quote)?.amountEUR
    }

    // MARK: Timeline

    private func timelineCard(_ row: ConnectionRow) -> some View {
        TimelineList(journey: row.journey, summary: row.summary, expanded: $expanded)
            .padding(Theme.Spacing.m)
            .frostedCard(cornerRadius: Theme.Radius.card)
    }

    private func journeyNotices(_ journey: Journey) -> [Notice] {
        let remarks = journey.remarks
        return JourneyPresentation.notices(remarks).filter { $0.severity >= .warning }
    }

    // MARK: Footer

    private func footer(_ row: ConnectionRow) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if row.journey.shopURL != nil {
                Button { showsShop = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari").font(.system(size: 16, weight: .semibold))
                        Text("Im ÖBB-Ticketshop öffnen").font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                Text("KlimaBilanz verkauft keine Tickets – der Kauf läuft im Shop der ÖBB.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            PlannerAttribution()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: Action bar

    @ViewBuilder
    private func actionBar(_ row: ConnectionRow, amount: Double?, model: PlannerModel) -> some View {
        let coverage = row.coverage?.overall ?? .unknown
        VStack(spacing: 6) {
            if !loggedTrips.isEmpty {
                Button { planReturn(row, model: model) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .semibold))
                        Text("Erfasst · Rückfahrt planen").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Theme.positiveText)
                    .background(Theme.positive.opacity(0.14), in: .capsule)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .motionTransition(.pop)
            } else if coverage == .notCovered {
                Button {} label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ticket").font(.system(size: 17, weight: .semibold))
                        Text("Nicht im KlimaTicket").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.primary)
                .disabled(true)
                Button("Trotzdem erfassen") { openEditor(row, model: model) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.vertical, 4)
            } else {
                Button { requestLog(row, amount: amount, model: model) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                        Text("Fahrt erfassen").font(.headline)
                        if let amount {
                            Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 22)
                            Text(Format.euroPrecise(amount)).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
                                .numericValue(amount)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.primary)
                .disabled(row.summary.isCancelled)
                .accessibilityHint(coverage == .partial ? "Erfasst nur den Teil, der dein Ticket abdeckt" : "")
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xs)
        .motionAnimation(Motion.bouncy, value: loggedTrips.isEmpty)
    }

    // MARK: Actions

    private func requestLog(_ row: ConnectionRow, amount: Double?, model: PlannerModel) {
        let departure = row.journey.rideLegs.first?.departure.planned ?? row.journey.departure?.planned
        if let departure, departure.timeIntervalSinceNow > 2 * 3600 {
            confirmsFuture = true
        } else {
            logNow(row, amount: amount, model: model)
        }
    }

    private func logNow(_ row: ConnectionRow, amount: Double?, model: PlannerModel) {
        let repo = Repository(context: context, app: app)
        let quote = price.quote ?? row.price.quote
        let trips = repo.logJourney(row.journey, quote: quote, coverage: row.coverage, travelClass: app.settings.defaultTravelClass,
                                    via: model.queriedVias)
        guard !trips.isEmpty else {
            app.showToast("exclamationmark.triangle.fill", "Nichts zu erfassen", "Diese Verbindung hat keine Fahrt mit Zug oder Bus")
            return
        }
        withMotion(Motion.bouncy) { loggedTrips = trips }
        logTick += 1
        let added = trips.reduce(0) { $0 + $1.fareEUR }
        var subtitle = "+ \(Format.euroPrecise(added))"
        if row.coverage?.overall == .partial, let name = row.coverage?.lastCoveredStopName {
            subtitle += " · nur bis \(DisplayNames.name(name)) bewertet"
        } else if row.coverage?.overall == .unknown {
            subtitle += " · Gültigkeit prüfen"
        }
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", subtitle, actionTitle: "Rückgängig", haptic: .success) {
            Repository(context: context, app: app).deleteTrips(trips)
            withMotion(Motion.smooth) { loggedTrips = [] }
        }
    }

    private func planReturn(_ row: ConnectionRow, model: PlannerModel) {
        let arrival = row.journey.arrival?.planned ?? Date()
        model.swap()
        model.setWhen(max(arrival.addingTimeInterval(2 * 3600), Date()), arrival: false)
        model.path = [.results]
        model.restartSearch()
    }

    /// „Trotzdem erfassen“ of a connection the ticket does not cover: the editor opens with the route, the user decides.
    private func openEditor(_ row: ConnectionRow, model: PlannerModel) {
        let plan = JourneyLogPlanner.plan(journey: row.journey, quote: price.quote ?? row.price.quote, coverage: nil,
                                          via: model.queriedVias, stations: app.stations)
        guard let first = plan.legs.first, let last = plan.legs.last else { return }
        var draft = TripDraft()
        draft.fromName = first.fromName
        draft.fromStationID = first.fromStationID
        draft.toName = last.toName
        draft.toStationID = last.toStationID
        draft.mode = first.mode
        draft.date = plan.date
        draft.via = first.via
        app.presentAddTrip(draft)
    }

    // MARK: Data

    private func loadExtras(_ row: ConnectionRow, model: PlannerModel) async {
        price = row.price
        calendarFile = PlannerCalendarFile.make(journey: row.journey)
        // The live quote of the whole connection (the cards only asked for the first three).
        if row.price.quote == nil || row.price.quote?.isLive == false, app.live.isLivePriceAvailable || app.live.isDemo {
            price.isLoading = true
            let quote = await app.live.quote(model.priceRequest(for: row.journey, coverage: row.coverage))
            withMotion(Motion.number) { price = PlannerPriceState(quote: quote, isLoading: false, isOffline: false) }
        } else if row.price.quote == nil {
            let quote = await app.live.offlineQuote(model.priceRequest(for: row.journey, coverage: row.coverage))
            price = PlannerPriceState(quote: quote, isLoading: false, isOffline: app.live.priceUnavailable == .offline)
        }
        await loadPolylines(row, model: model)
    }

    /// Lazy polylines per ride leg (the list never asks for them).
    private func loadPolylines(_ row: ConnectionRow, model: PlannerModel) async {
        guard let timetable = app.live.timetable else { return }
        for leg in row.journey.rideLegs where polylines[leg.id] == nil && leg.polyline == nil {
            guard let tripID = leg.tripID else { continue }
            if let details = try? await timetable.trip(tripID, includePolyline: true), let line = details.polyline, line.count >= 2 {
                withMotion(Motion.smooth) { polylines[leg.id] = line }
            }
            if Task.isCancelled { return }
        }
    }

    /// Realtime of this connection every 60 s while the detail is on screen.
    private func refreshLoop(_ model: PlannerModel) async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await model.refreshRows()
        }
    }

    private func mapRoute(_ row: ConnectionRow) -> PlannerMapRoute {
        PlannerMapRoute.make(journey: row.journey, polylines: polylines)
    }

    private func dayText(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.vienna
        if cal.isDateInToday(date) { return "Heute · \(Format.weekdayDayMonth(date))" }
        if cal.isDateInTomorrow(date) { return "Morgen · \(Format.weekdayDayMonth(date))" }
        return Format.weekdayDayMonth(date)
    }

    private func shareText(_ row: ConnectionRow) -> String {
        let s = row.summary
        let from = row.journey.origin.map { DisplayNames.name($0.name) } ?? "", to = row.journey.destination.map { DisplayNames.name($0.name) } ?? ""
        let times = [s.plannedDeparture, s.plannedArrival].compactMap { $0.map(Format.time) }.joined(separator: "–")
        return "\(from) → \(to) · \(Format.weekdayDayMonth(s.plannedDeparture ?? Date())), \(times) · \(s.lineSummary)"
    }
}

// MARK: - Timeline list

/// The stops and legs of a connection on one rail.
private struct TimelineList: View {
    var journey: Journey
    var summary: ConnectionSummary
    @Binding var expanded: Set<String>

    private enum Item: Identifiable {
        case stop(id: String, role: TimelineStopRow.Role, name: String, planned: Date?, event: StopEvent?, caption: String?, above: TimelineRail, below: TimelineRail, footnote: Bool)
        case ride(Leg)
        case walk(id: String, text: String, transfer: TransferInfo?)

        var id: String {
            switch self {
            case .stop(let id, _, _, _, _, _, _, _, _): "s-\(id)"
            case .ride(let leg): "r-\(leg.id)"
            case .walk(let id, _, _): "w-\(id)"
            }
        }
    }

    var body: some View {
        let items = build()
        VStack(spacing: 0) {
            ForEach(items) { item in
                switch item {
                case .stop(_, let role, let name, let planned, let event, let caption, let above, let below, let footnote):
                    TimelineStopRow(role: role, planned: planned,
                                    realtime: event.map(RealtimePresentation.label) ?? RealtimeLabel(state: .scheduled),
                                    name: DisplayNames.make(name), caption: caption,
                                    platform: event.flatMap { JourneyPresentation.platformLabel($0, mode: modeOf(name)) },
                                    above: above, below: below, isFootnote: footnote, showsScheduledHint: true)
                case .ride(let leg):
                    rideView(leg)
                case .walk(_, let text, let transfer):
                    TimelineWalkLeg(text: text, transfer: transfer)
                }
            }
        }
    }

    private func modeOf(_ name: String) -> TransportMode? {
        journey.legs.first { $0.origin.name == name || $0.destination.name == name }?.line?.mode
    }

    private func rideView(_ leg: Leg) -> some View {
        let line = leg.line
        let badge = line.map { LineBadge(line: $0, size: .m) } ?? LineBadge(kind: .sonst, text: "", spoken: "Fahrt")
        let minutes: Int = {
            guard let a = leg.departure.planned ?? leg.departure.effective, let b = leg.arrival.planned ?? leg.arrival.effective else { return 0 }
            return Int(b.timeIntervalSince(a) / 60)
        }()
        let kindText = line?.categoryLong?.trimmingCharacters(in: .whitespaces).nonEmpty ?? line?.operatorName.flatMap { $0 == "Nahreisezug" ? nil : $0 }
        let subtitle = [kindText, minutes > 0 ? JourneyPresentation.durationText(minutes: minutes) : nil].compactMap { $0 }.joined(separator: " · ")
        let stops = leg.intermediateStops.filter { !$0.passesWithoutStop }.enumerated().map { index, stop -> TimelineIntermediateStop in
            let event = stop.departure ?? stop.arrival
            return TimelineIntermediateStop(id: "\(leg.id)-\(index)", time: event?.planned,
                                            realtime: event.map(RealtimePresentation.label) ?? RealtimeLabel(state: .scheduled),
                                            name: DisplayNames.name(stop.location.name))
        }
        let notices = JourneyPresentation.notices(leg.remarks).filter { $0.severity >= .warning }
        return TimelineRideLeg(badge: badge, title: line.map(LinePresentation.title) ?? "Fahrt", direction: leg.direction.map(DisplayNames.name),
                               subtitle: subtitle.isEmpty ? nil : subtitle, attributes: JourneyPresentation.attributes(leg.remarks),
                               stops: stops, color: PlannerPalette.stroke(for: line?.mode ?? .train), notices: notices,
                               isCancelled: leg.isCancelled,
                               isExpanded: Binding(get: { expanded.contains(leg.id) },
                                                   set: { if $0 { expanded.insert(leg.id) } else { expanded.remove(leg.id) } }))
    }

    /// Stops at the boundaries of the legs, ride legs between them, walks and changes dotted.
    private func build() -> [Item] {
        var items: [Item] = []
        let legs = journey.legs
        var transfers = summary.transfers[...]
        for (index, leg) in legs.enumerated() {
            let previous = index > 0 ? legs[index - 1] : nil
            let next = index + 1 < legs.count ? legs[index + 1] : nil
            let railBefore = rail(for: previous), railHere = rail(for: leg), railAfter = rail(for: next)
            let isFootnoteStart = index == 0 && leg.kind != .ride
            // A stop row opens the journey and every place the traveller is on foot or changes.
            if index == 0 {
                let caption: String? = {
                    guard leg.kind == .ride, let t = leg.departure.effective, t > Date() else { return nil }
                    let m = Int(t.timeIntervalSinceNow / 60)
                    return m < 1 ? "Abfahrt jetzt" : "Abfahrt in \(m) min"
                }()
                items.append(.stop(id: "\(leg.id)-o", role: .start, name: leg.origin.name, planned: leg.departure.planned, event: leg.departure,
                                   caption: caption, above: .none, below: railHere, footnote: isFootnoteStart))
            } else if previous?.kind != .ride, leg.kind == .ride {
                // After a walk: the stop where the next ride starts.
                items.append(.stop(id: "\(leg.id)-o", role: .transfer, name: leg.origin.name, planned: leg.departure.planned, event: leg.departure,
                                   caption: nil, above: railBefore, below: railHere, footnote: false))
            }
            switch leg.kind {
            case .ride:
                items.append(.ride(leg))
                let isLast = next == nil
                items.append(.stop(id: "\(leg.id)-d", role: isLast ? .end : .transfer, name: leg.destination.name,
                                   planned: leg.arrival.planned, event: leg.arrival, caption: "Ankunft",
                                   above: railHere, below: isLast ? .none : railAfter, footnote: false))
            case .walk, .transfer:
                let info: TransferInfo? = (previous?.kind == .ride && next?.kind == .ride && !transfers.isEmpty) ? transfers.removeFirst() : nil
                items.append(.walk(id: leg.id, text: walkText(leg), transfer: info))
                if next == nil {
                    // A trailing walk ends at its own stop (address, POI).
                    items.append(.stop(id: "\(leg.id)-d", role: .end, name: leg.destination.name, planned: leg.arrival.planned, event: leg.arrival,
                                       caption: "Ziel", above: .walk, below: .none, footnote: true))
                }
            }
        }
        return items
    }

    private func rail(for leg: Leg?) -> TimelineRail {
        guard let leg else { return .none }
        return leg.kind == .ride ? .ride(PlannerPalette.stroke(for: leg.line?.mode ?? .train)) : .walk
    }

    private func walkText(_ leg: Leg) -> String {
        let minutes: Int = {
            if let a = leg.departure.effective, let b = leg.arrival.effective { return max(1, Int((b.timeIntervalSince(a) / 60).rounded())) }
            return max(1, (leg.walkDurationSeconds ?? 60) / 60)
        }()
        if leg.kind == .transfer { return "Umstieg · \(minutes) min" }
        var text = "\(minutes) min Fußweg"
        let sub = DisplayNames.make(leg.destination.name).sub
        if let meters = leg.walkDistanceMeters, meters > 0 { text += " · \(meters) m" + (sub.map { " zum \($0)" } ?? "") }
        else if let sub { text += " · zum \(sub)" }
        return text
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Price info popover

/// „Woher kommt der Preis?“ – the source, when it was asked, other prices found, and the rule.
struct PriceInfoPopover: View {
    var quote: PriceQuote

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            PriceSourceBadge(source: PriceSourceBadge.Source(quote: quote))
            Text(quote.explanation).font(.subheadline).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            if let fetched = quote.fetchedAt {
                Text("abgefragt \(Format.dayMonth(fetched)), \(Format.time(fetched))").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if !quote.alternatives.isEmpty {
                Divider()
                ForEach(Array(quote.alternatives.enumerated()), id: \.offset) { _, alternative in
                    Text(alternative.text).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Divider()
            Text("Normalpreis: das reguläre Einzelticket am Reisetag. Ohne Gewähr.").font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Spacing.m)
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: - Calendar and shop

/// A one-event .ics file of the connection (shared through the share sheet: „In den Kalender“).
enum PlannerCalendarFile {
    static func make(journey: Journey) -> URL? {
        guard let start = journey.departure?.planned, let end = journey.arrival?.planned else { return nil }
        let from = journey.origin.map { DisplayNames.name($0.name) } ?? "", to = journey.destination.map { DisplayNames.name($0.name) } ?? ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let lines = journey.rideLegs.map { leg -> String in
            let name = leg.line.map(LinePresentation.title) ?? "Fahrt"
            let dep = leg.departure.planned.map(Format.time) ?? "", arr = leg.arrival.planned.map(Format.time) ?? ""
            return "\(dep) \(DisplayNames.name(leg.origin.name)) → \(arr) \(DisplayNames.name(leg.destination.name)) (\(name))"
        }
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: "\n", with: "\\n") }
        let ics = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//KlimaBilanz//Fahrplan//DE", "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)@klimabilanz", "DTSTAMP:\(formatter.string(from: Date()))",
            "DTSTART:\(formatter.string(from: start))", "DTEND:\(formatter.string(from: end))",
            "SUMMARY:\(escape("\(from) → \(to)"))", "LOCATION:\(escape(from))", "DESCRIPTION:\(escape(lines.joined(separator: "\n")))",
            "END:VEVENT", "END:VCALENDAR",
        ].joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appending(path: "Fahrt \(from) nach \(to).ics", directoryHint: .notDirectory)
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// The ÖBB shop opens in a Safari view controller (never in-app purchase, docs/OEBB_LIVE.md §2).
struct PlannerSafariSheet: View {
    var url: URL
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if canImport(SafariServices)
        SafariRepresentable(url: url).ignoresSafeArea()
        #else
        Color.clear.onAppear { openURL(url); dismiss() }
        #endif
    }
}

#if canImport(SafariServices)
private struct SafariRepresentable: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
