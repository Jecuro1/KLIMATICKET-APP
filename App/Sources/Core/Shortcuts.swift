import AppIntents

/// Siri & Shortcuts phrases (German). Must live in the app target.
struct KlimaBilanzShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowBalanceIntent(),
            phrases: [
                "Hat sich mein Ticket mit \(.applicationName) rentiert",
                "Zeig meine \(.applicationName)",
                "Wie viel habe ich mit \(.applicationName) gespart",
            ],
            shortTitle: "Bilanz",
            systemImageName: "gauge.with.needle"
        )
        AppShortcut(
            intent: LogFavoriteTripIntent(),
            phrases: [
                "\(\.$favorite) in \(.applicationName) erfassen",
                "Lieblingsfahrt in \(.applicationName) erfassen",
            ],
            shortTitle: "Lieblingsfahrt",
            systemImageName: "star.fill"
        )
        AppShortcut(
            intent: OpenAddTripIntent(),
            phrases: [
                "Neue Fahrt in \(.applicationName)",
                "Fahrt in \(.applicationName) erfassen",
            ],
            shortTitle: "Fahrt erfassen",
            systemImageName: "plus.circle.fill"
        )
    }
}
