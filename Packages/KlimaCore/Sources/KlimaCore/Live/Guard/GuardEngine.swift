import Foundation

// Anschluss-Wächter, the whole guard of one follow as a value (docs/CONNECTION_GUARD.md §4): the record, the memory of the
// assessment, the request history and the alternatives limit. The app service (`ConnectionGuardService`) only adds the
// clock, the network closures and the observation; every decision is made here, so it is tested on Linux.

/// What an update changed, for the toast, the haptic and the automatic alternatives.
public struct GuardChange: Sendable, Hashable {
    public var previous: GuardState?
    public var current: GuardState?
    /// The shown state got worse (not on the first assessment, not for „Umstieg vorbei“): one toast and one `.warning`.
    public var worsened: Bool
    /// The state just entered „Wahrscheinlich verpasst“, „Verpasst“ or „Fällt aus“ and a search is allowed: one TripSearch.
    public var searchAlternatives: Bool

    public static let none = GuardChange(previous: nil, current: nil, worsened: false, searchAlternatives: false)
}

/// What the card offers at one moment (docs/CONNECTION_GUARD.md §8). Decided here, so the card never shows a button that
/// does nothing – „Jetzt prüfen“ after the end was such a button.
public struct GuardActions: Sendable, Hashable {
    public enum Alternatives: Sendable, Hashable {
        /// Not offered.
        case none
        /// In the card's menu.
        case menu
        /// A full-width button under the prominent one (after a short „Umstieg vorbei“).
        case button
        /// The prominent full-width button (shaky or worse).
        case prominent
    }

    /// „REX 41 weiter verfolgen“ (after „Umstieg vorbei“).
    public var continueFollow: Bool
    public var alternatives: Alternatives
    /// „Jetzt prüfen“: only while the guard runs and is on.
    public var checkNow: Bool
    /// „Wecker fürs Umsteigen“: while the guard runs, after its end only while the feeder has not arrived yet.
    public var alarm: Bool
    /// „Wächter aus“ / „Wächter an“: only while the guard runs.
    public var toggleSwitch: Bool

    public init(continueFollow: Bool = false, alternatives: Alternatives = .none, checkNow: Bool = false, alarm: Bool = false,
                toggleSwitch: Bool = false) {
        self.continueFollow = continueFollow
        self.alternatives = alternatives
        self.checkNow = checkNow
        self.alarm = alarm
        self.toggleSwitch = toggleSwitch
    }

    /// The card shows its „…“ menu.
    public var hasMenu: Bool { toggleSwitch || alternatives == .menu }
    /// The row of side-by-side buttons has anything in it.
    public var hasRow: Bool { checkNow || alarm || hasMenu }
}

public struct GuardEngine: Sendable {
    public private(set) var record: GuardRecord
    public private(set) var memory = GuardMemory()
    public private(set) var requests = GuardRequestState()
    public private(set) var assessment: GuardAssessment?
    public private(set) var lastAlternativesSearchAt: Date?
    /// The guard has ended and stopped (`finish`): it asks nothing any more, its switch and its record stay as they are (the
    /// file is gone). Data that comes anyway – the follow's answer of the feeder, an answer still on its way – still counts:
    /// an end computed from an old answer („Umstieg vorbei“ after a long time in the background) gives way to „Verpasst“ when a
    /// fresher one says the feeder came after the departure.
    public private(set) var isFinished = false
    private var followSnapshot: LiveFollowSnapshot?
    private var followAt: Date?
    private var connectionTrip: TripDetails?
    private var connectionTripAt: Date?

    public init(record: GuardRecord) {
        self.record = record
    }

    // MARK: Reading

    public var state: GuardState? { assessment?.state }

    /// The window of the automatic checks (feeder's planned departure − 30 min … connecting departure + 5 min).
    public var window: DateInterval? {
        guard let (a, b) = ConnectionGuard.legIndices(record.journey, feederRide: record.feederRide) else { return nil }
        let departure = assessment?.connectionDeparture ?? record.journey.legs[b].departure.effective
        return GuardPlan.window(feederPlannedDeparture: record.journey.legs[a].departure.planned, connectionDeparture: departure)
    }

