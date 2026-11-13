import Foundation

// Anschluss-Wächter (docs/CONNECTION_GUARD.md §2–3): „Erwische ich meinen Anschluss?“ while the user rides. Pure and
// clock-injected: the app feeds the followed connection (planner answer or Reconstruction), the follow's latest
// JourneyDetails answer of the feeder and, after two failed Reconstructions, the JourneyDetails answer of the connecting
// trip. Out come the spare minutes (the formula of the connection detail), the state with trend and hysteresis, and the
// figures the card shows. Nothing here asks the network.

/// How the change looks. Our own rules, written down in docs/CONNECTION_GUARD.md §3 – the Auskunft never says whether a
/// train waits, so no state claims that.
public enum GuardState: String, Sendable, Hashable, Codable, CaseIterable {
    /// Five minutes or more to spare and not shrinking (or shrinking but still ten or more).
    case safe
    /// Two to four minutes, or five and more but two less than ten minutes ago.
    case tighter
    /// Zero or one minute, one minute short, or the Auskunft marks the connection as not reachable.
    case shaky
    /// Two or more minutes short while the connecting train has not left yet – a forecast from both trains' predictions.
    case likelyMissed
    /// The connecting departure has passed while the feeder had not arrived – a fact of the data.
    case missed
    /// The feeder or the connection is cancelled, or one of them does not stop at the transfer station.
    case cancelled
    /// Neither train has a realtime value: computed from the timetable.
    case scheduled
    /// Two minutes after the connecting departure with time to spare: the change is behind you, the guard ends.
    case over

    /// Worse is higher. „Nach Fahrplan“ ranks with „Sicher“ (no warning); „Umstieg vorbei“ is the end, not a level.
    public var rank: Int {
        switch self {
        case .over: return -1
        case .safe, .scheduled: return 0
        case .tighter: return 1
        case .shaky: return 2
        case .likelyMissed: return 3
        case .missed: return 4
        case .cancelled: return 5
        }
    }

    /// Worth a badge, a toast and the faster check cadence.
    public var isWarning: Bool { rank > 0 }
    /// The state opens the alternatives on its own (one search, docs/CONNECTION_GUARD.md §5).
    public var searchesAlternatives: Bool { self == .likelyMissed || self == .missed || self == .cancelled }
}

/// Where the spare minutes are heading over the last ten minutes.
public enum GuardTrend: String, Sendable, Hashable, Codable {
    case falling, steady, rising
}

/// One buffer value at the time of the answer it came from.
public struct GuardSample: Sendable, Hashable, Codable {
    public var at: Date
    public var minutes: Int

    public init(at: Date, minutes: Int) {
        self.at = at
        self.minutes = minutes
    }
}

/// Which train a cancellation hit.
public enum GuardLegRole: String, Sendable, Hashable, Codable {
    case feeder, connection
}

/// One side of the change as the card shows it: the feeder's arrival or the connection's departure at the transfer station.
public struct GuardLegFigure: Sendable, Hashable {
    public var lineName: String
    public var planned: Date?
    /// The realtime forecast, nil without realtime.
    public var expected: Date?
    /// Whole minutes late (negative: early), rounded as the planner does; nil without realtime.
    public var delayMinutes: Int?
    public var platform: String?
    public var plannedPlatform: String?
    public var platformChanged: Bool
    /// True for a bus or tram bay („Steig“), false for a track („Gleis“).
    public var isStand: Bool
    public var isCancelled: Bool

    public init(lineName: String, planned: Date? = nil, expected: Date? = nil, delayMinutes: Int? = nil, platform: String? = nil,
                plannedPlatform: String? = nil, platformChanged: Bool = false, isStand: Bool = false, isCancelled: Bool = false) {
        self.lineName = lineName
        self.planned = planned
        self.expected = expected
        self.delayMinutes = delayMinutes
        self.platform = platform
        self.plannedPlatform = plannedPlatform
        self.platformChanged = platformChanged
        self.isStand = isStand
        self.isCancelled = isCancelled
    }

    /// Realtime when known, else planned.
    public var effective: Date? { expected ?? planned }
    public var hasRealtime: Bool { expected != nil }

    static func make(_ event: StopEvent, line: Line?, fallbackName: String, mode: TransportMode?) -> GuardLegFigure {
        let label = RealtimePresentation.label(event)
        let platform = JourneyPresentation.platformLabel(event, mode: mode)
        return GuardLegFigure(lineName: line.map { LinePresentation.title($0) } ?? fallbackName, planned: event.planned,
                              expected: event.realtime, delayMinutes: event.realtime == nil ? nil : label.delayMinutes,
                              platform: platform?.display, plannedPlatform: platform?.planned,
                              platformChanged: platform?.changed ?? false, isStand: platform.map { $0.label == "Steig" } ?? false,
                              isCancelled: event.isCancelled)
    }
}

