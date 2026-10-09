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
        return .result(dialog: "\(IntentCopy.logged(favorite.title, snapshot: WidgetSnapshot.load()))")
    }
}

/// Opens the app with the add-trip sheet.
struct OpenAddTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Fahrt erfassen"
    static var description = IntentDescription("Öffnet KlimaBilanz direkt beim Erfassen einer neuen Fahrt.")
    static let supportedModes: IntentModes = .foreground

    static let pendingKey = "intent.openAddTrip"

    @MainActor
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
        .result(dialog: "\(IntentCopy.balance(WidgetSnapshot.load()))")
    }
}

/// Spoken / shown answers of the intents – the same rounded figures as the widgets (`WidFigures`, `WidFormat.percent`),
/// so Siri never says "100 Prozent" while € 4 are still missing.
enum IntentCopy {
    static let noTicket = "Öffne KlimaBilanz und lege zuerst dein Ticket an."

    /// "Dein KlimaTicket Ö Klassik" · "Dein Ticket" (for names that do not read as one, e.g. "Arbeit 2026").
    static func ticket(_ s: WidgetSnapshot) -> String {
        s.ticketName.localizedCaseInsensitiveContains("ticket") ? "Dein \(s.ticketName)" : "Dein Ticket"
    }

    static func balance(_ snapshot: WidgetSnapshot?, now: Date = Date()) -> String {
        guard let s = snapshot else { return noTicket }
        let percent = WidFormat.percentValue(s.amortizedFraction)
        if WidInsight.isPaidOff(s) {
            return "\(ticket(s)) hat sich rentiert – du bist \(euro(WidFigures.profit(s))) im Plus, "
                + "bei \(WidFormat.trips(s.tripCount))."
        }
        if WidInsight.daysRemaining(s, now: now) <= 0 {
            return "\(ticket(s)) ist abgelaufen. Es hat sich zu \(percent) Prozent rentiert – "
                + "\(euro(WidFigures.remaining(s))) haben bis zum Break-even gefehlt."
        }
        var text = "\(ticket(s)) ist zu \(percent) Prozent amortisiert. "
            + "Es fehlen noch \(euro(WidFigures.remaining(s)))."
        if let date = WidInsight.upcomingBreakEven(s, now: now) {
            text += " Bei deinem Tempo hat es sich am \(spokenDate(date)) rentiert."
        }
        return text
    }

    /// "Pendeln erfasst. Dein Ticket ist jetzt zu 75 Prozent amortisiert."
    static func logged(_ title: String, snapshot: WidgetSnapshot?) -> String {
        guard let s = snapshot else { return "\(title) erfasst." }
        if WidInsight.isPaidOff(s) {
            return "\(title) erfasst. \(ticket(s)) hat sich rentiert – du bist \(euro(WidFigures.profit(s))) im Plus."
        }
        return "\(title) erfasst. \(ticket(s)) ist jetzt zu \(WidFormat.percentValue(s.amortizedFraction)) Prozent amortisiert."
    }

    /// "354 Euro" – whole euros read better aloud than "€ 354".
    static func euro(_ value: Double) -> String { "\(WidFormat.number(value)) Euro" }

    /// "14. Dezember"
    static func spokenDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(WidFormat.locale))
    }
}
