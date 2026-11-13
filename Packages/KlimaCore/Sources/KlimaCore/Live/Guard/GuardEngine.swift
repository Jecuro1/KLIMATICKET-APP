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

public struct GuardEngine: Sendable {
    public private(set) var record: GuardRecord
    public private(set) var memory = GuardMemory()
    public private(set) var requests = GuardRequestState()
    public private(set) var assessment: GuardAssessment?
    public private(set) var lastAlternativesSearchAt: Date?
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
        GuardPlan.hasEnded(state: assessment?.state, window: window, createdAt: record.createdAt, now: now)
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
            applyFailure(kind: .reconstruction, countsForFallback: true, sentAt: sentAt, manual: manual)
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

    public mutating func applyFailure(kind: GuardRequestKind, countsForFallback: Bool, sentAt: Date, manual: Bool = false) {
        requests = GuardPlan.record(requests, kind: kind, sentAt: sentAt, outcome: .failed(countsForFallback: countsForFallback),
                                    manual: manual)
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
            followSnapshot: record.feederRide == 0 ? followSnapshot : nil, followAt: followAt, journeyAt: record.journeyAt,
            connectionTrip: connectionTrip, connectionTripAt: connectionTripAt, previous: memory, now: now) else { return .none }
        assessment = result.assessment
        memory = result.memory
        let current = result.assessment.state
        let worsened = previous.map { current.rank > $0.rank && current != .over } ?? false
        let entered = current.searchesAlternatives && !(previous?.searchesAlternatives ?? false)
        let search = entered && GuardAlternatives.canSearch(lastSearchAt: lastAlternativesSearchAt, now: now)
        return GuardChange(previous: previous, current: current, worsened: worsened, searchAlternatives: search)
    }

    public mutating func setSwitchedOff(_ off: Bool) { record.switchedOff = off }

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
