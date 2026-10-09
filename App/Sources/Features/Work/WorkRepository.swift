import Foundation
import KlimaCore

/// Writes of the "Arbeit & Steuer" module – through Repository, so save, widgets and sync stay consistent.
extension Repository {
    /// Sets the purpose of a logged trip (e.g. "Dienstreise" for the business-trip proof). No-op when unchanged.
    func workSetCategory(_ category: TripCategory?, for trip: TripEntity) {
        guard trip.category != category else { return }
        trip.category = category
        updateTrip(trip)
    }
}
