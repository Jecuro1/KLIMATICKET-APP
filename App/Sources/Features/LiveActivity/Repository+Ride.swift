import Foundation
import SwiftData
import KlimaCore

/// Saving rides of the "Unterwegs" Live Activity as trips (all writes go through the Repository).
extension Repository {
    /// Saves the rides the Live Activity handed over ("Fahrt speichern"). Returns what was added.
    @discardableResult
    func ingestFinishedRides() -> [(record: RideRecord, trip: TripEntity)] {
        let records = RideStore.drainFinished()
        guard !records.isEmpty else { return [] }
        let saved = records.compactMap { record in insertRideTrip(record).map { (record: record, trip: $0) } }
        if !saved.isEmpty { commit() }
        return saved
    }

    /// Saves a ride right away (the app's "Fahrt noch speichern?" question).
    @discardableResult
    func saveRide(_ record: RideRecord) -> TripEntity? {
        RideStore.remove(record.id)
        guard let trip = insertRideTrip(record) else { return nil }
        commit()
        return trip
    }

    /// The trip of a ride: from its favourite (current fare, category, usage count – like a quick log) or from the
    /// stored form. The ride id becomes the trip id, so a ride is never saved twice.
    private func insertRideTrip(_ record: RideRecord) -> TripEntity? {
        let id = record.id
        let existing = (try? context.fetchCount(FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == id }))) ?? 0
        guard existing == 0 else { return nil }
        let trip: TripEntity
        if let favoriteID = record.trip.favoriteID, let favorite = liveFavorites().first(where: { $0.id == favoriteID }) {
            trip = favorite.makeTrip(on: record.startedAt)
            favorite.usageCount += 1
            favorite.touch()
        } else {
            let t = record.trip
            guard t.isValid else { return nil }
            trip = TripEntity(date: record.startedAt, fromName: t.fromName, toName: t.toName, fromStationID: t.fromStationID,
                              toStationID: t.toStationID, mode: t.mode, distanceKm: t.distanceKm, fareEUR: t.fareEUR,
                              isFareManual: t.isFareManual, isRoundTrip: t.isRoundTrip, travelClass: t.travelClass,
                              companions: t.companions, states: t.states, note: t.note)
            trip.category = t.category
            trip.isInduced = t.isInduced
        }
        trip.id = record.id
        context.insert(trip)
        return trip
    }
}
