import AppIntents
import SwiftUI
import KlimaCore

// Siri and Shortcuts for the Fahrplan: „Nächste Verbindung nach …“ answers with the next connection of the live timetable
// (docs/PLANNER.md §Siri). The intent is the app's own: the consent, the switch and the kill switch of the live layer
// decide, nothing is requested without them.

/// The running app's state for the planner intents, set at the end of `AppState.init`. Nil only before the app state exists.
@MainActor
enum PlannerIntentHost {
    static weak var app: AppState?
}

/// A station as an intent parameter: a stop of the offline station index, with the same id the planner uses.
struct PlannerPlaceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Haltestelle")
    static let defaultQuery = PlannerPlaceQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlannerPlaceQuery: EntityStringQuery {
    @MainActor
    func entities(matching string: String) async throws -> [PlannerPlaceEntity] {
        guard let index = PlannerIntentHost.app?.stations else { return [] }
        return index.search(string, limit: 8).map { PlannerPlaceEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [PlannerPlaceEntity] {
        guard let index = PlannerIntentHost.app?.stations else { return [] }
        return identifiers.compactMap { id in index.station(id: id).map { PlannerPlaceEntity(id: $0.id, name: $0.name) } }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlannerPlaceEntity] {
        guard let app = PlannerIntentHost.app,
              let home = app.settings.homeStationID.flatMap({ app.stations.station(id: $0) }) else { return [] }
        return [PlannerPlaceEntity(id: home.id, name: home.name)]
    }
}

/// What the planner intent answers: a short dialog for Siri and the lines of the snippet.
struct PlannerIntentAnswer: Equatable {
    var title: String
    var lines: [String]
    var dialog: String
}

@MainActor
enum PlannerIntentLookup {
    /// The first connection from `fromID` (the home station when nil) to `toID`, departing now. Every failure is an answer too.
    static func answer(fromID: String?, toID: String) async -> PlannerIntentAnswer {
        guard let app = PlannerIntentHost.app else {
            return PlannerIntentAnswer(title: "KlimaBilanz", lines: [],
                                       dialog: "KlimaBilanz ist noch nicht bereit. Öffne die App einmal und versuche es erneut.")
        }
        let stations = app.stations
        guard let destination = stations.station(id: toID) else {
            return PlannerIntentAnswer(title: "Ziel", lines: [], dialog: "Diese Haltestelle kenne ich nicht.")
        }
        guard let origin = fromID.flatMap({ stations.station(id: $0) }) ?? app.settings.homeStationID.flatMap({ stations.station(id: $0) }) else {
            return PlannerIntentAnswer(title: "Von wo?", lines: [],
                                       dialog: "Nenne eine Abfahrtshaltestelle oder lege deine Startstation in KlimaBilanz fest.")
        }
        let route = "\(DisplayNames.name(origin.name)) → \(DisplayNames.name(destination.name))"
        // Nil unless live data is on: the consent, the switch and the kill switch are checked there.
        guard let timetable = app.live.timetable else {
            return PlannerIntentAnswer(title: route, lines: [],
                                       dialog: "Die Live-Daten sind in KlimaBilanz nicht eingeschaltet. Du findest sie unter Einstellungen, Live-Daten.")
        }
        do {
            let from = try await app.planner.resolve(.station(origin))
            let to = try await app.planner.resolve(.station(destination))
            let query = JourneyQuery(origin: from, destination: to, date: Date(), products: .all, results: 3, includeStopovers: false)
            let page = try await timetable.journeys(query)
            guard let journey = page.journeys.first else {
                return PlannerIntentAnswer(title: route, lines: [], dialog: "Ich finde gerade keine Verbindung.")
            }
            let summary = JourneyPresentation.summary(journey, now: Date())
            let departure = summary.plannedDeparture.map(Format.time) ?? ""
            let arrival = summary.plannedArrival.map(Format.time) ?? ""
            var lines = ["Ab \(departure) Uhr\(summary.departure.text.map { " · \($0)" } ?? "")", "An \(arrival) Uhr", summary.changesText]
            if !summary.lineSummary.isEmpty { lines.append(summary.lineSummary) }
            return PlannerIntentAnswer(title: route, lines: lines,
                                       dialog: "Die nächste Verbindung fährt um \(departure) Uhr, \(summary.changesText). Preise und Gültigkeit prüfst du in KlimaBilanz.")
        } catch {
            return PlannerIntentAnswer(title: route, lines: [],
                                       dialog: "Die Verbindung ist gerade nicht erreichbar. Versuch es später noch einmal.")
        }
    }
}

/// „Nächste Verbindung nach …“ for Siri, Shortcuts and the Action button.
struct PlanConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächste Verbindung"
    static let description = IntentDescription(
        "Nennt die nächste Verbindung zwischen zwei Haltestellen. Braucht die Live-Daten, die du in KlimaBilanz eingeschaltet hast.")
    static let openAppWhenRun = false

    @Parameter(title: "Von", description: "Abfahrtshaltestelle. Ohne Angabe: deine Startstation.")
    var from: PlannerPlaceEntity?

    @Parameter(title: "Nach")
    var to: PlannerPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Nächste Verbindung von \(\.$from) nach \(\.$to)")
    }

    init() {}

    init(from: PlannerPlaceEntity?, to: PlannerPlaceEntity) {
        self.from = from
        self.to = to
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let answer = await PlannerIntentLookup.answer(fromID: from?.id, toID: to.id)
        return .result(dialog: "\(answer.dialog)", view: PlannerIntentSnippet(answer: answer))
    }
}

/// The snippet under the Siri answer: the route, the times and the changes of the next connection.
struct PlannerIntentSnippet: View {
    let answer: PlannerIntentAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer.title).font(.headline)
            ForEach(answer.lines, id: \.self) { line in
                Text(line).font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
