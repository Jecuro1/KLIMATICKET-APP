import Foundation
import SwiftData
import KlimaCore

/// The trip detection's writes (docs/TRIP_DETECTION.md). All of them go through the Repository: confirming a proposal creates
/// the ordinary `TripEntity` through `addTrip`, so Statistik, Jahresrückblick, widgets and sync pick it up like any ride.
extension Repository {
    // MARK: Reading

    func pendingCandidates() -> [TripCandidateEntity] {
        let pending = CandidateStatus.pending.rawValue
        return (try? context.fetch(FetchDescriptor<TripCandidateEntity>(predicate: #Predicate { $0.statusRaw == pending },
                                                                        sortBy: [SortDescriptor(\.departedAt, order: .reverse)]))) ?? []
    }

    func allCandidates() -> [TripCandidateEntity] {
        (try? context.fetch(FetchDescriptor<TripCandidateEntity>(sortBy: [SortDescriptor(\.departedAt, order: .reverse)]))) ?? []
    }

    /// How often each pair of stations was dismissed or accepted (direction-independent).
    func pairHistory() -> PairHistory {
        var history = PairHistory()
        for candidate in allCandidates() {
            guard let from = candidate.fromStationID, let to = candidate.toStationID else { continue }
            let key = PairHistory.key(from, to)
            switch candidate.status {
            case .dismissed: history.dismissed[key, default: 0] += 1
            case .accepted: history.accepted[key, default: 0] += 1
            case .pending: break
            }
        }
        return history
    }

    /// The trips entered in the last days – what a detected ride is compared with (dedup).
    func existingRides(since: Date) -> [ExistingRide] {
        let predicate = #Predicate<TripEntity> { $0.deletedAt == nil && $0.date >= since }
        let trips = (try? context.fetch(FetchDescriptor<TripEntity>(predicate: predicate))) ?? []
        return trips.map {
            ExistingRide(date: $0.date, fromStationID: $0.fromStationID, toStationID: $0.toStationID, fromName: $0.fromName, toName: $0.toName,
                         isRoundTrip: $0.isRoundTrip)
        }
    }

    // MARK: Detection result

    /// Which of the detector's candidates are new: not already entered as a ride (`CandidateDedup.split`), not already in the
    /// inbox and not decided before (`CandidateDedup.reconcile` says skip). Nothing is written – the optional timetable lookup
    /// runs on these, then `insert` files them.
    func triage(_ outcome: DetectionOutcome, now: Date = Date()) -> (fresh: [DetectedCandidate], duplicates: [DetectedCandidate]) {
        guard !outcome.candidates.isEmpty else { return ([], []) }
        let split = CandidateDedup.split(outcome.candidates, rides: existingRides(since: now.addingTimeInterval(-3 * 86_400)))
        let known = allCandidates().compactMap(\.known)
        let fresh = split.fresh.filter { CandidateDedup.reconcile($0, known: known) != .skip }
        return (fresh, split.covered.map(\.candidate))
    }

    struct DetectionIngest {
        var inserted: [TripCandidateEntity] = []
        var replaced: [(candidate: DetectedCandidate, count: Int)] = []
    }

    /// Puts candidates into the inbox. A longer ride replaces the pending shorter one it contains (the train stopped at a hub
    /// and went on): A → Hub becomes A → B.
    @discardableResult
    func insert(_ candidates: [DetectedCandidate], timetableLines: [UUID: String] = [:]) -> DetectionIngest {
        var result = DetectionIngest()
        var existing = allCandidates()
        for candidate in candidates.sorted(by: { $0.departure < $1.departure }) {
            let withStations = existing.compactMap { entity in entity.known.map { (entity: entity, known: $0) } }
            switch CandidateDedup.reconcile(candidate, known: withStations.map(\.known)) {
            case .skip:
                continue
            case .insert:
                break
            case .replace(let indexes):
                let doomed = indexes.filter(withStations.indices.contains).map { withStations[$0].entity }
                for entity in doomed { context.delete(entity) }
                existing.removeAll { entity in doomed.contains { $0 === entity } }
                result.replaced.append((candidate, doomed.count))
            }
            let entity = TripCandidateEntity(candidate, timetableLine: timetableLines[candidate.id] ?? "")
            context.insert(entity)
            existing.append(entity)
            result.inserted.append(entity)
        }
        if !result.inserted.isEmpty || !result.replaced.isEmpty { saveCandidates() }
        return result
    }

    /// Candidates are not synced and not exported: a plain save, without widget refresh or sync.
    func saveCandidates() {
        do { try context.save() } catch { Self.log.error("candidate save failed: \(String(describing: error), privacy: .public)") }
    }

