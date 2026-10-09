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

    /// "Als Kombi-Vorlage speichern": a journey's legs as one favourite (docs/JOURNEYS.md). The favourite's own fields sum
    /// the legs up (first start, last destination, main mode, km and fare), `legsRaw` keeps each leg. One leg → a plain
    /// favourite.  // MARK: trips
    @discardableResult
    func metaAddFavorite(fromJourney legs: [TripEntity], title: String = "") -> FavoriteRouteEntity? {
        guard let first = legs.first, let last = legs.last else { return nil }
        guard legs.count > 1 else { return metaAddFavorite(from: first, title: title) }
        let count = (try? context.fetchCount(FetchDescriptor<FavoriteRouteEntity>())) ?? 0
        let mode = JourneySummary.mainMode(legs.map { ($0.mode, $0.distanceKm, $0.fareEUR) }) ?? first.mode
        let states = Set(legs.flatMap(\.states)).sorted()
        let favorite = FavoriteRouteEntity(title: title, fromName: first.fromName, toName: last.toName,
                                           fromStationID: first.fromStationID, toStationID: last.toStationID, mode: mode,
                                           distanceKm: legs.reduce(0) { $0 + $1.distanceKm },
                                           fareEUR: legs.reduce(0) { $0 + $1.fareEUR },
                                           isRoundTrip: first.isRoundTrip, states: states, sortIndex: count)
        favorite.categoryRaw = first.categoryRaw
        favorite.legsRaw = JourneyLegCodec.encode(legs.map { leg in
            JourneyLeg(fromName: leg.fromName, fromStationID: leg.fromStationID, toName: leg.toName, toStationID: leg.toStationID,
                       mode: leg.mode, distanceKm: leg.distanceKm, fareEUR: leg.fareEUR, viaRaw: leg.viaRaw,
                       statesRaw: leg.statesRaw)
        })
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
