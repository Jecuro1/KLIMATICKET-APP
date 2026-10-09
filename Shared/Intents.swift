import AppIntents
import Foundation
import WidgetKit

/// A favourite route as seen by Siri, Shortcuts and widgets (backed by the widget snapshot).
struct FavoriteRouteAppEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Lieblingsfahrt"
    static var defaultQuery = FavoriteRouteQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct FavoriteRouteQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [FavoriteRouteAppEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FavoriteRouteAppEntity] { all() }

    private func all() -> [FavoriteRouteAppEntity] {
        (WidgetSnapshot.load()?.favorites ?? []).map { FavoriteRouteAppEntity(id: $0.id, title: $0.title) }
    }
}

/// Logs a favourite route for today – usable from interactive widgets, Control Center and Siri.
struct LogFavoriteTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Lieblingsfahrt erfassen"
    static var description = IntentDescription("Erfasst eine deiner Lieblingsfahrten mit Datum und Uhrzeit von jetzt.")

    @Parameter(title: "Fahrt")
    var favorite: FavoriteRouteAppEntity

    init() {}

    init(favoriteID: UUID, title: String) {
        self.favorite = FavoriteRouteAppEntity(id: favoriteID, title: title)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        QuickLogQueue.enqueue(favoriteID: favorite.id)
        WidgetCenter.shared.reloadAllTimelines()
        if let snapshot = WidgetSnapshot.load() {
            let percent = Int((snapshot.amortizedFraction * 100).rounded())
            return .result(dialog: "\(favorite.title) erfasst. Dein Ticket ist jetzt zu \(percent) % amortisiert.")
        }
        return .result(dialog: "\(favorite.title) erfasst.")
    }
}

/// Opens the app with the add-trip sheet.
struct OpenAddTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Fahrt erfassen"
    static var description = IntentDescription("Öffnet KlimaBilanz direkt beim Erfassen einer neuen Fahrt.")
    static let supportedModes: IntentModes = .foreground

    static let pendingKey = "intent.openAddTrip"

    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(true, forKey: Self.pendingKey)
        NotificationCenter.default.post(name: QuickLogQueue.didEnqueue, object: nil)
        return .result()
    }
}

/// "Hat sich mein KlimaTicket schon rentiert?" – answers with the current balance.
struct ShowBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Ticket-Bilanz anzeigen"
    static var description = IntentDescription("Sagt dir, wie viel deines Tickets sich schon rentiert hat.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = WidgetSnapshot.load() else {
            return .result(dialog: "Öffne KlimaBilanz und lege zuerst dein Ticket an.")
        }
        let percent = Int((s.amortizedFraction * 100).rounded())
        let euro = Int(abs(s.net).rounded())
        if s.isPaidOff {
            return .result(dialog: "Dein \(s.ticketName) hat sich rentiert! Du bist \(euro) Euro im Plus – bei \(s.tripCount) Fahrten.")
        }
        return .result(dialog: "Dein \(s.ticketName) ist zu \(percent) Prozent amortisiert. Es fehlen noch \(euro) Euro.")
    }
}
