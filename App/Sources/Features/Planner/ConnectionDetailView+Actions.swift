import SwiftUI
import SwiftData
import KlimaCore

// The action bar, logging, the follow target and data loading of the connection detail (split from ConnectionDetailView.swift).

extension ConnectionDetailView {
    // MARK: Action bar

    @ViewBuilder
    func actionBar(_ row: ConnectionRow, amount: Double?, model: PlannerModel) -> some View {
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

    func logNow(_ row: ConnectionRow, amount: Double?, model: PlannerModel) {
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

    func loadExtras(_ row: ConnectionRow, model: PlannerModel) async {
        price = row.price
        calendarFile = PlannerCalendarFile.make(journey: row.journey)
        reminderFire = await PlannerReminders.pendingFireDate(journeyID: row.journey.id)
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
    func refreshLoop(_ model: PlannerModel) async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await model.refreshRows()
        }
    }

    func mapRoute(_ row: ConnectionRow) -> PlannerMapRoute {
        PlannerMapRoute.make(journey: row.journey, polylines: polylines)
    }

    func dayText(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.vienna
        if cal.isDateInToday(date) { return "Heute · \(Format.weekdayDayMonth(date))" }
        if cal.isDateInTomorrow(date) { return "Morgen · \(Format.weekdayDayMonth(date))" }
        return Format.weekdayDayMonth(date)
    }
}

// MARK: scotty – the follow target of a connection
extension ConnectionDetailView {
    /// The first ride leg as a follow target; nil without live data or without a trip id.
    func followTarget(_ row: ConnectionRow) -> LiveFollowTarget? {
        guard app.live.timetable != nil, let leg = row.journey.rideLegs.first, let tripID = leg.tripID else { return nil }
        // The next ride leg: the user changes trains after this one (docs/OEBB_LIVE.md §R8). Walking time between two
        // stations is not subtracted from the spare time, so a tight-transfer notice is a warning, not a timetable.
        let transfer = row.journey.rideLegs.dropFirst().first.flatMap { next -> FollowTransfer? in
            guard let planned = next.departure.planned else { return nil }
            return FollowTransfer(stationName: next.origin.name, plannedDeparture: planned,
                                  lineName: next.line.map { LinePresentation.title($0) })
        }
        return LiveFollowTarget(tripID: tripID, lineName: leg.line.map { LinePresentation.title($0) } ?? "Verbindung",
                                boardingStop: leg.origin, alightStop: leg.destination,
                                plannedDeparture: leg.departure.planned, plannedArrival: leg.arrival.planned,
                                transfer: transfer)
    }
}
