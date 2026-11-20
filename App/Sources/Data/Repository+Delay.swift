import Foundation
import SwiftData
import KlimaCore

// MARK: delaydiary – the Verspätungs-Tagebuch writes through the Repository like every edit (docs/DELAY_DIARY.md §5).
// The two fields belong to the Zeitbilanz (`TripEntity.delayMinutes` / `delaySourceRaw`, docs/TIME_BALANCE.md §5): local only,
// not in the sync rows, carried by the JSON backup. A write stamps the trip (`touch()`), so the Zeitbilanz, Statistik and
// the diary – all keyed on `updatedAt` – recompute at once. No sync is started for it: nothing of the delay goes to the server.
extension Repository {
    /// Records the arrival delay of `trip` (0 = „pünktlich“; clamped to 0…240) with where it came from. One commit.
    @discardableResult
    func recordDelay(_ trip: TripEntity, minutes: Int, source: TripDelaySource) -> Bool {
        trip.delayMinutes = DelayDiaryRules.clamp(minutes)
        trip.delaySourceRaw = source.rawValue
        trip.touch()
        return commit(sync: false)
    }

    /// Marks several trips „pünktlich“ (Nachtragen) in one commit.
    @discardableResult
    func recordOnTime(_ trips: [TripEntity]) -> Bool {
        guard !trips.isEmpty else { return true }
        for trip in trips {
            trip.delayMinutes = 0
            trip.delaySourceRaw = TripDelaySource.manual.rawValue
            trip.touch()
        }
        return commit(sync: false)
    }

    /// „Entfernen“: the trip is „nicht erfasst“ again.
    @discardableResult
    func removeDelay(_ trip: TripEntity) -> Bool {
        trip.delayMinutes = 0
        trip.delaySourceRaw = ""
        trip.touch()
        return commit(sync: false)
    }

    /// „Rückgängig“: puts back what the trips had before (minutes and raw source as read before the change).
    @discardableResult
    func restoreDelays(_ previous: [(trip: TripEntity, minutes: Int, sourceRaw: String)]) -> Bool {
        guard !previous.isEmpty else { return true }
        for item in previous {
            item.trip.delayMinutes = item.minutes
            item.trip.delaySourceRaw = item.sourceRaw
            item.trip.touch()
        }
        return commit(sync: false)
    }

    /// The live trip with `id` (the diary's rows carry ids, the sheet edits the entity).
    func liveTrip(id: UUID) -> TripEntity? {
        let match: UUID = id
        var descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate { $0.id == match && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
