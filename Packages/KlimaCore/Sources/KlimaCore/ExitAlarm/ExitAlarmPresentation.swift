import Foundation

// Aussteige-Wecker: what the card, the full-screen moment, the Live Activity and the notifications say (docs/EXIT_ALARM.md §4).
// German, Du-Form. Pure functions of the state and "now", so the words are tested and the numbers cannot drift from the planner.

public struct ExitAlarmEstimate: Hashable, Sendable {
    public enum Source: String, Sendable, Hashable {
        /// From the timetable and the reported delay.
        case timetable
        /// From the remaining distance and the smoothed speed.
        case gps
    }

    /// Seconds to the arrival at the stop; nil when nothing is known.
    public var remainingSeconds: TimeInterval?
    /// Metres along the stops; nil without a fresh fix on the run. Never invented.
    public var remainingMeters: Double?
    /// Seconds until the alarm rings; nil when no moment is known.
    public var secondsUntilAlarm: TimeInterval?
    /// 0 to 1: how far the ride to the stop has come.
    public var progress: Double
    public var source: Source
    /// The number is an estimate (GPS or a prognosed arrival), not a planned time. The card says "geschätzt".
    public var isEstimate: Bool
}

public enum ExitAlarmPresentation {
    // MARK: Numbers

    /// The arrival the card shows: the earlier of the timetable and a fresh GPS estimate (the alarm rings on the earlier one).
    public static func estimate(_ state: ExitAlarmState, now: Date, config: ExitAlarmConfig = .standard) -> ExitAlarmEstimate {
        let fresh = state.motion.isFresh(at: now, config: config)
        let gps = fresh ? state.gpsArrival : nil
        let timetable = state.timetableArrival
        var arrival: Date?
        var source = ExitAlarmEstimate.Source.timetable
        switch (timetable, gps) {
        case let (t?, g?):
            // The GPS wins only when it is clearly earlier: a few seconds of difference are not a second opinion.
            if g < t.addingTimeInterval(-30) { arrival = g; source = .gps } else { arrival = t }
        case let (t?, nil): arrival = t
        case let (nil, g?): arrival = g; source = .gps
        case (nil, nil): arrival = nil
        }
        let remaining = arrival.map { max($0.timeIntervalSince(now), 0) }
        let meters = fresh ? state.remainingMeters : nil
        let moment = ExitAlarmPlanner.triggerMoment(state, now: now, config: config)
        let isEstimate = source == .gps || (state.delaySeconds ?? 0) != 0 || arrival == nil
        return ExitAlarmEstimate(remainingSeconds: remaining, remainingMeters: meters,
                                 secondsUntilAlarm: moment.map { max($0.timeIntervalSince(now), 0) },
                                 progress: progress(state, now: now, remainingMeters: meters, arrival: arrival),
                                 source: source, isEstimate: isEstimate)
    }

    /// Ring progress. By distance when a fix is on the run, else by time between the boarding departure and the arrival.
    static func progress(_ state: ExitAlarmState, now: Date, remainingMeters: Double?, arrival: Date?) -> Double {
        switch state.phase {
        case .fired, .acknowledged, .ended: return 1
        default: break
        }
        let length = GeoPath(state.spec.path).length
        if let remainingMeters, length > 0 {
            return min(max(1 - remainingMeters / length, 0), 1)
        }
        guard let start = state.spec.boardingDeparture, let arrival, arrival > start else { return 0 }
        return min(max(now.timeIntervalSince(start) / arrival.timeIntervalSince(start), 0), 1)
    }

    // MARK: Words

