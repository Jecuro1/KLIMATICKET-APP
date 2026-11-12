import Foundation

// Aussteige-Wecker: the alarms of the app (docs/EXIT_ALARM.md §3). At most `capacity` are active at once, one per run and
// stop. A fix, a tick or a timetable change reaches all of them; an acknowledgement or a snooze reaches one. Alarms of
// different stops on the same run are independent: acknowledging one does not touch the other.

public struct ExitAlarmBook: Codable, Hashable, Sendable {
    public static let capacity = 3
    /// An ended alarm stays visible this long (the card says what happened), then it is dropped.
    public static let endedRetention: TimeInterval = 3600

    public private(set) var alarms: [ExitAlarmState] = []

    public init() {}

    public enum ArmResult: Equatable, Sendable {
        case armed(String)
        /// The same run and stop was armed before: its lead and times are replaced.
        case replaced(String)
        /// Three alarms are active already.
        case full
        /// The arrival is over (more than the expiry window ago).
        case arrivalOver
    }

    public var active: [ExitAlarmState] { alarms.filter(\.isActive) }
    public var ended: [ExitAlarmState] { alarms.filter { !$0.isActive } }

    public func state(id: String) -> ExitAlarmState? { alarms.first { $0.id == id } }

    /// An alarm that rings (or rang) and waits for the user: the full-screen moment shows it.
    public var needsAttention: ExitAlarmState? {
        active.filter { $0.phase == .fired }.min { ($0.firedAt ?? .distantFuture) < ($1.firedAt ?? .distantFuture) }
    }

    @discardableResult
    public mutating func arm(_ spec: ExitAlarmSpec, arrival: Date?, departure: Date? = nil, delaySeconds: Int? = nil, now: Date,
                             config: ExitAlarmConfig = .standard) -> (result: ArmResult, commands: [ExitAlarmCommand]) {
        if let arrival = arrival ?? spec.plannedArrival, now >= arrival.addingTimeInterval(config.expiryAfterArrival) {
            return (.arrivalOver, [])
        }
        var commands: [ExitAlarmCommand] = []
        var replaced = false
        if let index = alarms.firstIndex(where: { $0.id == spec.id }) {
            if alarms[index].isActive {
                commands += ExitAlarmBook.tag(ExitAlarmPlanner.apply(.end(.cancelledByUser), to: &alarms[index], now: now, config: config), spec.id)
                replaced = true
            }
            alarms.remove(at: index)
        }
        if !replaced, active.count >= Self.capacity { return (.full, []) }
        let armed = ExitAlarmPlanner.arm(spec, arrival: arrival, departure: departure, delaySeconds: delaySeconds, now: now, config: config)
        alarms.append(armed.state)
        commands += ExitAlarmBook.tag(armed.effects, spec.id)
        return (replaced ? .replaced(spec.id) : .armed(spec.id), commands)
    }

    /// One event for every active alarm.
    public mutating func apply(_ event: ExitAlarmEvent, now: Date, config: ExitAlarmConfig = .standard) -> [ExitAlarmCommand] {
        var commands: [ExitAlarmCommand] = []
        for index in alarms.indices where alarms[index].isActive {
            commands += ExitAlarmBook.tag(ExitAlarmPlanner.apply(event, to: &alarms[index], now: now, config: config), alarms[index].id)
        }
        return commands
    }

    /// One event for the alarm with this id.
    public mutating func apply(_ event: ExitAlarmEvent, to id: String, now: Date, config: ExitAlarmConfig = .standard) -> [ExitAlarmCommand] {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return [] }
        return ExitAlarmBook.tag(ExitAlarmPlanner.apply(event, to: &alarms[index], now: now, config: config), id)
    }

    /// One event for every active alarm of a run (the timetable of that run, the end of its follow).
    public mutating func apply(_ event: ExitAlarmEvent, tripID: String, now: Date, config: ExitAlarmConfig = .standard) -> [ExitAlarmCommand] {
        var commands: [ExitAlarmCommand] = []
        for index in alarms.indices where alarms[index].isActive && alarms[index].spec.tripID == tripID {
            commands += ExitAlarmBook.tag(ExitAlarmPlanner.apply(event, to: &alarms[index], now: now, config: config), alarms[index].id)
        }
        return commands
    }

    /// Drops ended alarms older than `endedRetention`.
    public mutating func prune(now: Date) {
        alarms.removeAll { state in
            guard !state.isActive, let endedAt = state.endedAt else { return false }
            return now.timeIntervalSince(endedAt) > Self.endedRetention
        }
    }

    public mutating func remove(id: String) {
        alarms.removeAll { $0.id == id }
    }

    /// The alarm the Live Activity shows: the armed one whose moment comes first.
    public func activityInfo(now: Date, config: ExitAlarmConfig = .standard) -> FollowExitAlarmInfo? {
        active.filter { $0.phase == .armed || $0.phase == .approaching }
            .compactMap { state -> (ExitAlarmState, Date)? in
                guard let arrival = ExitAlarmPresentation.estimate(state, now: now, config: config).remainingSeconds else { return nil }
                return (state, now.addingTimeInterval(arrival))
            }
            .min { $0.1 < $1.1 }
            .map { state, arrival in
                FollowExitAlarmInfo(stopName: state.spec.stopName, arrival: arrival, isTransfer: state.spec.isTransfer,
                                    isApproaching: state.phase == .approaching)
            }
    }

    /// The most location any active alarm needs.
    public func locationNeed(now: Date, config: ExitAlarmConfig = .standard) -> ExitAlarmLocationNeed {
        active.map { ExitAlarmPlanner.locationNeed($0, now: now, config: config) }.max() ?? .none
    }

    private static func tag(_ effects: [ExitAlarmEffect], _ id: String) -> [ExitAlarmCommand] {
        effects.map { ExitAlarmCommand(alarmID: id, effect: $0) }
    }
}
