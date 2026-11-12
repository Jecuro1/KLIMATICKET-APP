import Foundation

// Aussteige-Wecker (docs/EXIT_ALARM.md): the values. Pure and Codable, no I/O, no Apple framework: the planner, the book of
// alarms and the engine in this folder run and are tested on Linux. "Now" is always a parameter.

/// How long before the arrival the alarm goes off.
public enum ExitAlarmLead: Int, Codable, CaseIterable, Sendable, Hashable {
    case atArrival = 0
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10

    public static let standard: ExitAlarmLead = .fiveMinutes

    public var minutes: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) * 60 }

    /// The closest choice for a stored number of minutes; the standard for anything unknown.
    public init(minutes: Int) {
        self = ExitAlarmLead(rawValue: minutes) ?? .standard
    }

    /// "Bei Ankunft", "2 Min vorher" (Settings picker, sheet).
    public var title: String {
        self == .atArrival ? "Bei Ankunft" : "\(rawValue) Min vorher"
    }

    /// "bei der Ankunft", "2 Min vor der Ankunft" (sentences).
    public var phrase: String {
        self == .atArrival ? "bei der Ankunft" : "\(rawValue) Min vor der Ankunft"
    }
}

/// One position fix. Only the newest one is kept, and only in memory (docs/EXIT_ALARM.md §6).
public struct LocationFix: Hashable, Sendable {
    public var time: Date
    public var coordinate: GeoPoint
    /// Metres per second; nil when the system reports no valid speed.
    public var speed: Double?
    /// Metres; a negative value means the fix is invalid.
    public var horizontalAccuracy: Double

    public init(time: Date, coordinate: GeoPoint, speed: Double? = nil, horizontalAccuracy: Double = 20) {
        self.time = time
        self.coordinate = coordinate
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }
}

/// The alarm the user asked for: one stop of one followed run.
public struct ExitAlarmSpec: Codable, Hashable, Sendable, Identifiable {
    /// "<trip id>|<stop id>": one alarm per run and stop.
    public var id: String
    public var tripID: String
    /// "RJX 66"
    public var lineName: String
    public var stopID: String
    public var stopName: String
    public var stopCoordinate: GeoPoint?
    public var platform: String?
    /// Coordinates of the run's stops from the boarding stop up to this one, in running order (public timetable data, no
    /// position of the user). The remaining distance is measured along it.
    public var path: [GeoPoint]
    public var plannedArrival: Date?
    /// Planned departure at the boarding stop: the ring and the start of the location window use it.
    public var boardingDeparture: Date?
    public var lead: ExitAlarmLead
    /// The user changes trains here (not the end of the journey).
    public var isTransfer: Bool
    public var createdAt: Date
    /// `ExitAlarmSound.rawValue` of the app; the engine does not interpret it.
    public var soundKey: String

    public init(tripID: String, lineName: String, stopID: String, stopName: String, stopCoordinate: GeoPoint? = nil,
                platform: String? = nil, path: [GeoPoint] = [], plannedArrival: Date? = nil, boardingDeparture: Date? = nil,
                lead: ExitAlarmLead = .standard, isTransfer: Bool = false, createdAt: Date = Date(), soundKey: String = "standard") {
        self.id = ExitAlarmSpec.makeID(tripID: tripID, stopID: stopID)
        self.tripID = tripID
        self.lineName = lineName
        self.stopID = stopID
        self.stopName = stopName
        self.stopCoordinate = stopCoordinate
        self.platform = platform
        self.path = path
        self.plannedArrival = plannedArrival
        self.boardingDeparture = boardingDeparture
        self.lead = lead
        self.isTransfer = isTransfer
        self.createdAt = createdAt
        self.soundKey = soundKey
    }

    public static func makeID(tripID: String, stopID: String) -> String { "\(tripID)|\(stopID)" }

    /// Stable, notification-safe key: letters and digits only (AlarmKit and notification identifiers).
    public var safeKey: String {
        String(id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" })
    }
}

/// Where a ring came from.
public enum ExitAlarmSource: String, Codable, Sendable, Hashable {
    /// The predicted arrival from the timetable and the reported delay.
    case timetable
    /// The GPS estimate, from the remaining distance and the smoothed speed.
    case gps
    /// The geofence around the stop was entered.
    case geofence
    /// The user asked for the snooze to end.
    case snooze
    /// "Wecker testen" in Settings.
    case test

