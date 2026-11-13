import SwiftUI
import KlimaCore

// MARK: commute – the card's quick actions (also its context menu and VoiceOver custom actions): „Fahrt erfassen“ (the trip
// editor, prefilled), „Live verfolgen“ (the existing follow, first connection), „Rückfahrt planen“ and „Verbindung ändern“
// (the Fahrplan, prefilled). „Ja, merken“ / „Nein“ of the invitation live here too.

@MainActor
struct CommuteActions {
    let app: AppState
    var model: CommuteModel = .shared

    private var settings: CommuteSettings { model.settings }

    /// „Fahrt erfassen“: the editor with the route – round trip when that is the remembered choice (then always from home),
    /// else the direction of the time of day. The user saves (and can change anything) in the editor.
    func logTrip(now: Date) {
        let direction: CommuteDirection = settings.logsRoundTrip
            ? .outbound : CommuteWindow.direction(at: now, plan: settings.plan, calendar: .vienna)
        guard let ends = model.ends(direction) else { return }
        var draft = TripDraft()
        draft.fromStationID = ends.from.stationID
        draft.toStationID = ends.to.stationID
        draft.fromName = ends.from.name
        draft.toName = ends.to.name
        draft.mode = settings.mode
        draft.isRoundTrip = settings.logsRoundTrip
        draft.date = LaunchMode.isSandboxed ? Date() : now
        app.presentAddTrip(draft)
    }

    /// The follow target of a row's first ride (nil without live data or without a run id).
    func followTarget(_ row: CommuteRow) -> LiveFollowTarget? {
        guard model.liveUnavailable(app.live) == nil, let journey = model.journey(for: row),
              let leg = journey.rideLegs.first, let tripID = leg.tripID, !row.isCancelled else { return nil }
        let transfer = journey.rideLegs.dropFirst().first.flatMap { next -> FollowTransfer? in
            guard let planned = next.departure.planned else { return nil }
            return FollowTransfer(stationName: next.origin.name, plannedDeparture: planned, lineName: next.line.map { LinePresentation.title($0) })
        }
        return LiveFollowTarget(tripID: tripID, lineName: leg.line.map { LinePresentation.title($0) } ?? row.lineTitle,
                                boardingStop: leg.origin, alightStop: leg.destination,
                                plannedDeparture: leg.departure.planned, plannedArrival: leg.arrival.planned, transfer: transfer)
    }

    /// „Live verfolgen“ for a row (the existing follow; its Live Activity and notices follow their own switches).
    func follow(_ row: CommuteRow) {
        guard let target = followTarget(row) else { return }
        LiveFollowTracker.shared.start(target, live: app.live)
        app.showToast("location.fill", "Live verfolgen", "\(row.lineTitle) · \(row.timeText)", haptic: .start)
    }

    /// „Rückfahrt planen“: the Fahrplan the other way, at the plan's time of that direction when it is still ahead today.
    func planReturn(shown direction: CommuteDirection, now: Date) {
        let back = direction.opposite
        guard let ends = model.ends(back) else { return }
        let cal = Calendar.vienna
        let planned = CommuteWindow.departure(on: cal.startOfDay(for: now), minute: settings.plan.minute(for: back), calendar: cal)
        openPlanner(from: ends.from, to: ends.to, at: planned.flatMap { $0 > now ? $0 : nil })
    }

    /// „Verbindung ändern“: the Fahrplan with the shown direction from now on – every option of the planner.
    func changeConnection(shown direction: CommuteDirection) {
        guard let ends = model.ends(direction) else { return }
        openPlanner(from: ends.from, to: ends.to, at: nil)
    }

    private func openPlanner(from: CommuteEndpoint, to: CommuteEndpoint, at: Date?) {
        app.selectedTab = .planner
        app.planner.handleDeepLink(PlannerLink(from: from.stationID ?? from.name, to: to.stationID ?? to.name, at: at))
    }

    // MARK: Invitation

