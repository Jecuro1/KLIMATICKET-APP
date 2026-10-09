import AppIntents
import CoreSpotlight
import Foundation
import SwiftUI
import WidgetKit

/// Kinds of the controls (Control Center, Lock Screen, Action button) – reloaded by the app and the intents.
enum WidControlKind {
    static let addTrip = "com.knitelarlberg.klimabilanz.control.addTrip"
    static let logFavorite = "com.knitelarlberg.klimabilanz.control.logFavorite"
}

/// A favourite route as seen by Siri, Shortcuts, Spotlight, controls and widgets (backed by the widget snapshot).
struct FavoriteRouteAppEntity: AppEntity, IndexedEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Lieblingsfahrt"
    static var defaultQuery = FavoriteRouteQuery()

    var id: UUID
    var title: String
    /// "St. Anton → Innsbruck · € 22,80" – nil while only the id is known (a widget button's intent).
    var subtitle: String? = nil
    var symbol: String = "star.fill"

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    init(_ favorite: WidgetSnapshot.Favorite) {
        id = favorite.id
        title = favorite.title
        symbol = favorite.modeSymbol
        let route = ([favorite.fromName] + (favorite.via ?? []) + [favorite.toName]).filter { !$0.isEmpty }.joined(separator: " → ")   // MARK: via
        subtitle = route.isEmpty ? WidFormat.euroPrecise(favorite.value) : "\(route) · \(WidFormat.euroPrecise(favorite.value))"
    }

    var displayRepresentation: DisplayRepresentation {
        let detail: LocalizedStringResource? = subtitle.map { "\($0)" }
        return DisplayRepresentation(title: "\(title)", subtitle: detail, image: .init(systemName: symbol))
    }

    /// Spotlight: "Pendeln – Lieblingsfahrt · St. Anton → Innsbruck · € 22,80".
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = title
        set.contentDescription = ["Lieblingsfahrt", subtitle].compactMap { $0 }.joined(separator: " · ")
        set.keywords = ["KlimaBilanz", "Fahrt", "Lieblingsfahrt", "KlimaTicket"]
        return set
    }
}

struct FavoriteRouteQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [FavoriteRouteAppEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FavoriteRouteAppEntity] { all() }

    /// Siri / Shortcuts by name: "Pendeln", "pendeln", "Innsbruck" (title first, then the route).
    func entities(matching string: String) async throws -> [FavoriteRouteAppEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all() }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let entities = all()
        let byTitle = entities.filter { $0.title.range(of: query, options: options) != nil }
        if !byTitle.isEmpty { return byTitle }
        return entities.filter { ($0.subtitle ?? "").range(of: query, options: options) != nil }
    }

    private func all() -> [FavoriteRouteAppEntity] {
        (WidgetSnapshot.load()?.favorites ?? []).map(FavoriteRouteAppEntity.init)
    }
}

/// Logs a favourite route for today – usable from interactive widgets, Siri, Shortcuts and Spotlight.
struct LogFavoriteTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Lieblingsfahrt erfassen"
    static var description = IntentDescription("Erfasst eine deiner Lieblingsfahrten mit Datum und Uhrzeit von jetzt.")

    @Parameter(title: "Lieblingsfahrt")
    var favorite: FavoriteRouteAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$favorite) erfassen")
    }

    init() {}

    init(favoriteID: UUID, title: String) {
        self.favorite = FavoriteRouteAppEntity(id: favoriteID, title: title)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let logged = QuickLogBridge.log(favoriteID: favorite.id)
        return .result(dialog: "\(IntentCopy.logged(favorite.title, snapshot: logged.snapshot))",
                       view: WidLoggedSnippet(title: favorite.title, favorite: logged.favorite, snapshot: logged.snapshot))
    }
}

/// "Lieblingsfahrt erfassen" control (Control Center, Lock Screen, Action button): the configured favourite is logged
/// right away, without opening the app – the control shows "Erfasst" while it runs.
struct LogFavoriteControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Lieblingsfahrt erfassen"
    static let description = IntentDescription("Erfasst die gewählte Lieblingsfahrt mit einem Tipp – ohne die App zu öffnen.")
    static let isDiscoverable = false

    @Parameter(title: "Lieblingsfahrt")
    var favorite: FavoriteRouteAppEntity?

    init() {}

    init(favorite: FavoriteRouteAppEntity?) {
        self.favorite = favorite
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let favorite else {
            return .result(dialog: "Wähle zuerst eine Lieblingsfahrt aus: Halte das Steuerelement gedrückt und tippe auf „Bearbeiten“.")
        }
        // A favourite deleted since the control was set up is not logged (the widgets' buttons vanish with it, too).
        if let snapshot = WidgetSnapshot.load(), !snapshot.favorites.contains(where: { $0.id == favorite.id }) {
            return .result(dialog: "„\(favorite.title)“ gibt es nicht mehr. Wähle für das Steuerelement eine andere Lieblingsfahrt.")
        }
        let logged = QuickLogBridge.log(favoriteID: favorite.id)
        return .result(dialog: "\(IntentCopy.logged(favorite.title, snapshot: logged.snapshot))")
    }
}

/// One place for "log this favourite now" (widget buttons, Siri, the control): queue it for the app, update the
/// widget snapshot optimistically and reload widgets + the favourite control.
enum QuickLogBridge {
    static func log(favoriteID: UUID, date: Date = Date()) -> (snapshot: WidgetSnapshot?, favorite: WidgetSnapshot.Favorite?) {
        QuickLogQueue.enqueue(favoriteID: favoriteID, date: date)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: WidControlKind.logFavorite)
        let snapshot = WidgetSnapshot.load()
        return (snapshot, snapshot?.favorites.first { $0.id == favoriteID })
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
    static var description = IntentDescription("Sagt dir, ob und wie weit sich dein KlimaTicket schon rentiert hat.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = WidgetSnapshot.load()
        return .result(dialog: "\(IntentCopy.balance(snapshot))", view: WidBalanceSnippet(snapshot: snapshot))
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
