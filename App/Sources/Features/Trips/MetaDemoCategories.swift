import Foundation
import KlimaCore

/// Plausible purposes for the demo year (screenshots, "Demo ansehen"): the Arlberg commuter's weekday trips to
/// Innsbruck and Landeck are "Arbeitsweg" (a few Innsbruck days are "Dienstreise"), the after-work bus to Lech mixes
/// Freizeit / Erledigung / Besuch, weekends are Besuch (Bludenz), Freizeit and Urlaub – and six weekend excursions are
/// marked "Ohne KlimaTicket wäre ich nicht gefahren". A few trips stay uncategorised, as in real life.
/// Only purposes change – dates, fares and values (and therefore the demo totals) stay exactly the same.
@MainActor
enum MetaDemoCategories {
    /// Number of weekend excursions marked as induced (≈ 8 % of the demo trips, in line with the BMIMI report).
    static let inducedExcursions = 6

    static func assign(trips: [TripEntity], favorites: [FavoriteRouteEntity]) {
        let calendar = Calendar.vienna
        let routes = DemoData.routes
        func isRoute(_ trip: TripEntity, _ index: Int) -> Bool {
            routes.indices.contains(index) && trip.fromName == routes[index].from && trip.toName == routes[index].to
        }

        var innsbruckDays = 0
        var lechEvenings = 0
        var excursions: [TripEntity] = []
        for trip in trips.sorted(by: { $0.date < $1.date }) {
            let weekday = calendar.component(.weekday, from: trip.date)   // 1 = Sonntag, 7 = Samstag
            let isWeekend = weekday == 1 || weekday == 7
            if isRoute(trip, 0) {                       // St. Anton – Innsbruck
                if isWeekend {
                    trip.category = .leisure
                } else {
                    trip.category = innsbruckDays % 3 == 1 ? .business : .commute
                    innsbruckDays += 1
                }
            } else if isRoute(trip, 1) {                // St. Anton – Landeck-Zams
                trip.category = isWeekend ? .errand : .commute
            } else if isRoute(trip, 9) {                // St. Anton – Lech (after work)
                let pattern: [TripCategory?] = [.leisure, .errand, .leisure, .visit, .leisure, nil]
                trip.category = pattern[lechEvenings % pattern.count]
                lechEvenings += 1
            } else if isRoute(trip, 2) {                // St. Anton – Bludenz: family
                trip.category = .visit
            } else if isRoute(trip, 3) || isRoute(trip, 7) {   // Bodensee, Hungerburg
                trip.category = .leisure
                if isWeekend { excursions.append(trip) }
            } else if isRoute(trip, 4) || isRoute(trip, 5) || isRoute(trip, 10) {   // Wien, Salzburg, Graz–Klagenfurt
                trip.category = .holiday
                if isWeekend { excursions.append(trip) }
            } else if isRoute(trip, 6) {                // U-Bahn in Wien during the city trip
                trip.category = .holiday
            }
            // Innsbruck Hbf – Marktplatz (Bim) stays uncategorised.
        }

        // Evenly spread over the year, so the honest balance tells a calm, believable story.
        let count = min(inducedExcursions, excursions.count)
        if count > 0 {
            for i in 0..<count {
                let index = count == 1 ? 0 : Int((Double(i) * Double(excursions.count - 1) / Double(count - 1)).rounded())
                excursions[index].isInduced = true
            }
        }

        // Favourites carry their purpose into quick logs.
        for favorite in favorites {
            switch favorite.toName {
            case routes[0].to, routes[1].to: favorite.categoryRaw = TripCategory.commute.rawValue
            case routes[2].to: favorite.categoryRaw = TripCategory.visit.rawValue
            case routes[9].to: favorite.categoryRaw = TripCategory.leisure.rawValue
            default: break
            }
        }
    }
}