    /// „Ja, merken“: the guess becomes the Stammstrecke. Weekdays and times come from a saved route of the same pair when there
    /// is one (its RouteSchedule), else from the guess, else the defaults (07:00 / 17:00).
    func accept(_ guess: CommuteGuess, savedRoutes: [FavoriteRouteEntity]) {
        let match = CommuteSetup.savedRoute(for: guess, in: savedRoutes)
        model.store.update { s in
            s.isEnabled = true
            s.origin = guess.origin
            s.destination = guess.destination
            s.source = match == nil ? .suggestion : .savedRoute
            s.savedRouteID = match?.id
            s.plan = CommuteSetup.plan(guess: guess, route: match)
            s.mode = match?.mode ?? .train
            s.logsRoundTrip = guess.mostlyRoundTrips
        }
        model.settingsChanged()
        app.showToast("checkmark.circle.fill", "Stammstrecke gemerkt",
                      "\(TripRow.short(guess.origin.name)) ⇄ \(TripRow.short(guess.destination.name))", haptic: .success)
    }

    /// „Nein“: this pair stays quiet for 30 days („Rückgängig“ in the toast).
    func decline(_ guess: CommuteGuess) {
        let key = guess.pairKey
        model.store.decline(pairKey: key)
        let store = model.store
        app.showToast("hand.raised.fill", "Kein Arbeitsweg", "Fragt 30 Tage nicht mehr nach", actionTitle: "Rückgängig", haptic: .tap) {
            store.undoDecline(pairKey: key)
        }
    }
}

/// Prefilling the plan from a saved route („Meine Routen“) and a guess.
enum CommuteSetup {
    /// The Übersicht asks „Ist das dein Arbeitsweg?“ only for a confident guess with two app stations (else „Ja, merken“ would
    /// end in „Stammstrecke fehlt“), not declined in the last 30 days, and not the stored route of a mode that is switched off.
    static func invitation(guess: CommuteGuess?, settings: CommuteSettings, now: Date) -> CommuteGuess? {
        guard let guess, guess.confidence == .high, !settings.isEnabled,
              guess.origin.stationID?.isEmpty == false, guess.destination.stationID?.isEmpty == false,
              !settings.isDeclined(guess.pairKey, now: now) else { return nil }
        if let origin = settings.origin, let destination = settings.destination,
           CommuteDetector.pairKey(origin, destination) == guess.pairKey { return nil }
        return guess
    }

    /// A saved route between the guess's two stations, either direction (outbound first).
    @MainActor
    static func savedRoute(for guess: CommuteGuess, in routes: [FavoriteRouteEntity]) -> FavoriteRouteEntity? {
        let key = guess.pairKey
        let live = routes.filter { $0.deletedAt == nil }
        let pairs = live.filter {
            CommuteDetector.pairKey(CommuteEndpoint(stationID: $0.fromStationID, name: $0.fromName),
                                    CommuteEndpoint(stationID: $0.toStationID, name: $0.toName)) == key
        }
        return pairs.first { $0.fromStationID == guess.origin.stationID && $0.schedule != nil }
            ?? pairs.first { $0.schedule != nil } ?? pairs.first
    }

    /// The route's schedule gives weekdays and the outbound time; the guess fills what the route does not know.
    @MainActor
    static func plan(guess: CommuteGuess?, route: FavoriteRouteEntity?) -> CommutePlan {
        let returnMinute = guess?.returnMinute ?? CommutePlan.defaultReturnMinute
        if let schedule = route?.schedule, !schedule.weekdays.isEmpty {
            return CommutePlan(schedule: schedule, returnMinute: returnMinute)
        }
        let weekdays = (guess?.weekdays.count ?? 0) >= 2 ? (guess?.weekdays ?? CommutePlan.workdays) : CommutePlan.workdays
        return CommutePlan(weekdays: weekdays, outboundMinute: guess?.outboundMinute ?? CommutePlan.defaultOutboundMinute,
                           returnMinute: returnMinute)
    }
}
