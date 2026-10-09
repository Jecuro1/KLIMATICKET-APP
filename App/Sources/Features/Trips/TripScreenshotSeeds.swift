import Foundation
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
