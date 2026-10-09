import Foundation
import SwiftData
import KlimaCore

/// Writes of the "Kategorien & ehrliche Bilanz" module – all through Repository (commit → widgets → sync).
extension Repository {
    /// Saves a trip's route as favourite and keeps its purpose, so quick logs (overview, widget, Siri) carry the category.
    @discardableResult
    func metaAddFavorite(from trip: TripEntity, title: String = "") -> FavoriteRouteEntity {
        let count = (try? context.fetchCount(FetchDescriptor<FavoriteRouteEntity>())) ?? 0
        let favorite = FavoriteRouteEntity(title: title, fromName: trip.fromName, toName: trip.toName, fromStationID: trip.fromStationID,
                                           toStationID: trip.toStationID, mode: trip.mode, distanceKm: trip.distanceKm,
                                           fareEUR: trip.fareEUR, isRoundTrip: trip.isRoundTrip, states: trip.states, sortIndex: count)
        favorite.categoryRaw = trip.categoryRaw
        favorite.viaRaw = trip.viaRaw   // MARK: via
        context.insert(favorite)
        commit()
        return favorite
    }

    /// Renames a favourite and sets its purpose (empty title = show the route).
    func metaUpdateFavorite(_ favorite: FavoriteRouteEntity, title: String, category: TripCategory?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = category?.rawValue ?? ""
        guard favorite.title != trimmed || favorite.categoryRaw != raw else { return }
        favorite.title = trimmed
        favorite.categoryRaw = raw
        favorite.touch()
        commit()
    }

    /// Sets purpose and "Ohne KlimaTicket nicht gefahren" of a logged trip (used by quick actions in the list).
    func metaSetPurpose(_ trip: TripEntity, category: TripCategory?, isInduced: Bool) {
        guard trip.category != category || trip.isInduced != isInduced else { return }
        trip.category = category
        trip.isInduced = isInduced
        updateTrip(trip)
    }
}