    /// „Umstieg vorbei“, past the window, or the record is older than 12 h.
    public func hasEnded(now: Date) -> Bool {
        isFinished || GuardPlan.hasEnded(state: assessment?.state, window: window, createdAt: record.createdAt, now: now)
    }

    /// Why the guard is over (nil while it runs).
    public func endReason(now: Date) -> GuardEndReason? {
        GuardPlan.endReason(state: assessment?.state, window: window, createdAt: record.createdAt, now: now)
            ?? (isFinished ? .windowPassed : nil)
    }

    /// What the card offers now.
    public func actions(now: Date) -> GuardActions {
        guard let a = assessment else { return GuardActions() }
        let warning = a.state.rank >= GuardState.shaky.rank
        if a.state == .over {
            // The change is behind you; when only the walk did not fit, the alternatives stay at hand.
            return GuardActions(continueFollow: continuation != nil, alternatives: a.overShort ? .button : .none)
        }
        if hasEnded(now: now) {
            let arrivalAhead = a.feederArrival.map { $0 > now } ?? false
            return GuardActions(alternatives: warning ? .prominent : .none, alarm: arrivalAhead)
        }
        return GuardActions(alternatives: warning ? .prominent : .menu, checkNow: !record.switchedOff, alarm: true, toggleSwitch: true)
    }

    /// The trip id of the connecting ride (the fallback's JourneyDetails).
    public var connectionTripID: String? {
        guard let (_, b) = ConnectionGuard.legIndices(record.journey, feederRide: record.feederRide) else { return nil }
        return record.journey.legs[b].tripID
    }

    /// What the follow's „Anschluss knapp“ notice should count with (§4.6): the expected connecting departure and the walk.
    public var transferEstimate: (expectedDeparture: Date, observedAt: Date, walkMinutes: Int?)? {
        guard let a = assessment, let departure = a.connectionDeparture else { return nil }
        return (departure, a.connectionDataAt, a.walkKnown ? a.walkMinutes : nil)
    }

    public func decision(conditions: GuardConditions, returnedToForeground: Bool = false, now: Date) -> GuardDecision {
        if record.switchedOff { return .idle(.switchedOff) }
        return GuardPlan.next(conditions: conditions, requests: planRequests, shown: assessment?.state, window: window,
                              ended: hasEnded(now: now), returnedToForeground: returnedToForeground, now: now)
    }

    public func manualDecision(conditions: GuardConditions, now: Date) -> GuardManualDecision {
        if record.switchedOff { return .unavailable(.switchedOff) }
        return GuardPlan.manual(conditions: conditions, requests: planRequests, ended: hasEnded(now: now), now: now)
    }

    /// The fallback needs the connecting trip's id; without one the guard keeps asking the Reconstruction.
    private var planRequests: GuardRequestState {
        var r = requests
        if r.usesFallback, connectionTripID == nil { r.usesFallback = false }
        return r
    }

    // MARK: Requests

    /// A request is on its way (never two).
    public mutating func begin() { requests.inFlight = true }

    /// A Reconstruction answer asked at `sentAt`. An answer without the watched change counts as a failure.
    public mutating func applyReconstruction(_ journey: Journey, sentAt: Date, manual: Bool = false, now: Date) -> GuardChange {
        guard ConnectionGuard.legIndices(journey, feederRide: record.feederRide) != nil else {
            applyFailure(kind: .reconstruction, countsForFallback: true, reason: .answerUnusable, sentAt: sentAt, manual: manual)
            return .none
        }
        requests = GuardPlan.record(requests, kind: .reconstruction, sentAt: sentAt, outcome: .answered, manual: manual)
        record = record.updated(journey: journey, at: sentAt)
        return reassess(now: now)
    }

    /// A JourneyDetails answer of the connecting trip (fallback) asked at `sentAt`.
    public mutating func applyConnectionTrip(_ trip: TripDetails, sentAt: Date, manual: Bool = false, now: Date) -> GuardChange {
        requests = GuardPlan.record(requests, kind: .connectionTrip, sentAt: sentAt, outcome: .answered, manual: manual)
        connectionTrip = trip
        connectionTripAt = trip.fetchedAt ?? sentAt
        return reassess(now: now)
    }

