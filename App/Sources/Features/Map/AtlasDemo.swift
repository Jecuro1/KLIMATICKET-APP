import SwiftUI
import SwiftData
import KlimaCore

/// Weekend excursions that turn the Arlberg commuter's demo year into a map worth looking at:
/// a Vienna weekend, a Salzkammergut loop via Linz, Lake Constance up to the Gemeinschaftsbahnhof Lindau-Reutin,
/// Kärnten and Kufstein. Burgenland stays open on purpose (8 of 9). Fares come from the regular estimator.
@MainActor
enum AtlasDemoData {
    struct Excursion {
        let from: String
        let to: String
        let mode: TransportMode
        let day: Int
        let hour: Int
        let roundTrip: Bool
        let states: [String]
    }

    static let excursions: [Excursion] = [
        Excursion(from: "at:47:1187", to: "at:49:1349", mode: .train, day: 40, hour: 7, roundTrip: false, states: ["T", "S", "OÖ", "NÖ", "W"]),
        Excursion(from: "wl:60201349", to: "wl:60201040", mode: .metro, day: 40, hour: 14, roundTrip: true, states: ["W"]),
        Excursion(from: "at:49:1468", to: "at:43:4848", mode: .train, day: 41, hour: 10, roundTrip: true, states: ["W", "NÖ"]),
        Excursion(from: "at:49:1349", to: "at:47:1187", mode: .train, day: 42, hour: 16, roundTrip: false, states: ["W", "NÖ", "OÖ", "S", "T"]),
        Excursion(from: "at:47:1187", to: "at:45:50002", mode: .train, day: 75, hour: 8, roundTrip: false, states: ["T", "S"]),
        Excursion(from: "at:45:50002", to: "at:44:41164", mode: .train, day: 75, hour: 15, roundTrip: false, states: ["S", "OÖ"]),
        Excursion(from: "at:44:41164", to: "at:47:1187", mode: .train, day: 76, hour: 17, roundTrip: false, states: ["OÖ", "S", "T"]),
        Excursion(from: "at:48:452", to: "de:09776:1592", mode: .train, day: 101, hour: 11, roundTrip: true, states: ["V", "X"]),
        Excursion(from: "at:42:3642", to: "at:42:3654", mode: .train, day: 131, hour: 10, roundTrip: true, states: ["K"]),
        Excursion(from: "at:47:1187", to: "at:47:2184", mode: .train, day: 150, hour: 9, roundTrip: true, states: ["T"]),
    ]

    /// Adds the excursions to the active demo ticket year (no-op without a ticket or when already present).
    static func seedExcursions(into context: ModelContext, app: AppState, now: Date = Date()) {
        let tickets = (try? context.fetch(FetchDescriptor<TicketEntity>())) ?? []
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return }
        let existing = (try? context.fetch(FetchDescriptor<TripEntity>())) ?? []
        guard !existing.contains(where: { $0.note == noteMarker }) else { return }
        let cal = Calendar.vienna
        for item in excursions {
            guard let a = app.stations.station(id: item.from), let b = app.stations.station(id: item.to),
                  let day = cal.date(byAdding: .day, value: item.day, to: cal.startOfDay(for: ticket.startDate)),
                  let date = cal.date(bySettingHour: item.hour, minute: 12, second: 0, of: day),
                  date <= now else { continue }
            let estimate = app.estimator.estimate(from: a, to: b, mode: item.mode, date: date)
            let trip = TripEntity(date: date, fromName: a.name, toName: b.name, fromStationID: a.id, toStationID: b.id,
                                  mode: item.mode, distanceKm: estimate.distanceKm, fareEUR: estimate.fareEUR,
                                  isRoundTrip: item.roundTrip, states: item.states, note: noteMarker)
            trip.category = .leisure
            context.insert(trip)
        }
        try? context.save()
    }

    static let noteMarker = "Ausflug"
}

/// CI screenshot scenes of the map ("map", "mapRoute", "mapRouteList", "mapDetails", "mapSatellite", "mapPreview")
/// with the excursion demo year.
struct AtlasScreenshotScene: View {
    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                switch screen {
                case "mapPreview":
                    AtlasPreviewShowcase()
                case "mapRoute":
                    NavigationStack { AtlasView(launchFocus: .topRoute) }
                case "mapRouteList":
                    NavigationStack { AtlasView(launchFocus: .topRouteExpanded) }
                case "mapDetails":
                    NavigationStack { AtlasView(launchFocus: .details) }
                default:
                    NavigationStack { AtlasView() }
                }
            } else {
                Color.clear
            }
        }
        .task {
            guard !isReady else { return }
            // The map look is remembered per device; screenshots set it explicitly.
            let look: AtlasMapLook = screen == "mapSatellite" ? .satellite : .standard
            UserDefaults.standard.set(look.rawValue, forKey: AtlasView.lookKey)
            AtlasDemoData.seedExcursions(into: context, app: app)
            isReady = true
        }
    }
}
