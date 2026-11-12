import Foundation
import SwiftData
import KlimaCore

// A ride the trip detection proposes ("Fahrten-Vorschläge", docs/TRIP_DETECTION.md). Additive and local: every property has a
// default (lightweight migration, old stores open unchanged), it is NOT part of the backup, the CSV export or the cloud
// sync, and it holds no coordinates – station names and ids, times, a label and a relative route sketch (0…1) only.
// Deleted with "Alle Standortdaten löschen" and with "Alle Daten löschen".

enum CandidateStatus: String, Sendable {
    /// Waiting in the inbox.
    case pending
    /// Confirmed: a trip was created (`tripID`).
    case accepted
    /// Dismissed: kept as a small record so the same pair of stations is down-weighted next time.
    case dismissed
}

@Model
final class TripCandidateEntity {
    var id: UUID = UUID()
    /// `DetectionSource.rawValue`.
    var sourceRaw: String = DetectionSource.background.rawValue
    /// `CandidateStatus.rawValue`.
    var statusRaw: String = CandidateStatus.pending.rawValue
    var fromName: String = ""
    var toName: String = ""
    var fromStationID: String?
    var toStationID: String?
    /// Hubs of a change, `TripViaCodec` encoding ("" = direct).
    var viaRaw: String = ""
    var modeRaw: String = TransportMode.train.rawValue
    var departedAt: Date = Date()
    var arrivedAt: Date = Date()
    var straightKm: Double = 0
    /// `DetectionConfidence.rawValue`.
    var confidenceRaw: String = DetectionConfidence.vielleicht.rawValue
    var score: Double = 0
    /// "code<TAB>weight<TAB>text" per line: why the ride was proposed (and what spoke against it).
    var reasonsRaw: String = ""
    /// `RouteSketch.encoded` ("" = none).
    var sketchRaw: String = ""
    /// "REX 5429 fährt um 08:07" when the optional timetable lookup confirmed the ride, else "".
    var timetableLine: String = ""
    /// The window of raw points this candidate was made of (they are deleted when it is decided).
    var evidenceStart: Date = Date()
    var evidenceEnd: Date = Date()
    /// The data can not exclude a car (every label below "sicher").
    var carNotExcluded: Bool = true
    /// The trip created when the candidate was accepted (for "Rückgängig").
    var tripID: UUID?
    var createdAt: Date = Date()
    var decidedAt: Date?

    init(_ c: DetectedCandidate, timetableLine: String = "") {
        id = UUID()
        sourceRaw = c.source.rawValue
        fromName = c.from.station.name
        toName = c.to.station.name
        fromStationID = c.from.station.id
        toStationID = c.to.station.id
        viaRaw = TripViaCodec.encode(c.via.map(TripVia.init))
        modeRaw = c.mode.rawValue
        departedAt = c.departure
        arrivedAt = c.arrival
        straightKm = c.straightKm
        confidenceRaw = c.confidence.rawValue
        score = c.rank.score
        reasonsRaw = Self.encode(reasons: c.rank.reasons)
        sketchRaw = c.sketch.encoded
        self.timetableLine = timetableLine
        evidenceStart = c.evidenceStart
        evidenceEnd = c.evidenceEnd
        carNotExcluded = c.rank.carNotExcluded
        createdAt = Date()
    }

    /// A ride without detection data: a recording's proposal or a migrated earlier suggestion.
    init(source: DetectionSource, fromName: String, toName: String, fromStationID: String?, toStationID: String?, via: [TripVia] = [],
         mode: TransportMode, departedAt: Date, arrivedAt: Date, straightKm: Double, confidence: DetectionConfidence,
         sketch: RouteSketch?, reasons: [RankingReason] = [], carNotExcluded: Bool = true) {
        id = UUID()
        sourceRaw = source.rawValue
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        viaRaw = TripViaCodec.encode(via)
        modeRaw = mode.rawValue
        self.departedAt = departedAt
        self.arrivedAt = arrivedAt
        self.straightKm = straightKm
        confidenceRaw = confidence.rawValue
        reasonsRaw = Self.encode(reasons: reasons)
        sketchRaw = sketch?.encoded ?? ""
        evidenceStart = departedAt
        evidenceEnd = arrivedAt
        self.carNotExcluded = carNotExcluded
        createdAt = Date()
    }

    // MARK: Typed views

    var status: CandidateStatus {
        get { CandidateStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var source: DetectionSource { DetectionSource(rawValue: sourceRaw) ?? .background }

    var mode: TransportMode {
        get { TransportMode(rawValue: modeRaw) ?? .train }
        set { modeRaw = newValue.rawValue }
    }

    var confidence: DetectionConfidence { DetectionConfidence(rawValue: confidenceRaw) ?? .vielleicht }

    var via: [TripVia] {
        get { TripViaCodec.decode(viaRaw) }
        set { viaRaw = TripViaCodec.encode(newValue) }
    }

    var sketch: RouteSketch? { sketchRaw.isEmpty ? nil : RouteSketch(encoded: sketchRaw) }

    var reasons: [RankingReason] { Self.decode(reasons: reasonsRaw) }

    var isPending: Bool { status == .pending }
    var duration: TimeInterval { arrivedAt.timeIntervalSince(departedAt) }

    /// Both stations are known, so the value can be computed and the ride can be confirmed.
    var isComplete: Bool { fromStationID != nil && toStationID != nil && fromStationID != toStationID }

    var known: KnownCandidate? {
        guard let from = fromStationID, let to = toStationID else { return nil }
        return KnownCandidate(fromStationID: from, toStationID: to, departure: departedAt, arrival: arrivedAt, isPending: isPending)
    }

    // MARK: Reasons text

    static func encode(reasons: [RankingReason]) -> String {
        reasons.map { r in
            [r.code, String(r.weight), r.text].map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    static func decode(reasons raw: String) -> [RankingReason] {
        raw.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, let weight = Double(fields[1]) else { return nil }
            return RankingReason(code: fields[0], text: fields[2], weight: weight)
        }
    }
}
