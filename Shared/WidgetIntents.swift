import AppIntents
import Foundation
import KlimaCore
import WidgetKit

// Configuration of the live widgets and the intents of the new controls (docs/WIDGETS.md). Shared by the app and the
// widget extension: the widget only reads WidgetCache, the intents write only the two live-follow keys.

/// "Nächste Verbindung": which favourite route the widget shows (the favourites come from the widget snapshot).
struct NextConnectionConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Nächste Verbindung"
    static var description = IntentDescription("Zeigt die nächsten Verbindungen deiner Lieblingsfahrt – mit Gleis und Verspätung.")

    @Parameter(title: "Lieblingsfahrt")
    var favorite: FavoriteRouteAppEntity?

    init() {}

    init(favorite: FavoriteRouteAppEntity?) {
        self.favorite = favorite
    }
}

/// A station the Abfahrten widget can show. The choices are the stations the app wrote to `WidgetCache.stations`: the home
/// station and the stations of the favourites.
struct StationAppEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static var defaultQuery = StationAppQuery()

    var id: String
    var name: String
    var isHome: Bool

    init(id: String, name: String, isHome: Bool) {
        self.id = id
        self.name = name
        self.isHome = isHome
    }

    init(_ station: WidgetStation) {
        self.init(id: station.id, name: station.name, isHome: station.isHome)
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? = isHome ? "Heimat-Station" : nil
        return DisplayRepresentation(title: "\(name)", subtitle: subtitle, image: .init(systemName: "tram.fill"))
    }
}

struct StationAppQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationAppEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StationAppEntity] { all() }

    func entities(matching string: String) async throws -> [StationAppEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all() }
        return all().filter { $0.name.localizedStandardContains(query) }
    }

    private func all() -> [StationAppEntity] {
        (WidgetCache.stations?.stations ?? []).map(StationAppEntity.init)
    }
}

/// "Abfahrten": the station to show. Without a choice the home station is shown (see `WidgetStation.isHome`).
struct DeparturesConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Abfahrten"
    static var description = IntentDescription("Zeigt die nächsten Abfahrten einer Station – Standard ist deine Heimat-Station.")

    @Parameter(title: "Station")
    var station: StationAppEntity?

    init() {}

    init(station: StationAppEntity?) {
        self.station = station
    }
}

/// Live verfolgen (control): turns the followed train on or off. Turning it on needs a train, so the app opens the Zug-Radar
/// for the choice. The app runs the request and mirrors the state back into `WidgetCache`.
struct LiveFollowSetIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Live verfolgen"
    static var description = IntentDescription("Verfolgt einen Zug live – die App öffnet dafür den Zug-Radar.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Live verfolgen")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        WidgetCache.requestLiveFollow(value)
        WidgetCache.setLiveFollowActive(value)
        return .result()
    }
}
