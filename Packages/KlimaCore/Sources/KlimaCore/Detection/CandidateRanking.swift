import Foundation

// How sure is a proposed ride? The rules (stations at both ends, distance, speed, dwell) only decide whether a ride is
// proposed at all; this scoring decides the label. It never claims more than the data can give:
//   • "sicher" needs the timetable's confirmation (an optional lookup) AND platform-near rail stations at both ends,
//   • "wahrscheinlich" is the best a track alone can reach,
//   • "vielleicht" is everything that passes the rules but could as well be a car.
// A car ride between two towns with stations passes every rule (docs/TRIP_DETECTION.md §4) – so the score rewards what a
// car park does not look like (a rail station within 150 m, a known relation, stops of the train on the way) and takes
// away what it does (ends far from the platform, only bus stops).

public enum DetectionConfidence: String, Codable, Sendable, CaseIterable, Comparable {
    case vielleicht
    case wahrscheinlich
    case sicher

    private var rank: Int {
        switch self {
        case .vielleicht: 0
        case .wahrscheinlich: 1
        case .sicher: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// German label as shown in the inbox.
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Where a candidate came from.
public enum DetectionSource: String, Codable, Sendable {
    /// Hintergrund-Erkennung (coarse points and visits).
    case background
    /// "Fahrt aufzeichnen" (dense fixes, the person asked for it).
    case recording
    /// A suggestion of the earlier geofence detection (migrated).
    case legacy
}

/// What the optional timetable lookup found out.
public enum TimetableVerdict: Hashable, Sendable {
    /// A connection between the two stations at about the time of the ride.
    case confirmed(TimetableConnection)
    /// The timetable answered and has no such connection at that time.
    case noMatch
    /// No lookup (not allowed, not asked, no network, throttled).
    case unavailable
}

/// How often the same pair of stations was dismissed or accepted before (either direction).
public struct PairHistory: Hashable, Sendable {
    public var dismissed: [String: Int]
    public var accepted: [String: Int]

    public static let empty = PairHistory(dismissed: [:], accepted: [:])

    public init(dismissed: [String: Int] = [:], accepted: [String: Int] = [:]) {
        self.dismissed = dismissed
        self.accepted = accepted
    }

    /// Direction-independent key of two station ids.
    public static func key(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    public func dismissals(_ a: String, _ b: String) -> Int { dismissed[Self.key(a, b)] ?? 0 }
    public func acceptances(_ a: String, _ b: String) -> Int { accepted[Self.key(a, b)] ?? 0 }
}

/// All the facts of a ride the ranking looks at.
public struct CandidateEvidence: Hashable, Sendable {
    public var source: DetectionSource
    public var from: StationMatch
    public var to: StationMatch
    public var straightKm: Double
    public var averageSpeedKmh: Double
    /// Dwell at the stays at both ends (nil for a recording: nobody asks for a dwell there).
    public var dwellAtStart: TimeInterval?
    public var dwellAtEnd: TimeInterval?
    /// The pair is a relation of the official price table.
    public var knownRelation: Bool
    /// Stops at other rail stations on the way (dense tracks only).
    public var intermediateHalts: Int
    public var timetable: TimetableVerdict
    public var history: PairHistory

    public init(source: DetectionSource, from: StationMatch, to: StationMatch, straightKm: Double, averageSpeedKmh: Double,
                dwellAtStart: TimeInterval? = nil, dwellAtEnd: TimeInterval? = nil, knownRelation: Bool = false,
                intermediateHalts: Int = 0, timetable: TimetableVerdict = .unavailable, history: PairHistory = .empty) {
        self.source = source
        self.from = from
        self.to = to
        self.straightKm = straightKm
        self.averageSpeedKmh = averageSpeedKmh
        self.dwellAtStart = dwellAtStart
        self.dwellAtEnd = dwellAtEnd
        self.knownRelation = knownRelation
        self.intermediateHalts = intermediateHalts
        self.timetable = timetable
        self.history = history
    }
}

/// One line of the explanation: what spoke for or against the ride (German, no coordinates).
public struct RankingReason: Codable, Hashable, Sendable {
    public var code: String
    public var text: String
    public var weight: Double

    public init(code: String, text: String, weight: Double) {
        self.code = code
        self.text = text
        self.weight = weight
    }

    public var isPositive: Bool { weight > 0 }

    /// "code<TAB>weight<TAB>text" per line – one String for a stored candidate (tabs and line breaks inside become spaces).
    public static func encode(_ reasons: [RankingReason]) -> String {
        reasons.map { r in
            [r.code, String(r.weight), r.text].map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    /// Lines that do not parse are skipped.
    public static func decode(_ raw: String) -> [RankingReason] {
        raw.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, let weight = Double(fields[1]), weight.isFinite else { return nil }
            return RankingReason(code: fields[0], text: fields[2], weight: weight)
        }
    }
}

public struct CandidateRank: Hashable, Sendable {
    /// 0 … 1.5 (never below 0), higher = more likely a ride on public transport.
    public var score: Double
    public var confidence: DetectionConfidence
    public var reasons: [RankingReason]
    /// Whether the ride is worth proposing at all.
    public var isProposable: Bool
    /// A car can not be ruled out from the data (shown as a hint on the card).
    public var carNotExcluded: Bool

    public var positives: [RankingReason] { reasons.filter(\.isPositive) }
    public var negatives: [RankingReason] { reasons.filter { !$0.isPositive } }
}

public enum CandidateRanking {
    /// Score thresholds of the labels. Below `propose` nothing is shown.
    public static let proposeThreshold = 0.30
    public static let likelyThreshold = 0.60
    public static let certainThreshold = 1.00

    public static func rank(_ e: CandidateEvidence) -> CandidateRank {
        var reasons: [RankingReason] = []
        func add(_ code: String, _ text: String, _ weight: Double) { reasons.append(RankingReason(code: code, text: text, weight: weight)) }

        // Every ride that reaches the ranking passed the hard rules.
        add("rules", "Strecke, Tempo und Halt an beiden Enden passen", 0.30)

        for (side, match) in [("start", e.from), ("end", e.to)] {
            let name = match.station.name
            let metres = Int(match.distanceMeters.rounded())
            if match.isRailLike {
                if match.distanceMeters <= 150 {
                    add("\(side).platform", "\(name): Bahnhof nur \(metres) m entfernt", 0.15)
                } else if match.distanceMeters <= 300 {
                    add("\(side).near", "\(name): Bahnhof \(metres) m entfernt", 0.08)
                } else if match.distanceMeters > 400 {
                    add("\(side).far", "\(name): Bahnhof erst \(metres) m entfernt – auch ein Parkplatz wäre so nah", -0.10)
                }
            } else if match.distanceMeters > 100 {
                add("\(side).stopOnly", "\(name): nur eine Haltestelle (\(metres) m) – kein Bahnhof", -0.08)
            }
        }

        if e.knownRelation {
            add("relation", "Die Verbindung steht in der ÖBB-Preistabelle", 0.15)
        }
        if e.from.isRailLike && e.to.isRailLike {
            add("rail", "Beide Enden sind Bahnhöfe", 0.10)
        }
        if e.straightKm >= 15 {
            add("distance", "Luftlinie \(Format1.km(e.straightKm)) km", 0.10)
        }
        if e.intermediateHalts > 0 {
            let halts = min(e.intermediateHalts, 2)
            add("halts", e.intermediateHalts == 1 ? "1 Halt an einem Bahnhof unterwegs" : "\(e.intermediateHalts) Halte an Bahnhöfen unterwegs", 0.15 * Double(halts))
        }

        switch e.timetable {
        case .confirmed(let connection):
            add("timetable", "Fahrplan: \(connection.summary)", 0.35)
        case .noMatch:
            add("timetable.none", "Fahrplan: zu dieser Zeit keine Verbindung zwischen den beiden Bahnhöfen", -0.25)
        case .unavailable:
            break
        }

        let dismissals = e.history.dismissals(e.from.station.id, e.to.station.id)
        if dismissals > 0 {
            add("history.dismissed", dismissals == 1 ? "Diese Strecke hast du schon einmal verworfen"
                                                     : "Diese Strecke hast du \(dismissals)-mal verworfen", -0.20 * Double(min(dismissals, 3)))
        }
        if e.history.acceptances(e.from.station.id, e.to.station.id) > 0 {
            add("history.accepted", "Diese Strecke hast du schon erfasst", 0.10)
        }

        let score = max(0, reasons.reduce(0) { $0 + $1.weight })
        var confidence: DetectionConfidence = score >= likelyThreshold ? .wahrscheinlich : .vielleicht
        // "sicher": the timetable has the connection and both ends are rail stations right at the platform.
        if score >= certainThreshold, case .confirmed = e.timetable, e.from.isRailLike, e.to.isRailLike,
           e.from.distanceMeters <= 250, e.to.distanceMeters <= 250 {
            confidence = .sicher
        }
        let carNotExcluded = confidence < .sicher
        return CandidateRank(score: score, confidence: confidence, reasons: reasons, isProposable: score >= proposeThreshold,
                             carNotExcluded: carNotExcluded)
    }
}

/// Number formatting inside KlimaCore without locale surprises ("12,3").
enum Format1 {
    static func km(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let whole = Int(rounded)
        let tenth = Int(((rounded - Double(whole)) * 10).rounded())
        return rounded == rounded.rounded() ? "\(whole)" : "\(whole),\(tenth)"
    }
}