/// A change after the watched one, as a plain line („Danach: Umstieg in …, 12 Min laut Fahrplan“).
public struct GuardLaterTransfer: Sendable, Hashable {
    public var stationName: String
    /// Spare minutes by the timetable (planned times, walk subtracted); nil when a planned time is missing.
    public var plannedBufferMinutes: Int?

    public init(stationName: String, plannedBufferMinutes: Int?) {
        self.stationName = stationName
        self.plannedBufferMinutes = plannedBufferMinutes
    }
}

/// What the card shows for one moment.
public struct GuardAssessment: Sendable, Hashable {
    /// The state on screen (after the hysteresis).
    public var state: GuardState
    /// The state the latest data says on its own.
    public var rawState: GuardState
    /// Connecting departure − feeder arrival − walk in whole minutes; nil when a time is missing.
    public var bufferMinutes: Int?
    public var walkMinutes: Int
    /// The connection has a walk or change leg between the two rides; without one the walk counts as 0 („Fußweg nicht bekannt“).
    public var walkKnown: Bool
    public var trend: GuardTrend
    /// The sample the trend compares with (the highest of the last ten minutes when falling, the lowest when rising).
    public var trendReference: GuardSample?
    /// At least two answers of the last ten minutes: a trend (also „Gleichbleibend“) can be said at all.
    public var hasTrendHistory: Bool
    /// Display name of the transfer station („St. Pölten Hbf“).
    public var stationName: String
    public var feeder: GuardLegFigure
    public var connection: GuardLegFigure
    public var cancelledLeg: GuardLegRole?
    /// The Auskunft marks the connection as not reachable (`isRchbl` false). Meaning unverified: shown as a note, caps at „Wackelt“.
    public var flaggedUnreachable: Bool
    /// Neither train has a realtime value.
    public var basedOnPlan: Bool
    /// Departure of the feeder at the boarding stop (realtime, else planned): a cancelled feeder that has not left yet
    /// searches alternatives from the boarding stop.
    public var feederDeparture: Date?
    /// Time of the newest answer behind these numbers (request time).
    public var dataAt: Date
    /// Time of the answer behind the connecting departure (Reconstruction, or its JourneyDetails in the fallback).
    public var connectionDataAt: Date
    public var laterTransfers: [GuardLaterTransfer]

    /// The connecting departure the guard counts with (realtime, else planned).
    public var connectionDeparture: Date? { connection.effective }
    /// The feeder's arrival at the transfer station the guard counts with.
    public var feederArrival: Date? { feeder.effective }
}

/// What the guard remembers between two assessments (memory only, docs/CONNECTION_GUARD.md §7).
public struct GuardMemory: Sendable, Hashable {
    public var shown: GuardState?
    /// A better state seen once; shown when the next new answer agrees.
    public var pendingBetter: GuardState?
    public var samples: [GuardSample]
    /// Time of the newest answer merged so far.
    public var lastAnswerAt: Date?

    public init(shown: GuardState? = nil, pendingBetter: GuardState? = nil, samples: [GuardSample] = [], lastAnswerAt: Date? = nil) {
        self.shown = shown
        self.pendingBetter = pendingBetter
        self.samples = samples
        self.lastAnswerAt = lastAnswerAt
    }
}

public enum ConnectionGuard {
    /// Trend window: samples older than this are dropped.
    public static let trendWindow: TimeInterval = 10 * 60
    /// A change of at least this many minutes against the window's extreme is a trend.
    public static let trendStep = 2
    /// Falling but still at least this many minutes: „Sicher“ stays.
    public static let calmMinutes = 10
    /// „Umstieg vorbei“ this long after the connecting departure.
    public static let overDelay: TimeInterval = 2 * 60

    /// Ride-leg indices (into `journey.legs`) of the feeder and the connection of the watched change; nil when the journey has
    /// no ride leg after the feeder.
    public static func legIndices(_ journey: Journey, feederRide: Int) -> (feeder: Int, connection: Int)? {
        let rides = journey.legs.indices.filter { journey.legs[$0].kind == .ride }
        guard feederRide >= 0, feederRide + 1 < rides.count else { return nil }
        return (rides[feederRide], rides[feederRide + 1])
    }

    /// The guard can watch this journey for this follow: a ride after the followed one, a Reconstruction handle, and the follow
    /// is ride `feederRide` (0: the first ride, as „Live verfolgen“ starts it; docs/CONNECTION_GUARD.md §2).
    public static func canWatch(_ journey: Journey, followTripID: String, feederRide: Int = 0) -> Bool {
        let rides = journey.rideLegs
        guard feederRide >= 0, rides.count >= feederRide + 2, let token = journey.refreshToken, !token.isEmpty else { return false }
        return rides[feederRide].tripID == followTripID
    }

