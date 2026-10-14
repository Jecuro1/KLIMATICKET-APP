import AppIntents
import KlimaCore

// „Meine Routen“ as Siri and Shortcuts (docs/ROUTES_ALARMS.md §1.6): „Strecke suchen“ opens the planner on a saved route, with
// the same link the „Suchen“ button uses. The search then runs with the app's live consent, like any other search.

struct SavedRouteSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Strecke suchen"
    static let description = IntentDescription(
        "Öffnet in KlimaBilanz die Verbindungssuche auf einer deiner gespeicherten Strecken.")
    static let openAppWhenRun = true

    @Parameter(title: "Route", description: "Eine deiner gespeicherten Strecken.")
    var route: FavoriteRouteAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Strecke \(\.$route) suchen")
    }

    init() {}

    init(route: FavoriteRouteAppEntity) {
        self.route = route
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let link = SavedRouteIntentLink.link(for: route.id), let url = link.url else {
            throw SavedRouteIntentError.routeGone
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

enum SavedRouteIntentError: LocalizedError {
    case routeGone

    var errorDescription: String? {
        "Diese Strecke gibt es nicht mehr. Lege sie in „Meine Routen“ neu an."
    }
}

/// The planner link of a saved route, read from the widget snapshot the favourites are written to (station names and via
/// stops). The planner resolves names the same way as a `klimabilanz://plan` link.
enum SavedRouteIntentLink {
    static func link(for id: UUID) -> PlannerLink? {
        guard let favorite = WidgetSnapshot.load()?.favorites.first(where: { $0.id == id }),
              !favorite.fromName.isEmpty, !favorite.toName.isEmpty else { return nil }
        return PlannerLink(from: favorite.fromName, to: favorite.toName, vias: favorite.via ?? [])
    }
}
