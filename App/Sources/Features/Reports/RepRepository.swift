import Foundation
import SwiftData
import KlimaCore

extension Repository {
    /// Inserts a batch of imported trips in ONE transaction (one save, one widget refresh, one sync push).
    @discardableResult
    func importTrips(_ trips: [TripEntity]) -> [TripEntity] {
        guard !trips.isEmpty else { return [] }
        do {
            try context.transaction {
                for trip in trips { context.insert(trip) }
            }
        } catch {
            print("⚠️ import transaction failed: \(error) – inserting individually")
            for trip in trips where trip.modelContext == nil { context.insert(trip) }
        }
        commit()
        return trips
    }

    /// Undo for a CSV import: soft-deletes the whole batch (tombstones keep cloud sync consistent).
    func undoImport(_ trips: [TripEntity]) {
        let now = Date()
        for trip in trips where trip.deletedAt == nil {
            trip.deletedAt = now
            trip.touch()
        }
        commit()
    }

    /// Live benefits ("Vorteile") – used by the annual report as extra savings next to the payoff.
    func reportBenefits() -> [BenefitEntity] {
        (try? context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                           sortBy: [SortDescriptor(\.date)]))) ?? []
    }
}