    /// Walk between the two rides, as the connection detail counts it (`JourneyPresentation.walkMinutes` of every non-ride leg).
    public static func walk(_ journey: Journey, feeder a: Int, connection b: Int) -> (minutes: Int, known: Bool) {
        guard a + 1 <= b else { return (0, false) }
        let between = journey.legs[(a + 1)..<b].filter { $0.kind != .ride }
        return (between.reduce(0) { $0 + JourneyPresentation.walkMinutes($1) }, !between.isEmpty)
    }

    /// Assesses the change after ride `feederRide` (0 = the followed first ride).
    ///
    /// - `journey`/`journeyAt`: the connection and the time it was asked for (planner answer or Reconstruction).
    /// - `followSnapshot`/`followAt`: the follow's latest answer of the feeder; its arrival wins only when it is newer.
    /// - `connectionTrip`/`connectionTripAt`: JourneyDetails of the connecting trip (fallback); wins only when newer.
    /// Returns nil when the journey has no change after `feederRide`.
    public static func assess(journey: Journey, feederRide: Int = 0, followSnapshot: LiveFollowSnapshot?, followAt: Date?,
                              journeyAt: Date, connectionTrip: TripDetails? = nil, connectionTripAt: Date? = nil,
                              previous: GuardMemory, now: Date) -> (assessment: GuardAssessment, memory: GuardMemory)? {
        guard let (a, b) = legIndices(journey, feederRide: feederRide) else { return nil }
        let feederLeg = journey.legs[a], connectionLeg = journey.legs[b]

        // Feeder: the newer of the connection answer and the follow's JourneyDetails.
        var arrivalEvent = feederLeg.arrival
        var feederCancelled = feederLeg.isCancelled || feederLeg.arrival.isCancelled
        var dataAt = journeyAt
        if let snapshot = followSnapshot, let followAt, followAt > journeyAt {
            if let arrival = snapshot.alighting?.arrival {
                arrivalEvent = arrival
            }
            feederCancelled = snapshot.phase == .cancelled || (snapshot.alighting?.arrival?.isCancelled ?? false)
            dataAt = max(dataAt, followAt)
        }

        // Connection: the newer of the connection answer and its own JourneyDetails (fallback).
        var departureEvent = connectionLeg.departure
        var connectionCancelled = connectionLeg.isCancelled || connectionLeg.departure.isCancelled
        var connectionDataAt = journeyAt
        if let trip = connectionTrip, let tripAt = connectionTripAt, tripAt > journeyAt,
           let i = LiveFollow.index(of: connectionLeg.origin, in: trip.stopovers), let departure = trip.stopovers[i].departure {
            departureEvent = departure
            connectionCancelled = trip.isCancelled || departure.isCancelled
            connectionDataAt = tripAt
            dataAt = max(dataAt, tripAt)
        }

        let (walkMinutes, walkKnown) = walk(journey, feeder: a, connection: b)
        let feeder = GuardLegFigure.make(arrivalEvent, line: feederLeg.line, fallbackName: "Zug", mode: feederLeg.line?.mode)
        let connection = GuardLegFigure.make(departureEvent, line: connectionLeg.line, fallbackName: "Anschluss",
                                             mode: connectionLeg.line?.mode)
        let buffer: Int? = {
            guard let arrival = feeder.effective, let departure = connection.effective else { return nil }
            return TransferBuffer.minutes(arrival: arrival, departure: departure, walkMinutes: walkMinutes)
        }()

        // Samples and trend: one sample per new answer, ten minutes kept.
        var memory = previous
        let isNewAnswer = memory.lastAnswerAt.map { dataAt > $0 } ?? true
        if isNewAnswer {
            memory.lastAnswerAt = dataAt
            if let buffer { memory.samples.append(GuardSample(at: dataAt, minutes: buffer)) }
        }
        memory.samples = memory.samples.filter { now.timeIntervalSince($0.at) <= trendWindow }
        let (trend, reference) = trend(buffer: buffer, samples: memory.samples)

        let flaggedUnreachable = connectionLeg.isReachable == false
        let basedOnPlan = !feeder.hasRealtime && !connection.hasRealtime
        var cancelledLeg: GuardLegRole?
        if feederCancelled { cancelledLeg = .feeder } else if connectionCancelled { cancelledLeg = .connection }

        let raw = rawState(buffer: buffer, trend: trend, arrival: feeder.effective, departure: connection.effective,
                           cancelled: cancelledLeg != nil, unreachable: flaggedUnreachable, basedOnPlan: basedOnPlan, now: now)
        let shown = hysteresis(raw, memory: &memory, isNewAnswer: isNewAnswer)

        let assessment = GuardAssessment(
            state: shown, rawState: raw, bufferMinutes: buffer, walkMinutes: walkMinutes, walkKnown: walkKnown, trend: trend,
            trendReference: reference, hasTrendHistory: memory.samples.count >= 2, stationName: DisplayNames.name(feederLeg.destination.name), feeder: feeder,
            connection: connection, cancelledLeg: cancelledLeg, flaggedUnreachable: flaggedUnreachable, basedOnPlan: basedOnPlan,
            feederDeparture: feederLeg.departure.effective, dataAt: dataAt, connectionDataAt: connectionDataAt,
            laterTransfers: laterTransfers(journey, after: feederRide + 1))
        return (assessment, memory)
    }

