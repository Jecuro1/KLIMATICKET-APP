import Foundation
import SwiftData
import KlimaCore

// MARK: commute – the Pendel-Modus writes through the Repository like every ride (docs/COMMUTE.md §6).
extension Repository {
    /// Siri's „Pendelfahrt erfassen“ (`CommuteLogQueue`): the queued rides as ordinary trips in one commit – widget refresh and
    /// sync included. On a failed save nothing stays inserted and the caller keeps the queue. Nothing to add counts as done.
    @discardableResult
    func addCommuteTrips(_ trips: [TripEntity]) -> Bool {
        guard !trips.isEmpty else { return true }
        for trip in trips { context.insert(trip) }
        guard commit() else {
            for trip in trips { context.delete(trip) }
            return false
        }
        return true
    }
}
