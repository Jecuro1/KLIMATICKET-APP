import Foundation

// Aussteige-Wecker: the fusion and the state machine of one alarm (docs/EXIT_ALARM.md §3). Pure: events and "now" come in,
// the new state and a list of effects go out. Nothing here reads a clock, a location manager or a scheduler.
//
// Two ways to ring, the earlier one wins, never twice:
//   - the time-based alarm: the predicted arrival (timetable plus the reported delay) minus the lead, scheduled with the
//     system, so it rings with the app closed and the phone locked;
//   - the location-based alarm: the geofence around the stop and the GPS estimate (remaining distance over the smoothed
//     speed, minus the lead), checked while the app is awake.
// Whoever rings first sets the state to `fired`; after that nothing rings again except "vorbeigefahren" and a snooze that
// the user asked for.

public enum ExitAlarmEvent: Sendable {
    /// A clock tick: nothing new, check the moment.
    case tick
    /// New timetable data of the target stop: the effective arrival (realtime when known) and its delay.
    case timetable(arrival: Date?, departure: Date?, delaySeconds: Int?)
    case fix(LocationFix)
    /// The system reports that the circle around the stop was entered.
    case regionEntered
    /// The system reports that the scheduled time-based alarm went off (or is ringing now).
    case timeAlarmRang
    /// The scheduler could not take the time-based alarm: the planner stops counting on it.
    case timeAlarmUnavailable
    case acknowledge
    case snooze(minutes: Int)
    /// The follow ended, the user cancelled or Live-Daten went off.
    case end(ExitAlarmEndReason)
}

/// The state of one alarm. Everything the position tells (fix, speed, distances) lives in memory only: the `CodingKeys`
/// leave it out, so a saved alarm holds the stop and the schedule, never where the user was.
public struct ExitAlarmState: Codable, Hashable, Sendable, Identifiable {
    public var spec: ExitAlarmSpec
    public var phase: ExitAlarmPhase
    public var endReason: ExitAlarmEndReason?
    /// Effective arrival at the stop (realtime when the timetable reports it).
    public var timetableArrival: Date?
    /// Departure at the stop, nil at the end of the run. "Vorbeigefahren" by the timetable uses it.
    public var timetableDeparture: Date?
    public var delaySeconds: Int?
    /// The moment the time-based alarm is scheduled for, nil when none is.
    public var scheduledTimeAlarm: Date?
    public var geofenceRadius: Double?
    public var firedAt: Date?
    public var firedBy: ExitAlarmSource?
    public var passedAt: Date?
    public var snoozedUntil: Date?
    public var snoozeCount = 0
    public var acknowledgedAt: Date?
    public var endedAt: Date?

    // In memory only (see the type's comment).
    public var motion = ExitAlarmMotion()
    public var remainingMeters: Double?
    public var gpsArrival: Date?
    public var closestMeters: Double?
    public var lastDistance: Double?
    public var growingFixes = 0
    public var gpsHits = 0

    public var id: String { spec.id }
    public var isActive: Bool { phase != .ended }

    private enum CodingKeys: String, CodingKey {
        case spec, phase, endReason, timetableArrival, timetableDeparture, delaySeconds, scheduledTimeAlarm, geofenceRadius
        case firedAt, firedBy, passedAt, snoozedUntil, snoozeCount, acknowledgedAt, endedAt
    }

    public init(spec: ExitAlarmSpec, phase: ExitAlarmPhase = .armed) {
        self.spec = spec
        self.phase = phase
    }

    /// The newest fix, if any (memory only).
    public var lastFix: LocationFix? { motion.lastFix }
}

public enum ExitAlarmPlanner {
    // MARK: Arming