    /// The state the data says on its own (before the hysteresis). Order: cancelled, missed (fact), over, no times, no
    /// realtime, then the spare minutes with the trend; `isRchbl` false caps a better state at „Wackelt“.
    static func rawState(buffer: Int?, trend: GuardTrend, arrival: Date?, departure: Date?, cancelled: Bool, unreachable: Bool,
                         basedOnPlan: Bool, now: Date) -> GuardState {
        if cancelled { return .cancelled }
        if let arrival, let departure, now >= departure, arrival > departure { return .missed }
        if let buffer, let departure, buffer >= 0, now >= departure.addingTimeInterval(overDelay) { return .over }
        var state: GuardState
        if let buffer, !basedOnPlan {
            switch buffer {
            case TransferBuffer.safeMinutes...:
                state = trend == .falling && buffer < calmMinutes ? .tighter : .safe
            case 2..<TransferBuffer.safeMinutes: state = .tighter
            case -1...1: state = .shaky
            default: state = .likelyMissed
            }
        } else {
            state = .scheduled
        }
        if unreachable, state == .safe || state == .tighter || state == .scheduled { state = .shaky }
        return state
    }

    /// Worse at once; better only after two new answers in a row say better (the more careful of the two is shown).
    /// The end („Umstieg vorbei“) shows at once. Without a new answer nothing turns better.
    static func hysteresis(_ raw: GuardState, memory: inout GuardMemory, isNewAnswer: Bool) -> GuardState {
        guard let shown = memory.shown, raw != .over else {
            memory.shown = raw
            memory.pendingBetter = nil
            return raw
        }
        if raw.rank >= shown.rank {
            memory.shown = raw
            memory.pendingBetter = nil
            return raw
        }
        guard isNewAnswer else { return shown }
        if let pending = memory.pendingBetter {
            let next = pending.rank >= raw.rank ? pending : raw
            memory.shown = next
            memory.pendingBetter = nil
            return next
        }
        memory.pendingBetter = raw
        return shown
    }

    /// Falling: now at least `trendStep` below the highest sample of the window; rising: at least `trendStep` above the lowest.
    static func trend(buffer: Int?, samples: [GuardSample]) -> (GuardTrend, GuardSample?) {
        guard let buffer, !samples.isEmpty else { return (.steady, nil) }
        // The most recent sample of the extreme value: „vor 4 Min waren es 9 Min“ names the closest moment.
        let highest = samples.max { $0.minutes < $1.minutes || ($0.minutes == $1.minutes && $0.at < $1.at) }
        let lowest = samples.min { $0.minutes < $1.minutes || ($0.minutes == $1.minutes && $0.at > $1.at) }
        if let highest, highest.minutes - buffer >= trendStep { return (.falling, highest) }
        if let lowest, buffer - lowest.minutes >= trendStep { return (.rising, lowest) }
        return (.steady, nil)
    }

    /// The changes after ride `index` (plain lines, planned times).
    static func laterTransfers(_ journey: Journey, after index: Int) -> [GuardLaterTransfer] {
        var out: [GuardLaterTransfer] = []
        var ride = index
        while let (a, b) = legIndices(journey, feederRide: ride) {
            let prev = journey.legs[a], next = journey.legs[b]
            let between = journey.legs[(a + 1)..<b].filter { $0.kind != .ride }
            let walk = between.reduce(0) { total, leg in
                if let s = leg.departure.planned, let e = leg.arrival.planned { return total + max(0, TransferBuffer.roundedMinutes(from: s, to: e)) }
                return total + JourneyPresentation.walkMinutes(leg)
            }
            var buffer: Int?
            if let arrival = prev.arrival.planned, let departure = next.departure.planned {
                buffer = TransferBuffer.minutes(arrival: arrival, departure: departure, walkMinutes: walk)
            }
            out.append(GuardLaterTransfer(stationName: DisplayNames.name(prev.destination.name), plannedBufferMinutes: buffer))
            ride += 1
        }
        return out
    }
}
