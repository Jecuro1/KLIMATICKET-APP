import Foundation

// MARK: - „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md) – saved trips as the diary reads them

/// One saved trip (or one leg of a „Reise mit Etappen“) with what the diary needs. The app maps `TripEntity` to this value.
public struct DelayDiaryTrip: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var fromName: String
    public var toName: String
    public var mode: TransportMode
    /// „RJX 662 · Bus 4235“ – what the Fahrplan saved with the trip ("" when unknown).
    public var lineSummary: String
    public var journeyID: UUID?
    public var legIndex: Int
    public var isRoundTrip: Bool
    /// Arrival delay in minutes; counted only when `delaySource` is set (`TripEntity.delayMinutes` / `delaySourceRaw`).
    public var delayMinutes: Int
    public var delaySource: TripDelaySource?

    public init(id: UUID = UUID(), date: Date, fromName: String = "", toName: String = "", mode: TransportMode = .train,
                lineSummary: String = "", journeyID: UUID? = nil, legIndex: Int = 0, isRoundTrip: Bool = false,
                delayMinutes: Int = 0, delaySource: TripDelaySource? = nil) {
        self.id = id
        self.date = date
        self.fromName = fromName
        self.toName = toName
        self.mode = mode
        self.lineSummary = lineSummary
        self.journeyID = journeyID
        self.legIndex = legIndex
        self.isRoundTrip = isRoundTrip
        self.delayMinutes = delayMinutes
        self.delaySource = delaySource
    }

    /// The same trip as the Zeitbilanz reads it, plus the line summary.
    public init(_ input: TimeTripInput, lineSummary: String = "") {
        self.init(id: input.id, date: input.date, fromName: input.fromName, toName: input.toName, mode: input.mode,
                  lineSummary: lineSummary, journeyID: input.journeyID, legIndex: input.legIndex, isRoundTrip: input.isRoundTrip,
                  delayMinutes: input.delayMinutes, delaySource: input.delaySource)
    }

    /// The recorded delay (0…240), nil when none was recorded – the same rule as `TimeTripInput.recordedDelayMinutes`.
    public var recordedDelayMinutes: Int? {
        guard delaySource != nil else { return nil }
        return DelayDiaryRules.clamp(delayMinutes)
    }
}

/// One „Fahrt“ of the diary: a trip of its own, or a journey once (like the Zeitbilanz and Statistik count it). A journey's
/// arrival is its last recorded one – the time missing at the destination; an earlier leg's delay is not added on top.
public struct DelayDiaryEntry: Hashable, Sendable, Identifiable {
    /// The journey's id, or the trip's own.
    public var id: UUID
    /// Departure of the first counted leg.
    public var date: Date
    public var fromName: String
    public var toName: String
    /// The legs' line summaries, distinct, in travel order („RJX 662 · S 1“); "" when none is known.
    public var lines: String
    /// Modes of the counted legs, distinct, in travel order.
    public var modes: [TransportMode]
    public var legCount: Int
    public var isRoundTrip: Bool
    /// Every counted leg, in travel order.
    public var tripIDs: [UUID]
    /// The recorded arrival delay, nil when no counted leg has one.
    public var minutes: Int?
    public var source: TripDelaySource?
    /// The leg that carries `minutes` (the one the entry sheet edits); the last leg when nothing is recorded.
    public var editTripID: UUID
    /// At or above the personal mark.
    public var isLate: Bool

    public var isRecorded: Bool { minutes != nil }
    public var isJourney: Bool { legCount > 1 }
}

public enum DelayDiaryEntries {
    /// The Fahrten of `trips` (scope applied, only up to `now`), oldest first. A journey's legs outside the scope are left out
    /// (with „Nur Bahn“ a bus leg neither counts nor carries the arrival); a journey without a leg in scope is not a Fahrt.
    public static func make(_ trips: [DelayDiaryTrip], options: DelayDiaryOptions = DelayDiaryOptions(), now: Date) -> [DelayDiaryEntry] {
        var groups: [UUID: [DelayDiaryTrip]] = [:]
        var order: [UUID] = []
        for trip in trips where trip.date <= now && options.scope.includes(trip.mode) {
            let key = trip.journeyID ?? trip.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(trip)
        }
        let threshold = DelayDiaryRules.normalizedThreshold(options.thresholdMinutes)
        var entries: [DelayDiaryEntry] = []
        entries.reserveCapacity(order.count)
        for key in order {
            guard let legs = groups[key]?.sorted(by: legOrder), let first = legs.first, let last = legs.last else { continue }
            let recorded = legs.last { $0.recordedDelayMinutes != nil }
            let minutes = recorded?.recordedDelayMinutes
            var modes: [TransportMode] = []
            var lines: [String] = []
            for leg in legs {
                if !modes.contains(leg.mode) { modes.append(leg.mode) }
                let line = leg.lineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty, !lines.contains(line) { lines.append(line) }
            }
            entries.append(DelayDiaryEntry(
                id: key, date: first.date, fromName: first.fromName, toName: last.toName, lines: lines.joined(separator: " · "),
                modes: modes, legCount: legs.count, isRoundTrip: legs.contains { $0.isRoundTrip }, tripIDs: legs.map(\.id),
                minutes: minutes, source: recorded?.delaySource, editTripID: recorded?.id ?? last.id,
                isLate: minutes.map { DelayDiaryRules.isLate($0, threshold: threshold) } ?? false))
        }
        return entries.sorted(by: entryOrder)
    }

    static func legOrder(_ lhs: DelayDiaryTrip, _ rhs: DelayDiaryTrip) -> Bool {
        if lhs.legIndex != rhs.legIndex { return lhs.legIndex < rhs.legIndex }
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Oldest first; the same moment by route, then id – a stable order for the list and the PDF.
    static func entryOrder(_ lhs: DelayDiaryEntry, _ rhs: DelayDiaryEntry) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        let left = "\(lhs.fromName)\u{1F}\(lhs.toName)", right = "\(rhs.fromName)\u{1F}\(rhs.toName)"
        if left != right { return left < right }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
