import Foundation
import SwiftData

/// Remembers exactly which rows "Demo ansehen" (onboarding) inserted, so Einstellungen › Daten › "Demo-Daten entfernen"
/// can take them out again without touching anything the user entered. The sample rows themselves carry no marker.
@MainActor
enum DemoDataStore {
    private static let key = "demo.ids"
    private static var cache: Set<UUID>?

    /// Ids of the inserted tickets, trips, favourites and benefits (UserDefaults, read once per launch).
    static var ids: Set<UUID> {
        get {
            if let cache { return cache }
            let stored = Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
            cache = stored
            return stored
        }
        set {
            cache = newValue
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

    private static func allIDs(in context: ModelContext) -> (trips: Set<UUID>, all: Set<UUID>) {
        let trips = Set(((try? context.fetch(FetchDescriptor<TripEntity>())) ?? []).map(\.id))
        var all = trips
        all.formUnion(((try? context.fetch(FetchDescriptor<TicketEntity>())) ?? []).map(\.id))
        all.formUnion(((try? context.fetch(FetchDescriptor<FavoriteRouteEntity>())) ?? []).map(\.id))
        all.formUnion(((try? context.fetch(FetchDescriptor<BenefitEntity>())) ?? []).map(\.id))
        return (trips, all)
    }
}
