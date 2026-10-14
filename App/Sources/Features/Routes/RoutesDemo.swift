import SwiftUI
import SwiftData
import KlimaCore

// „Meine Routen“ in `-KBDemo` and the CI screenshots (`routesList`, `routeDetail`, `routeEdit`): the demo favourites of
// DemoData, departures that are fixed and relative to now, and no network.

/// The demo departures of a saved route (only with `-KBDemo`; the live cache is never read in demo mode).
enum SavedRouteDemo {
    static func connections(for route: FavoriteRouteEntity, now: Date) -> [WidgetConnection] {
        let departures: [(line: String, minutes: Double, platform: String?)] = [
            ("RJ 66", 12, "Gl. 3"), ("RJ 68", 42, "Gl. 2"), ("REX 5", 75, nil), ("RJ 70", 103, "Gl. 1"),
        ]
        return departures.enumerated().map { index, departure in
            WidgetConnection(id: "\(route.id.uuidString)-\(index)",
                             planned: now.addingTimeInterval(departure.minutes * 60),
                             realtime: index == 1 ? now.addingTimeInterval((departure.minutes + 4) * 60) : nil,
                             changes: 0, durationMinutes: 62,
                             fromName: route.fromName, toName: route.toName,
                             lineName: departure.line, modeSymbol: "tram.fill",
                             direction: route.toName, platform: departure.platform)
        }
    }
}

struct RoutesScreenshotHost: View {
    static let screens: Set<String> = ["routesList", "routeDetail", "routeEdit"]

    let screen: String
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var routes: [FavoriteRouteEntity]

    var body: some View {
        // The demo route the screens show: the commute, or the first route when the demo data differs.
        let route = routes.first { $0.title == "Arbeit" } ?? routes.first
        switch screen {
        case "routeDetail":
            NavigationStack {
                if let route {
                    SavedRouteDetailView(route: route)
                } else {
                    ProgressView()
                }
            }
        case "routeEdit":
            NavigationStack {
                SavedRouteEditView(route: route)
            }
        default:
            SavedRoutesView()
        }
    }
}

struct AlarmsScreenshotHost: View {
    static let screens: Set<String> = ["alarmsList", "alarmHistory"]

    let screen: String

    var body: some View {
        NavigationStack {
            if screen == "alarmHistory" {
                AlarmHistoryView(model: AlarmsModel(demo: .history))
            } else {
                AlarmsView(demo: .list)
            }
        }
    }
}