    // MARK: Decisions

    /// What a ride is worth and how it is filed – the SAME inputs as the trip editor: the stations, the mode, the ride's date, the
    /// default class and discount of the settings (`CandidateValuation`, docs/TRIP_DETECTION.md §7).
    func facts(mode: TransportMode, date: Date, from: Station, to: Station, via: [Station] = []) -> CandidateTripFacts {
        CandidateValuation.facts(from: from, to: to, via: via, mode: mode, date: date, estimator: app.estimator,
                                 travelClass: app.settings.defaultTravelClass, discount: app.settings.defaultDiscount)
    }

    /// "Übernehmen": creates the ordinary ride. Returns it (for "Rückgängig"), nil when the stations are not both known.
    @discardableResult
    func accept(_ candidate: TripCandidateEntity, from: Station, to: Station, via: [Station]) -> TripEntity? {
        guard candidate.isPending, from.id != to.id else { return nil }
        let value = facts(mode: candidate.mode, date: candidate.departedAt, from: from, to: to, via: via)
        let trip = TripEntity(date: candidate.departedAt, fromName: from.name, toName: to.name, fromStationID: from.id, toStationID: to.id,
                              mode: candidate.mode, distanceKm: value.distanceKm, fareEUR: value.fareEUR, isFareManual: false, isRoundTrip: false,
                              travelClass: app.settings.defaultTravelClass, companions: 0, states: value.states, note: "")
        trip.via = via.map(TripVia.init)
        trip.priceSourceRaw = value.priceSource.rawValue
        trip.arrivalAt = candidate.arrivedAt
        candidate.fromName = from.name
        candidate.toName = to.name
        candidate.fromStationID = from.id
        candidate.toStationID = to.id
        candidate.status = .accepted
        candidate.tripID = trip.id
        candidate.decidedAt = Date()
        addTrip(trip)   // inserts, saves, refreshes the widgets, schedules the sync – like every ride
        RecentStations.remember(from.id)
        RecentStations.remember(to.id)
        return trip
    }

    /// "Rückgängig" after "Übernehmen": the ride goes to the trash like any deleted ride, the proposal is waiting again.
    func undoAccept(_ candidate: TripCandidateEntity, trip: TripEntity) {
        deleteTrip(trip)
        candidate.status = .pending
        candidate.tripID = nil
        candidate.decidedAt = nil
        saveCandidates()
    }

    /// "Verwerfen": the proposal stays as a small record (the pair is down-weighted next time), without raw points.
    func dismiss(_ candidate: TripCandidateEntity) {
        guard candidate.isPending else { return }
        candidate.status = .dismissed
        candidate.decidedAt = Date()
        saveCandidates()
    }

    /// "Rückgängig" after "Verwerfen": the proposal waits in the inbox again and no longer counts against its pair of stations.
    func undoDismiss(_ candidate: TripCandidateEntity) {
        guard candidate.status == .dismissed else { return }
        candidate.status = .pending
        candidate.decidedAt = nil
        saveCandidates()
    }

    /// Adds a proposal of "Fahrt aufzeichnen" (a recording is one explicit ride – it always goes to the inbox and the review).
    @discardableResult
    func insertRecordingCandidate(_ proposal: RecordingProposal) -> TripCandidateEntity {
        let entity = TripCandidateEntity(source: .recording, fromName: proposal.from?.station.name ?? "", toName: proposal.to?.station.name ?? "",
                                         fromStationID: proposal.from?.station.id, toStationID: proposal.to?.station.id,
                                         via: [], mode: proposal.mode, departedAt: proposal.start, arrivedAt: proposal.end,
                                         straightKm: proposal.straightKm, confidence: .sicher, sketch: proposal.sketch, carNotExcluded: false)
        context.insert(entity)
        saveCandidates()
        return entity
    }

    // MARK: Cleaning up

    /// Decided candidates older than 90 days go (the pair memory keeps three months).
    func pruneDecidedCandidates(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        var changed = false
        for candidate in allCandidates() where !candidate.isPending && (candidate.decidedAt ?? candidate.createdAt) < cutoff {
            context.delete(candidate)
            changed = true
        }
        // A proposal nobody looked at for two weeks is stale: the ride is long gone.
        for candidate in pendingCandidates() where candidate.arrivedAt < now.addingTimeInterval(-14 * 86_400) {
            context.delete(candidate)
            changed = true
        }
        if changed { saveCandidates() }
    }

    /// "Alle Standortdaten löschen" and "Alle Daten löschen": every proposal and record.
    func deleteAllCandidates() {
        for candidate in allCandidates() { context.delete(candidate) }
        saveCandidates()
    }
}
