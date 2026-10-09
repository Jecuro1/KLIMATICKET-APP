import Foundation
import SwiftData
import Observation

/// Remembers exactly which rows "Demo ansehen" (onboarding) inserted, so Einstellungen › Daten › "Demo-Daten entfernen"
/// can take them out again without touching anything the user entered. The sample rows themselves carry no marker.
/// Observable, so the Daten section follows a change right away.
@Observable
@MainActor
final class DemoDataStore {
    private static let key = "demo.ids"
    private static let shared = DemoDataStore()

    /// Ids of the inserted tickets, trips, favourites and benefits (UserDefaults, read once per launch).
    private var storedIDs: Set<UUID>

    private init() {
        storedIDs = Set((UserDefaults.standard.stringArray(forKey: Self.key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    static var ids: Set<UUID> {
        get { shared.storedIDs }
        set {
            shared.storedIDs = newValue
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(newValue.map(\.uuidString), forKey: key)
            }
        }
    }

    /// Seeds the sample year (`DemoData`) and records the rows it added – the store may already hold rows of its own.
    /// Returns the number of sample trips.
    @discardableResult
    static func seed(into context: ModelContext) -> Int {
        let before = allIDs(in: context)
        DemoData.seed(into: context)
        let after = allIDs(in: context)
        ids.formUnion(after.all.subtracting(before.all))
        return after.trips.subtracting(before.trips).count
    }

    static func forget() { ids = [] }

    /// CI screenshots (`settingsDemo`): the seeded sample year counts as loaded via "Demo ansehen".
    static func markAllRowsAsDemo(in context: ModelContext) {
        ids = allIDs(in: context).all
    }

    private static func allIDs(in context: ModelContext) -> (trips: Set<UUID>, all: Set<UUID>) {
        let trips = Set(((try? context.fetch(FetchDescriptor<TripEntity>())) ?? []).map(\.id))
        var all = trips
        all.formUnion(((try? context.fetch(FetchDescriptor<TicketEntity>())) ?? []).map(\.id))
        all.formUnion(((try? context.fetch(FetchDescriptor<FavoriteRouteEntity>())) ?? []).map(\.id))
        all.formUnion(((try? context.fetch(FetchDescriptor<BenefitEntity>())) ?? []).map(\.id))
        return (trips, all)
    }
}