    /// A new alarm. The effects schedule the time-based alarm and set the geofence. When the moment has already passed
    /// (the lead is longer than the time left) the alarm rings at once.
    public static func arm(_ spec: ExitAlarmSpec, arrival: Date?, departure: Date? = nil, delaySeconds: Int? = nil, now: Date,
                           config: ExitAlarmConfig = .standard) -> (state: ExitAlarmState, effects: [ExitAlarmEffect]) {
        var state = ExitAlarmState(spec: spec)
        state.timetableArrival = arrival ?? spec.plannedArrival
        state.timetableDeparture = departure
        state.delaySeconds = delaySeconds
        var effects: [ExitAlarmEffect] = []
        if let center = geofenceCenter(spec) {
            let radius = ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: nil, config: config)
            state.geofenceRadius = radius
            effects.append(.setGeofence(center: center, radius: radius))
        }
        effects += reschedule(&state, now: now, config: config)
        effects += evaluate(&state, now: now, config: config, fixArrived: false)
        return (state, effects)
    }

    // MARK: Events

    @discardableResult
    public static func apply(_ event: ExitAlarmEvent, to state: inout ExitAlarmState, now: Date,
                             config: ExitAlarmConfig = .standard) -> [ExitAlarmEffect] {
        guard state.phase != .ended else { return [] }
        var effects: [ExitAlarmEffect] = []
        var fixArrived = false

        switch event {
        case .tick:
            break

        case .timetable(let arrival, let departure, let delay):
            if let arrival { state.timetableArrival = arrival }
            state.timetableDeparture = departure
            state.delaySeconds = delay
            if state.phase == .armed || state.phase == .approaching {
                effects += reschedule(&state, now: now, config: config)
            }

        case .fix(let fix):
            fixArrived = ingest(fix, into: &state, now: now, config: config)
            if fixArrived, state.phase == .armed || state.phase == .approaching {
                effects += adjustGeofence(&state, config: config)
            }

        case .regionEntered:
            guard state.phase == .armed || state.phase == .approaching else { break }
            // A circle that is entered while the timetable still says "long to go" is not believed.
            if let trigger = timetableTrigger(state), trigger.timeIntervalSince(now) > config.geofenceSanityWindow { break }
            return fire(&state, source: .geofence, now: now, ring: true)

        case .timeAlarmRang:
            guard state.phase == .armed || state.phase == .approaching || state.phase == .snoozed else { break }
            // A late report of the alarm that rang before the snooze is not the snooze alarm: that one rings at `snoozedUntil`.
            if state.phase == .snoozed, let until = state.snoozedUntil, now < until.addingTimeInterval(-5) { break }
            return fire(&state, source: state.phase == .snoozed ? .snooze : .timetable, now: now, ring: false)

        case .timeAlarmUnavailable:
            state.scheduledTimeAlarm = nil

        case .acknowledge:
            return acknowledge(&state, now: now)

        case .snooze(let minutes):
            guard state.passedAt == nil, state.phase != .acknowledged else { break }
            let seconds = min(max(TimeInterval(minutes) * 60, 60), config.maxSnooze)
            let until = now.addingTimeInterval(seconds)
            var out: [ExitAlarmEffect] = []
            if state.phase == .fired { out.append(.stopRinging) }
            if state.scheduledTimeAlarm != nil { out.append(.cancelTimeAlarm) }
            state.phase = .snoozed
            state.snoozedUntil = until
            state.snoozeCount += 1
            state.scheduledTimeAlarm = until
            out.append(.scheduleTimeAlarm(at: until))
            return out

        case .end(let reason):
            return end(&state, reason: reason == .followEnded && state.phase == .acknowledged ? .completed : reason, now: now)
        }

        effects += evaluate(&state, now: now, config: config, fixArrived: fixArrived)
        return effects
    }

    // MARK: Trigger moment

    /// The timetable moment: predicted arrival minus the lead.
    public static func timetableTrigger(_ state: ExitAlarmState) -> Date? {
        state.timetableArrival.map { $0.addingTimeInterval(-state.spec.lead.seconds) }
    }

    /// The GPS moment: estimated arrival minus the lead. Nil without a fresh fix and a travelling speed.
    public static func gpsTrigger(_ state: ExitAlarmState) -> Date? {
        state.gpsArrival.map { $0.addingTimeInterval(-state.spec.lead.seconds) }
    }

    /// The moment the alarm rings: the earlier of the timetable and the GPS moment. The GPS moment only counts while the
    /// last fix is fresh (a tunnel gives it up and the timetable carries on).
    public static func triggerMoment(_ state: ExitAlarmState, now: Date, config: ExitAlarmConfig = .standard) -> Date? {
        let gps = state.motion.isFresh(at: now, config: config) ? gpsTrigger(state) : nil
        switch (timetableTrigger(state), gps) {
        case let (t?, g?): return min(t, g)
        case let (t?, nil): return t
        case let (nil, g?): return g
        case (nil, nil): return nil
        }
    }

    /// How much location the alarm needs now: nothing, the geofence, or low-power updates while the trip runs.
    public static func locationNeed(_ state: ExitAlarmState, now: Date, config: ExitAlarmConfig = .standard) -> ExitAlarmLocationNeed {
        switch state.phase {
        case .ended, .acknowledged:
            return .none
        case .fired:
            return state.passedAt == nil ? .continuous : .none
        case .armed, .approaching, .snoozed:
            let start = (state.spec.boardingDeparture ?? state.spec.createdAt).addingTimeInterval(-config.locationWindowLead)
            return now >= start ? .continuous : .geofenceOnly
        }
    }

    // MARK: Evaluation

    private static func evaluate(_ state: inout ExitAlarmState, now: Date, config: ExitAlarmConfig, fixArrived: Bool) -> [ExitAlarmEffect] {
        if let arrival = state.timetableArrival ?? state.spec.plannedArrival,
           now >= arrival.addingTimeInterval(config.expiryAfterArrival) {
            return end(&state, reason: state.phase == .acknowledged ? .completed : .expired, now: now)
        }
        var effects: [ExitAlarmEffect] = []

        switch state.phase {
        case .ended, .acknowledged:
            return []

        case .snoozed:
            let due = state.scheduledTimeAlarm ?? state.snoozedUntil
            if let due, now >= due {
                return fire(&state, source: .snooze, now: now, ring: state.scheduledTimeAlarm == nil)
            }

        case .armed, .approaching:
            let timetable = timetableTrigger(state)
            let gps = state.motion.isFresh(at: now, config: config) ? gpsTrigger(state) : nil

            // The GPS has to say "now" on several fixes in a row: one wild fix rings nothing.
            if fixArrived {
                if let gps, now >= gps { state.gpsHits += 1 } else { state.gpsHits = 0 }
            }
            if state.gpsHits >= config.gpsConfirmations {
                return fire(&state, source: .gps, now: now, ring: true)
            }

            if let timetable, now >= timetable {
                if let scheduled = state.scheduledTimeAlarm {
                    if scheduled <= timetable.addingTimeInterval(config.rescheduleTolerance) {
                        // The system rings at `scheduled`; the app only records it.
                        if now >= scheduled { return fire(&state, source: .timetable, now: now, ring: false) }
                    } else {
                        // The timetable moved earlier than the scheduled alarm: ring now and drop the late one.
                        return fire(&state, source: .timetable, now: now, ring: true)
                    }
                } else {
                    return fire(&state, source: .timetable, now: now, ring: true)
                }
            } else if let scheduled = state.scheduledTimeAlarm, now >= scheduled.addingTimeInterval(3) {
                // The scheduled alarm went off while the prediction moved later: it has rung, it is not rung twice.
                return fire(&state, source: .timetable, now: now, ring: false)
            }

            let moment = [timetable, gps].compactMap { $0 }.min()
            if let moment {
                let remaining = moment.timeIntervalSince(now)
                if remaining <= config.approachWindow {
                    state.phase = .approaching
                } else if state.phase == .approaching, remaining > config.approachWindow + config.hysteresis {
                    state.phase = .armed
                }
            }

        case .fired:
            break
        }

        effects += passedCheck(&state, now: now, config: config)
        return effects
    }

    /// "Du bist an X vorbeigefahren": the target stop was passed and the user did not acknowledge.
    private static func passedCheck(_ state: inout ExitAlarmState, now: Date, config: ExitAlarmConfig) -> [ExitAlarmEffect] {
        guard state.passedAt == nil, state.phase != .acknowledged, state.phase != .ended else { return [] }
        var passed = false
        // A stop cannot be passed before the alarm's moment: while the alarm still waits and the timetable knows the arrival, the
        // distance that grows is a curve at the start of a short ride, not an overshoot.
        let stillWaiting = (state.phase == .armed || state.phase == .approaching) && state.timetableArrival != nil
        if state.motion.isFresh(at: now, config: config) {
            // GPS: the closest approach was near, the distance has grown since, over several fixes, at travelling speed.
            if !stillWaiting, let closest = state.closestMeters, let last = state.lastDistance, closest <= config.passedNearDistance,
               last >= closest + config.passedGrowth, state.growingFixes >= config.passedGrowingFixes,
               let speed = state.motion.smoothedSpeed, speed >= config.minTravelSpeed {
                passed = true
            }
        } else if let departure = state.timetableDeparture, now >= departure.addingTimeInterval(config.passedAfterDeparture) {
            // No GPS: the train has left the stop by the timetable (an intermediate stop; the last stop cannot be passed).
            passed = true
        }
        guard passed else { return [] }
        state.passedAt = now
        var effects: [ExitAlarmEffect] = []
        if state.scheduledTimeAlarm != nil {
            effects.append(.cancelTimeAlarm)
            state.scheduledTimeAlarm = nil
        }
        if state.geofenceRadius != nil {
            effects.append(.removeGeofence)
            state.geofenceRadius = nil
        }
        if state.phase != .fired {
            state.phase = .fired
            state.firedAt = now
            state.firedBy = .gps
        }
        effects.append(.ringPassed)
        return effects
    }

    // MARK: Transitions

    private static func fire(_ state: inout ExitAlarmState, source: ExitAlarmSource, now: Date, ring: Bool) -> [ExitAlarmEffect] {
        var effects: [ExitAlarmEffect] = []
        if ring, state.scheduledTimeAlarm != nil { effects.append(.cancelTimeAlarm) }
        state.scheduledTimeAlarm = nil
        state.phase = .fired
        state.firedAt = now
        state.firedBy = source
        state.snoozedUntil = nil
        state.gpsHits = 0
        if ring { effects.append(.ring(source)) }
        if state.geofenceRadius != nil {
            effects.append(.removeGeofence)
            state.geofenceRadius = nil
        }
        return effects
    }

    private static func acknowledge(_ state: inout ExitAlarmState, now: Date) -> [ExitAlarmEffect] {
        var effects: [ExitAlarmEffect] = []
        if state.phase == .fired { effects.append(.stopRinging) }
        if state.scheduledTimeAlarm != nil {
            effects.append(.cancelTimeAlarm)
            state.scheduledTimeAlarm = nil
        }
        if state.geofenceRadius != nil {
            effects.append(.removeGeofence)
            state.geofenceRadius = nil
        }
        state.phase = .acknowledged
        state.acknowledgedAt = now
        state.snoozedUntil = nil
        return effects
    }

    private static func end(_ state: inout ExitAlarmState, reason: ExitAlarmEndReason, now: Date) -> [ExitAlarmEffect] {
        var effects: [ExitAlarmEffect] = []
        if state.phase == .fired { effects.append(.stopRinging) }
        if state.scheduledTimeAlarm != nil {
            effects.append(.cancelTimeAlarm)
            state.scheduledTimeAlarm = nil
        }
        if state.geofenceRadius != nil {
            effects.append(.removeGeofence)
            state.geofenceRadius = nil
        }
        state.phase = .ended
        state.endReason = reason
        state.endedAt = now
        state.snoozedUntil = nil
        return effects
    }

    // MARK: Scheduling and geofence

    /// Moves the time-based alarm to the timetable moment when it differs by more than the tolerance.
    private static func reschedule(_ state: inout ExitAlarmState, now: Date, config: ExitAlarmConfig) -> [ExitAlarmEffect] {
        guard let trigger = timetableTrigger(state), trigger > now.addingTimeInterval(5) else { return [] }
        if let scheduled = state.scheduledTimeAlarm {
            // An alarm that is already due is not moved: it rings, or has rung.
            guard scheduled > now.addingTimeInterval(5) else { return [] }
            guard abs(scheduled.timeIntervalSince(trigger)) >= config.rescheduleTolerance else { return [] }
        }
        state.scheduledTimeAlarm = trigger
        return [.scheduleTimeAlarm(at: trigger)]
    }

    private static func geofenceCenter(_ spec: ExitAlarmSpec) -> GeoPoint? { spec.stopCoordinate ?? spec.path.last }

    /// A new radius when the smoothed speed changed it by a quarter or more.
    private static func adjustGeofence(_ state: inout ExitAlarmState, config: ExitAlarmConfig) -> [ExitAlarmEffect] {
        guard let current = state.geofenceRadius, let center = geofenceCenter(state.spec) else { return [] }
        let radius = ExitAlarmGeometry.geofenceRadius(spec: state.spec, smoothedSpeed: state.motion.smoothedSpeed, config: config)
        guard abs(radius - current) / current >= 0.25 else { return [] }
        state.geofenceRadius = radius
        return [.setGeofence(center: center, radius: radius)]
    }

    /// Feeds one fix in. False when it is dropped (stale on arrival, invalid, out of order).
    private static func ingest(_ fix: LocationFix, into state: inout ExitAlarmState, now: Date, config: ExitAlarmConfig) -> Bool {
        guard now.timeIntervalSince(fix.time) <= config.maxFixLag, fix.time.timeIntervalSince(now) <= 5 else { return false }
        guard state.motion.ingest(fix, config: config) else { return false }

        if let distance = ExitAlarmGeometry.distance(of: fix, spec: state.spec) {
            state.remainingMeters = distance.remaining
            state.gpsArrival = state.motion.arrival(remaining: distance.remaining, at: now, config: config)
        } else {
            state.remainingMeters = nil
            state.gpsArrival = nil
        }

        if let straight = ExitAlarmGeometry.straightDistance(of: fix, spec: state.spec) {
            if let closest = state.closestMeters, straight >= closest {
                if let last = state.lastDistance {
                    if straight > last + 20 { state.growingFixes += 1 } else if straight < last - 20 { state.growingFixes = 0 }
                }
            } else {
                state.closestMeters = straight
                state.growingFixes = 0
            }
            state.lastDistance = straight
        }
        return true
    }
}
