import Foundation
import SwiftData

// MARK: via – vias saved while the Worker did not know the `via` column (docs/VIA.md §3) never went up: a push only
// sends rows changed since the last push, so those vias would stay on this device until the trip is edited again (a new
// phone restoring from the cloud would get the trip without them). The first sync with a Worker that lists `trip_via`
// therefore also pushes every trip and favourite that has vias – once per account. The server takes them (same
// updated_at, other content) unless another device changed the row later; rows without vias are never re-sent, so
// nothing can wipe vias another device uploaded.
@MainActor
enum SyncViaBackfill {
    private static func key(_ userID: String) -> String { "sync.user.\(userID.lowercased()).viaBackfill" }

    /// The server takes `via` and this account's local vias have not been uploaded in full yet.
    static func isNeeded(userID: String, serverSyncsVia: Bool, _ defaults: UserDefaults) -> Bool {
        serverSyncsVia && !defaults.bool(forKey: key(userID))
    }

    /// After a successful push that included the backfill.
    static func markDone(userID: String, _ defaults: UserDefaults) {
        defaults.set(true, forKey: key(userID))
    }

    /// Trips with vias that the regular push (`updatedAt > since`) leaves out.
    static func trips(unchangedSince since: Date, context: ModelContext) throws -> [TripEntity] {
        try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.viaRaw != "" && $0.updatedAt <= since }))
    }

    /// Favourites with vias that the regular push leaves out.
    static func favorites(unchangedSince since: Date, context: ModelContext) throws -> [FavoriteRouteEntity] {
        try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.viaRaw != "" && $0.updatedAt <= since }))
    }
}