    public mutating func applyFailure(kind: GuardRequestKind, countsForFallback: Bool, reason: GuardFailure = .auskunft, sentAt: Date,
                                      manual: Bool = false) {
        requests = GuardPlan.record(requests, kind: kind, sentAt: sentAt,
                                    outcome: .failed(countsForFallback: countsForFallback, reason: reason), manual: manual)
    }

    /// A failed request with the error that ended it: the reason for the card and whether it counts towards the fallback.
    /// `circuitOpenUntil`: the app's circuit for the Auskunft right after the failure (tells a 429 from the app's own limit).
    public mutating func applyFailure(kind: GuardRequestKind, error: LiveError, circuitOpenUntil: Date? = nil, sentAt: Date,
                                      manual: Bool = false) {
        applyFailure(kind: kind, countsForFallback: GuardFailure.countsForFallback(error),
                     reason: GuardFailure(error, circuitOpenUntil: circuitOpenUntil), sentAt: sentAt, manual: manual)
    }

    /// The request was dropped before it went out (cancelled, the guard changed): nothing recorded but the flight.
    public mutating func abandon() { requests.inFlight = false }

    // MARK: Follow, time, switch

    /// The follow's latest JourneyDetails answer of the feeder (asked at `at`); no request.
    public mutating func followUpdated(_ snapshot: LiveFollowSnapshot, at: Date, now: Date) -> GuardChange {
        if let followAt, at <= followAt { return reassess(now: now) }
        followSnapshot = snapshot
        followAt = at
        return reassess(now: now)
    }

    /// Recomputes with the data at hand (time moves: „Verpasst“, „Umstieg vorbei“, the trend window).
    public mutating func reassess(now: Date) -> GuardChange {
        let previous = assessment?.state
        guard let result = ConnectionGuard.assess(
            journey: record.journey, feederRide: record.feederRide,
            followSnapshot: followSnapshot, followAt: followAt, journeyAt: record.journeyAt,
            connectionTrip: connectionTrip, connectionTripAt: connectionTripAt, previous: memory, now: now) else { return .none }
        assessment = result.assessment
        memory = result.memory
        let current = result.assessment.state
        let worsened = previous.map { current.rank > $0.rank && current != .over } ?? false
        let entered = current.searchesAlternatives && !(previous?.searchesAlternatives ?? false)
        let search = entered && GuardAlternatives.canSearch(lastSearchAt: lastAlternativesSearchAt, now: now)
        return GuardChange(previous: previous, current: current, worsened: worsened, searchAlternatives: search)
    }

    /// „Wächter aus“ / „Wächter an“; after the end nothing changes (the record is gone and must not come back).
    @discardableResult
    public mutating func setSwitchedOff(_ off: Bool) -> Bool {
        guard !isFinished else { return false }
        record.switchedOff = off
        return true
    }

    /// The guard has ended (`hasEnded`): it stops for good – also when fresher data turns „Umstieg vorbei“ into „Verpasst“
    /// before the window's end.
    public mutating func finish() {
        isFinished = true
        requests.inFlight = false
    }

    // MARK: Weiter verfolgen

    /// After „Umstieg vorbei“: the connecting ride as the next follow (with its own change, if any), and the ride index a new
    /// guard watches from (nil when the journey ends there).
    public var continuation: (target: LiveFollowTarget, nextFeederRide: Int?)? {
        guard assessment?.state == .over,
              let target = GuardAlternatives.followTarget(record.journey, ride: record.feederRide + 1) else { return nil }
        let next = record.feederRide + 1
        return (target, ConnectionGuard.canWatch(record.journey, followTripID: target.tripID, feederRide: next) ? next : nil)
    }

    // MARK: Alternatives

    /// The TripSearch for the alternatives, or nil when the three-minute limit holds (`force` is never needed: the limit is
    /// per guard, automatic or not).
    public func alternativesQuery(now: Date) -> JourneyQuery? {
        guard GuardAlternatives.canSearch(lastSearchAt: lastAlternativesSearchAt, now: now) else { return nil }
        return GuardAlternatives.query(journey: record.journey, feederRide: record.feederRide, assessment: assessment,
                                       products: record.products, now: now)
    }

    public mutating func alternativesSearched(at: Date) { lastAlternativesSearchAt = at }
}