    public var title: String {
        switch self {
        case .timetable: "Fahrplan"
        case .gps: "Standort"
        case .geofence: "Standort"
        case .snooze: "Erinnerung"
        case .test: "Test"
        }
    }
}

public enum ExitAlarmPhase: String, Codable, Sendable, Hashable {
    /// Waiting. The time-based alarm is scheduled and, with location, the geofence is set.
    case armed
    /// The moment is close (within `ExitAlarmConfig.approachWindow`): the card pulses.
    case approaching
    /// Rang and waits for the user.
    case fired
    /// The user pushed "5 Min später".
    case snoozed
    /// The user pushed "Quittieren". The alarm is done and waits for the arrival to be over.
    case acknowledged
    /// Over, with a reason.
    case ended
}

public enum ExitAlarmEndReason: String, Codable, Sendable, Hashable {
    /// Acknowledged, and the arrival is over.
    case completed
    /// Arrival plus ten minutes passed without the alarm being acknowledged.
    case expired
    case cancelledByUser
    /// The follow of the run ended (arrived, cancelled, replaced, stopped).
    case followEnded
    /// Live-Daten were switched off (kill switch or the user's switch).
    case killSwitch

    public var title: String {
        switch self {
        case .completed: "Erledigt"
        case .expired: "Abgelaufen"
        case .cancelledByUser: "Abgebrochen"
        case .followEnded: "Fahrt beendet"
        case .killSwitch: "Live-Daten aus"
        }
    }
}

/// What the planner decides. The engine carries these out with the scheduler and the location provider.
public enum ExitAlarmEffect: Hashable, Sendable {
    /// Schedule (or move) the time-based alarm to this moment.
    case scheduleTimeAlarm(at: Date)
    /// Remove the time-based alarm.
    case cancelTimeAlarm
    /// Ring now, because the location (or a snooze or a test) decided. The time-based alarm is cancelled before.
    case ring(ExitAlarmSource)
    /// The target stop was passed and the alarm was not acknowledged.
    case ringPassed
    /// Silence what rings (acknowledged, snoozed, cancelled).
    case stopRinging
    /// Watch a circle around the stop.
    case setGeofence(center: GeoPoint, radius: Double)
    case removeGeofence
}

public struct ExitAlarmCommand: Hashable, Sendable {
    public var alarmID: String
    public var effect: ExitAlarmEffect
    public init(alarmID: String, effect: ExitAlarmEffect) {
        self.alarmID = alarmID
        self.effect = effect
    }
}

/// How much location the alarms need right now.
public enum ExitAlarmLocationNeed: Int, Comparable, Sendable {
    case none = 0
    /// Only the geofence (the system wakes the app when the circle is entered).
    case geofenceOnly = 1
    /// Low-power updates: the trip is running and the alarm is waiting.
    case continuous = 2

    public static func < (a: ExitAlarmLocationNeed, b: ExitAlarmLocationNeed) -> Bool { a.rawValue < b.rawValue }
}

/// Tunable numbers of the planner. The defaults are the product decisions of docs/EXIT_ALARM.md §3.
public struct ExitAlarmConfig: Sendable {
    /// The card pulses from this long before the trigger moment.
    public var approachWindow: TimeInterval = 180
    /// A moment that moves later by more than this beyond the window returns the alarm from approaching to armed.
    public var hysteresis: TimeInterval = 120
    /// A timetable change under this does not move the scheduled time-based alarm.
    public var rescheduleTolerance: TimeInterval = 30
    /// A fix older than this does not feed the GPS estimate (tunnel, GPS loss).
    public var staleFixAge: TimeInterval = 90
    /// A fix delivered later than this after its time is dropped on arrival (a cached fix at the start).
    public var maxFixLag: TimeInterval = 60
    /// A fix with a worse accuracy is ignored.
    public var maxAccuracy: Double = 300
    /// Below this smoothed speed there is no GPS estimate (standing at a station).
    public var minTravelSpeed: Double = 3
    /// The GPS must say "now" on this many fixes in a row before it rings.
    public var gpsConfirmations = 2
    /// Time constant of the speed smoothing.
    public var speedTimeConstant: TimeInterval = 30
    /// The alarm ends this long after the arrival.
    public var expiryAfterArrival: TimeInterval = 600
    /// An alarm that never learned its arrival (the timetable gave none) ends this long after it rang, or after it was set: the
    /// location must not run for ever for a moment nobody knows.
    public var maxLifeWithoutArrival: TimeInterval = 6 * 3600
    /// The geofence radius never goes below this.
    public var minGeofenceRadius: Double = 1500
    public var maxGeofenceRadius: Double = 20_000
    /// A geofence entry is ignored while the timetable says the trigger is further away than this (implausible).
    public var geofenceSanityWindow: TimeInterval = 30 * 60
    /// "Vorbeigefahren": the closest approach must have been this near …
    public var passedNearDistance: Double = 3000
    /// … and the distance must have grown by this much since …
    public var passedGrowth: Double = 600
    /// … over this many fixes in a row, at a speed of at least `minTravelSpeed`.
    public var passedGrowingFixes = 3
    /// By the timetable alone: this long after the departure of the stop.
    public var passedAfterDeparture: TimeInterval = 90
    /// The location window opens this long before the boarding departure.
    public var locationWindowLead: TimeInterval = 10 * 60
    /// A snooze lasts at least a minute and at most this long.
    public var maxSnooze: TimeInterval = 15 * 60

    public init() {}
    public static let standard = ExitAlarmConfig()
}
