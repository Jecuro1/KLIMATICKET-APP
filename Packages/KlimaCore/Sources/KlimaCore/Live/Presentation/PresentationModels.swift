import Foundation

// CONTRACT (Step 0) – owned by WP-C after the contracts commit. Pure, UI-framework-free view-model values that the
// app renders 1:1 (SPEC §C3). Expected values for tests: fixtures/ux/vm_*.json.

/// Realtime colour state used everywhere (cards, timeline, board, Live Activity).
public enum RealtimeState: String, Codable, Sendable, Hashable {
    /// No realtime → plain ink, label "Fahrplan" in detail.
    case scheduled
    /// Δ ≤ 0 min → "pünktlich" (positiveText, live dot).
    case onTime
    /// 1…4 min → "12:20 +4" (summitText).
    case late
    /// ≥ 5 min → "12:23 +7" (negativeText).
    case veryLate
    /// dCncl/aCncl/isCncl → "Fällt aus".
    case cancelled
}

public struct RealtimeLabel: Codable, Sendable, Hashable {
    public var state: RealtimeState
    /// Rounded minutes (nil without realtime).
    public var delayMinutes: Int?
    /// "pünktlich", "12:20 +4", "Fällt aus", nil for scheduled.
    public var text: String?

    public init(state: RealtimeState, delayMinutes: Int? = nil, text: String? = nil) {
        self.state = state
        self.delayMinutes = delayMinutes
        self.text = text
    }
}

public enum TransferRisk: String, Codable, Sendable, Hashable {
    /// buffer ≥ 5 min
    case ok
    /// 2…4 min
    case tight
    /// < 2 min
    case atRisk
}

public struct TransferInfo: Codable, Sendable, Hashable {
    /// Display name of the station where the change happens.
    public var stationName: String
    public var walkMinutes: Int
    /// Next departure − arrival − walk, realtime where known.
    public var bufferMinutes: Int
    public var risk: TransferRisk
    /// "15 min Umstiegszeit" / "Knapp: 3 min zum Umsteigen" / "Anschluss gefährdet".
    public var text: String

    public init(stationName: String, walkMinutes: Int, bufferMinutes: Int, risk: TransferRisk, text: String) {
        self.stationName = stationName
        self.walkMinutes = walkMinutes
        self.bufferMinutes = bufferMinutes
        self.risk = risk
        self.text = text
    }
}

public enum NoticeSeverity: String, Codable, Sendable, Hashable, Comparable {
    case info, crowd, warning, critical

    private var rank: Int { [.info: 0, .crowd: 1, .warning: 2, .critical: 3][self] ?? 0 }
    public static func < (a: NoticeSeverity, b: NoticeSeverity) -> Bool { a.rank < b.rank }
}

public struct Notice: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var severity: NoticeSeverity
    public var title: String
    public var text: String?
    public var priority: Int?

    public init(id: String, severity: NoticeSeverity, title: String, text: String? = nil, priority: Int? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.text = text
        self.priority = priority
    }
}

/// "St.Anton am Arlberg Bahnhof (Vorplatz)" → name "St. Anton am Arlberg", sub "Vorplatz".
public struct DisplayName: Codable, Sendable, Hashable {
    public var raw: String
    public var name: String
    public var sub: String?

    public init(raw: String, name: String, sub: String? = nil) {
        self.raw = raw
        self.name = name
        self.sub = sub
    }
}

public struct JourneyBarSegment: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case ride, walk, wait }

    public var kind: Kind
    public var mode: TransportMode?
    /// Plate text for ride segments ("RJX", "760", "S 4").
    public var plate: String?
    public var minutes: Int
    /// Share of the total journey duration (sums to 1 ± 0.001).
    public var fraction: Double

    public init(kind: Kind, mode: TransportMode? = nil, plate: String? = nil, minutes: Int, fraction: Double) {
        self.kind = kind
        self.mode = mode
        self.plate = plate
        self.minutes = minutes
        self.fraction = fraction
    }
}

/// Everything a Live Activity / in-app "live journey" accessory needs at one moment (SPEC §C3.6). The app maps it onto
/// the separately built `RideActivityAttributes.ContentState`; KlimaCore never imports ActivityKit.
public struct LiveJourneySnapshot: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable {
        case beforeDeparture, riding, transferring, arrived, cancelled
    }

    public var journeyID: String
    public var phase: Phase
    public var originName: String
    public var destinationName: String
    /// Line of the current or next ride leg ("RJX 19910").
    public var currentLine: String?
    public var currentMode: TransportMode?
    /// Next relevant event (departure, transfer departure or final arrival).
    public var nextEventTitle: String
    public var nextEventTime: Date?
    public var nextEventPlatform: String?
    public var nextEventRealtime: RealtimeLabel
    /// 0…1 along the journey by elapsed time (realtime-aware).
    public var progress: Double
    public var transfer: TransferInfo?
    public var arrival: Date?
    /// Regular price for the "Angekommen · Fahrt erfassen · € 29,70" end state.
    public var regularPriceEUR: Double?
    /// Snapshot is stale after this date (next event + 2 min).
    public var staleAfter: Date?
    public var updatedAt: Date

    public init(journeyID: String, phase: Phase, originName: String, destinationName: String, currentLine: String? = nil,
                currentMode: TransportMode? = nil, nextEventTitle: String, nextEventTime: Date? = nil, nextEventPlatform: String? = nil,
                nextEventRealtime: RealtimeLabel, progress: Double, transfer: TransferInfo? = nil, arrival: Date? = nil,
                regularPriceEUR: Double? = nil, staleAfter: Date? = nil, updatedAt: Date) {
        self.journeyID = journeyID
        self.phase = phase
        self.originName = originName
        self.destinationName = destinationName
        self.currentLine = currentLine
        self.currentMode = currentMode
        self.nextEventTitle = nextEventTitle
        self.nextEventTime = nextEventTime
        self.nextEventPlatform = nextEventPlatform
        self.nextEventRealtime = nextEventRealtime
        self.progress = progress
        self.transfer = transfer
        self.arrival = arrival
        self.regularPriceEUR = regularPriceEUR
        self.staleAfter = staleAfter
        self.updatedAt = updatedAt
    }
}
