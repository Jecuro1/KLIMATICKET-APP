import SwiftUI
import SwiftData
import KlimaCore

/// Extra rows for the trips area's CI screenshot routes (RootView › ScreenshotRouter, `// MARK: trips`). They go into the
/// throwaway screenshot store of that one launch only – the shared demo year (DemoData) and every other screen's totals
/// stay as they are.
@MainActor
enum TripScreenshotSeeds {
    /// "tripEditFare": an own price that looks off (€ 150 for Wien → Mödling) – the editor shows the plausibility callout.
    static func implausibleFareTrip(context: ModelContext, app: AppState) -> TripEntity {
        let stations = app.stations
        let from = stations.station(named: "Wien Hbf"), to = stations.station(named: "Mödling")
        let trip = TripEntity(date: Date().addingTimeInterval(-2 * 3600), fromName: from?.name ?? "Wien Hauptbahnhof",
                              toName: to?.name ?? "Mödling", fromStationID: from?.id, toStationID: to?.id, mode: .train,
                              distanceKm: 17, fareEUR: 150, isFareManual: true, states: ["NÖ", "W"])
        context.insert(trip)
        try? context.save()
        return trip
    }
}

extension TripScreenshotSeeds {
    /// "Reise mit Etappen" for the journey screenshots: Lech → Langen am Arlberg (Bus) → Wien Hbf (Zug) → Wien Praterstern
    /// (U-Bahn), two hours ago, priced by the estimator like a logged journey (the bus stop has no tariff data: € 5,80).
    static func journey(context: ModelContext, app: AppState) -> [TripEntity] {
        let stations = app.stations
        let date = Date().addingTimeInterval(-2 * 3600)
        let lech = stations.station(named: "Lech")
        let langen = stations.station(id: "at:48:1226") ?? stations.station(named: "Langen am Arlberg")
        let wien = stations.station(id: "at:49:1349") ?? stations.station(named: "Wien Hauptbahnhof")
        let wienMetro = stations.station(id: "wl:60201349") ?? wien
        let praterstern = stations.station(id: "wl:60201040") ?? stations.station(named: "Wien Praterstern")
        let plan: [(from: Station?, fromName: String, to: Station?, toName: String, mode: TransportMode, km: Double, fare: Double)] = [
            (lech, "Lech", langen, "Langen am Arlberg", .bus, 16, 5.8),
            (langen, "Langen am Arlberg", wien, "Wien Hauptbahnhof", .train, 612, 81.4),
            (wienMetro, "Wien Hauptbahnhof", praterstern, "Wien Praterstern", .metro, 4.5, 3.2),
        ]
        let journeyID = UUID()
        let legs = plan.enumerated().map { index, leg -> TripEntity in
            var km = leg.km, fare = leg.fare
            if let a = leg.from, let b = leg.to, a.id != b.id {
                let estimate = app.estimator.estimate(from: a, via: [], to: b, mode: leg.mode, travelClass: .second, discount: .none,
                                                      date: date)
                if estimate.fareEUR > 0 { fare = estimate.fareEUR; km = estimate.distanceKm }
            }
            let trip = TripEntity(date: date, fromName: leg.from?.name ?? leg.fromName, toName: leg.to?.name ?? leg.toName,
                                  fromStationID: leg.from?.id, toStationID: leg.to?.id, mode: leg.mode, distanceKm: km,
                                  fareEUR: fare, isFareManual: leg.from == nil || leg.to == nil,
                                  states: Array(Set([leg.from?.state, leg.to?.state].compactMap { $0 })).sorted())
            trip.category = .visit
            trip.journeyID = journeyID
            trip.legIndex = index
            if index == 0 { trip.note = "Zu Oma nach Wien – Gepäck im Railjet" }
            context.insert(trip)
            return trip
        }
        try? context.save()
        return legs
    }
}

/// CI screenshot routes of journeys (RootView › ScreenshotRouter): seeds the demo journey into this launch's store, then
/// shows the screen – "tripsJourney" (Fahrten, journey unfolded), "journeyDetail", "addTripJourney" (the editor filled from
/// the journey's Kombi-Vorlage), "favoritesCombo" (Favoriten with the Kombi-Vorlage).
struct TripScreenshotJourneyHost: View {
    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var journeyID: UUID?

    var body: some View {
        Group {
            switch screen {
            case "journeyDetail":
                NavigationStack {
                    if let journeyID { TripJourneyDetailView(journeyID: journeyID) }
                }
            case "favoritesCombo":
                NavigationStack {
                    if journeyID != nil { FavoritesManagerView() }
                }
            default:
                MainTabView()
            }
        }
        .task {
            guard journeyID == nil else { return }
            let legs = TripScreenshotSeeds.journey(context: context, app: app)
            let repository = Repository(context: context, app: app)
            switch screen {
            case "tripsJourney":
                app.selectedTab = .trips
            case "favoritesCombo":
                repository.metaAddFavorite(fromJourney: legs, title: "Zu Oma")
            case "addTripJourney":
                let favorite = repository.metaAddFavorite(fromJourney: legs, title: "Zu Oma")
                journeyID = legs.first?.journeyID
                try? await Task.sleep(for: .milliseconds(600))
                var draft = TripDraft()
                draft.favorite = favorite
                app.presentAddTrip(draft)
                return
            default:
                break
            }
            journeyID = legs.first?.journeyID
        }
    }
}
