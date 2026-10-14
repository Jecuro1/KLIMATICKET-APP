import AppIntents

/// Siri & Shortcuts phrases (German). Must live in the app target.
struct KlimaBilanzShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowBalanceIntent(),
            phrases: [
                "Hat sich mein KlimaTicket in \(.applicationName) gelohnt",
                "Hat sich mein Ticket mit \(.applicationName) rentiert",
                "Zeig meine \(.applicationName)",
                "\(.applicationName) Bilanz",
                "Wie viel habe ich mit \(.applicationName) gespart",
            ],
            shortTitle: "Ticket-Bilanz",
            systemImageName: "gauge.with.needle"
        )
        // The favourite phrases know every favourite by name once the app has called updateAppShortcutParameters()
        // (WidIntentSync, whenever the favourites change).
        AppShortcut(
            intent: LogFavoriteTripIntent(),
            phrases: [
                "\(\.$favorite) in \(.applicationName) erfassen",
                "Lieblingsfahrt \(\.$favorite) in \(.applicationName) erfassen",
                "\(.applicationName) \(\.$favorite) erfassen",
                "Lieblingsfahrt in \(.applicationName) erfassen",
            ],
            shortTitle: "Lieblingsfahrt",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: OpenAddTripIntent(),
            phrases: [
                "Fahrt in \(.applicationName) erfassen",
                "Neue Fahrt in \(.applicationName)",
                "\(.applicationName) Fahrt erfassen",
            ],
            shortTitle: "Fahrt erfassen",
            systemImageName: "plus.circle.fill"
        )
        // MARK: planner – one parameter per phrase; the origin defaults to the start station of the app
        AppShortcut(
            intent: PlanConnectionIntent(),
            phrases: [
                "Nächste Verbindung nach \(\.$to) in \(.applicationName)",
                "Verbindung nach \(\.$to) in \(.applicationName)",
            ],
            shortTitle: "Nächste Verbindung",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )
        // MARK: routes – „Meine Routen“: a saved route by name (the names come from the favourites, like the phrases above)
        AppShortcut(
            intent: SavedRouteSearchIntent(),
            phrases: [
                "Strecke \(\.$route) suchen in \(.applicationName)",
                "Verbindung für \(\.$route) in \(.applicationName) suchen",
            ],
            shortTitle: "Strecke suchen",
            systemImageName: "magnifyingglass"
        )
        // MARK: live
        AppShortcut(
            intent: RideStartIntent(),
            phrases: [
                "\(\.$favorite) mit \(.applicationName) starten",
                "Fahrt mit \(.applicationName) starten",
            ],
            shortTitle: "Fahrt starten",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}