    /// "4 Min", "1 Std 5 Min", "unter 1 Min". Rounds up: "noch 4 Min" never claims more time than there is.
    public static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "unter 1 Min" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) Min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) Std" : "\(hours) Std \(rest) Min"
    }

    /// "850 m", "4,2 km", "18 km" (German decimal comma).
    public static func distanceText(_ meters: Double) -> String {
        if meters < 995 { return "\(Int((meters / 10).rounded()) * 10) m" }
        let km = meters / 1000
        if km < 10 { return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(km.rounded())) km"
    }

    /// "17:42" in Vienna time.
    public static func timeText(_ date: Date) -> String {
        timeFormatterLock.lock()
        defer { timeFormatterLock.unlock() }
        return timeFormatter.string(from: date)
    }

    // One formatter for the whole app: the card asks on every redraw. DateFormatter is thread-safe for reading since iOS 7, the
    // lock only keeps the strict-concurrency checker and Linux's Foundation calm.
    private static let timeFormatterLock = NSLock()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// The card's title.
    public static func title(_ state: ExitAlarmState) -> String {
        state.spec.isTransfer ? "Umsteigen in \(state.spec.stopName)" : "Aussteigen in \(state.spec.stopName)"
    }

    /// The state in one line under the title.
    public static func statusLine(_ state: ExitAlarmState, now: Date, config: ExitAlarmConfig = .standard) -> String {
        switch state.phase {
        case .armed, .approaching:
            if let moment = ExitAlarmPlanner.triggerMoment(state, now: now, config: config) {
                let lead = state.spec.lead.minutes == 0 ? "bei der Ankunft" : "\(state.spec.lead.minutes) Min vor der Ankunft"
                return moment.timeIntervalSince(now) < 60
                    ? "Weckt dich jetzt, \(lead)"
                    : "Weckt dich um \(timeText(moment)), \(lead)"
            }
            return "Weckt dich \(state.spec.lead.phrase), sobald die Ankunft bekannt ist"
        case .fired:
            return state.passedAt == nil ? "Aussteigen!" : "Vorbeigefahren"
        case .snoozed:
            return state.snoozedUntil.map { "Schlummert bis \(timeText($0))" } ?? "Schlummert"
        case .acknowledged:
            return "Quittiert"
        case .ended:
            return state.endReason?.title ?? "Beendet"
        }
    }

    /// Remaining time and distance for the card: "noch 12 Min · ca. 18 km". The distance only appears with a fix on the run.
    public static func remainingLine(_ estimate: ExitAlarmEstimate) -> String? {
        guard let seconds = estimate.remainingSeconds else { return nil }
        var text = "noch \(durationText(seconds))"
        if let meters = estimate.remainingMeters { text += " · ca. \(distanceText(meters))" }
        return text
    }

    /// The tag next to the numbers.
    public static func estimateTag(_ estimate: ExitAlarmEstimate) -> String {
        if estimate.source == .gps { return "geschätzt · Standort" }
        return estimate.isEstimate ? "geschätzt" : "laut Fahrplan"
    }

    /// The Live Activity line while the alarm is armed: "Aussteigen in 4 Min".
    public static func activityLine(_ state: ExitAlarmState, now: Date, config: ExitAlarmConfig = .standard) -> String? {
        guard state.phase == .armed || state.phase == .approaching || state.phase == .snoozed else { return nil }
        guard let seconds = estimate(state, now: now, config: config).remainingSeconds else { return nil }
        return "\(state.spec.isTransfer ? "Umsteigen" : "Aussteigen") in \(durationText(seconds))"
    }

    /// The one sentence that says what the alarm does, by the kind of alarm this iPhone uses. "Auch im Schlaf" stands only where it is
    /// true: the system alarm rings through the silent switch and Focus, a notification does not, and without a permission the alarm
    /// waits for one.
    public static func promise(kind: ExitAlarmKind) -> String {
        switch kind {
        case .alarmKit:
            "Weckt dich kurz vor deiner Haltestelle, auch im Schlaf und bei lautlosem iPhone."
        case .notifications:
            "Meldet sich kurz vor deiner Haltestelle. Der Lautlos-Schalter und der Fokus können die Mitteilung stumm schalten."
        case .none:
            "Weckt dich kurz vor deiner Haltestelle. Beim Stellen fragt iOS nach der Erlaubnis für den Wecker."
        }
    }

    // MARK: Full-screen moment and notification

    public static func firedTitle(_ state: ExitAlarmState) -> String {
        if state.passedAt != nil { return "Vorbeigefahren" }
        return state.spec.isTransfer ? "Umsteigen!" : "Aussteigen!"
    }

    public static func firedSubtitle(_ state: ExitAlarmState) -> String {
        if state.passedAt != nil { return "Du bist an \(state.spec.stopName) vorbeigefahren." }
        var text = state.spec.stopName
        if let platform = state.spec.platform, !platform.isEmpty { text += " · Gleis \(platform)" }
        return text
    }

    /// What the system alarm and the notifications say.
    public static func ringContent(_ spec: ExitAlarmSpec, kind: ExitAlarmRingContent.Kind, now: Date = Date()) -> ExitAlarmRingContent {
        let platform = spec.platform.flatMap { $0.isEmpty ? nil : " · Gleis \($0)" } ?? ""
        switch kind {
        case .arrival:
            let verb = spec.isTransfer ? "Umsteigen" : "Aussteigen"
            let when = spec.lead.minutes == 0 ? "gleich" : "in etwa \(spec.lead.minutes) Min"
            return ExitAlarmRingContent(id: spec.id, kind: kind, title: "\(verb)!",
                                        body: "\(spec.stopName) \(when)\(platform)", stopName: spec.stopName,
                                        lineName: spec.lineName, soundKey: spec.soundKey)
        case .snoozed:
            // After "5 Min später" the lead is used up: the text must not promise "in etwa 5 Min" any more.
            let verb = spec.isTransfer ? "Umsteigen" : "Aussteigen"
            return ExitAlarmRingContent(id: spec.id, kind: kind, title: "\(verb)!",
                                        body: "Deine Erinnerung für \(spec.stopName)\(platform)", stopName: spec.stopName,
                                        lineName: spec.lineName, soundKey: spec.soundKey)
        case .passed:
            return ExitAlarmRingContent(id: spec.id, kind: kind, title: "Vorbeigefahren",
                                        body: "Du bist an \(spec.stopName) vorbeigefahren.", stopName: spec.stopName,
                                        lineName: spec.lineName, soundKey: spec.soundKey)
        case .test:
            return ExitAlarmRingContent(id: spec.id, kind: kind, title: "Test: Aussteigen!",
                                        body: "So klingt dein Aussteige-Wecker.", stopName: spec.stopName,
                                        lineName: spec.lineName, soundKey: spec.soundKey)
        }
    }
}

/// What a scheduler needs to ring: title, body and the sound.
public struct ExitAlarmRingContent: Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable { case arrival, snoozed, passed, test }
    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var stopName: String
    public var lineName: String
    public var soundKey: String

    public init(id: String, kind: Kind, title: String, body: String, stopName: String, lineName: String, soundKey: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.stopName = stopName
        self.lineName = lineName
        self.soundKey = soundKey
    }
}

/// A stable UUID from a string (AlarmKit needs UUIDs, the engine uses readable ids): two FNV-1a passes with different
/// seeds fill the 16 bytes. The same string gives the same UUID on every launch.
public enum ExitAlarmUUID {
    public static func make(from string: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> UInt64(8 * i)) & 0xff)
            bytes[8 + i] = UInt8((b >> UInt64(8 * i)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50   // version 5 layout
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
