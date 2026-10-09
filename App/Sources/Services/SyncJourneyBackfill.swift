import Foundation
import SwiftData

// MARK: trips – journeys saved while the Worker did not know `journey_id` / `leg_index` / `legs` (docs/JOURNEYS.md §3)
// went up without them: a push only sends rows changed since the last push, so another device would keep seeing those legs
// as trips of their own until each is edited again. The first sync with a Worker that lists `trip_journey` therefore also
// pushes every journey leg and Kombi-Vorlage once per account (like SyncViaBackfill). Rows without a journey are never
// re-sent, so nothing can take a leg out of a journey another device uploaded.
@MainActor
enum SyncJourneyBackfill {
    private static func key(_ userID: String) -> String { "sync.user.\(userID.lowercased()).journeyBackfill" }

    static func isNeeded(userID: String, serverSyncsJourney: Bool, _ defaults: UserDefaults) -> Bool {
        serverSyncsJourney && !defaults.bool(forKey: key(userID))
    }

    static func markDone(userID: String, _ defaults: UserDefaults) {
        defaults.set(true, forKey: key(userID))
    }

    /// Journey legs that the regular push (`updatedAt > since`) leaves out.
    static func trips(unchangedSince since: Date, context: ModelContext) throws -> [TripEntity] {
        try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.journeyID != nil && $0.updatedAt <= since }))
    }

    /// Kombi-Vorlagen that the regular push leaves out.
    static func favorites(unchangedSince since: Date, context: ModelContext) throws -> [FavoriteRouteEntity] {
        try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.legsRaw != "" && $0.updatedAt <= since }))
    }
}
