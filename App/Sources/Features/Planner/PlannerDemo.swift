import SwiftUI
import Foundation
import KlimaCore

// Deterministic offline stand-ins for CI screenshots and previews (`-KBDemo`): the network is never touched.
// Times are relative to „now“, so a screenshot always shows a connection leaving in 18 minutes.

// MARK: - Demo places

enum DemoPlaces {
    struct Spot { let extId: String; let name: String; let lat: Double; let lon: Double; let products: ProductMask }

    static let all: [Spot] = [
        Spot(extId: "8100108", name: "Innsbruck Hbf", lat: 47.2633, lon: 11.4010, products: .all),
        Spot(extId: "8100013", name: "Ötztal Bahnhof", lat: 47.2406, lon: 10.8728, products: .rail),
        Spot(extId: "8100035", name: "Landeck-Zams Bahnhof", lat: 47.1396, lon: 10.5667, products: .rail),
        Spot(extId: "8100002", name: "St.Anton am Arlberg Bahnhof", lat: 47.1285, lon: 10.2685, products: .all),
        Spot(extId: "460631", name: "St.Anton am Arlberg Bahnhof (Vorplatz)", lat: 47.1288, lon: 10.2681, products: .bus),
        Spot(extId: "8100003", name: "Langen am Arlberg Bahnhof", lat: 47.1384, lon: 10.1076, products: .rail),
        Spot(extId: "460211", name: "Lech Rüfiplatz", lat: 47.2079, lon: 10.1428, products: .bus),
        Spot(extId: "8100051", name: "Hall in Tirol Bahnhof", lat: 47.2820, lon: 11.5090, products: .rail),
        Spot(extId: "8100040", name: "Bludenz Bahnhof", lat: 47.1536, lon: 9.8228, products: .rail),
        Spot(extId: "8100010", name: "Feldkirch Bahnhof", lat: 47.2385, lon: 9.5985, products: .rail),
        Spot(extId: "8100020", name: "Bregenz Bahnhof", lat: 47.5116, lon: 9.7436, products: .rail),
        Spot(extId: "1290401", name: "Wien Hauptbahnhof", lat: 48.1852, lon: 16.3764, products: .all),
        Spot(extId: "8100030", name: "Salzburg Hauptbahnhof", lat: 47.8130, lon: 13.0456, products: .all),
    ]

    static func location(_ spot: Spot) -> Location {
        Location(lid: "A=1@L=\(spot.extId)@", kind: .station, extId: spot.extId, name: spot.name,
                 coordinate: GeoPoint(latitude: spot.lat, longitude: spot.lon), products: spot.products)
    }

    static func named(_ part: String) -> Location? {
        all.first { $0.name.localizedCaseInsensitiveContains(part) }.map(location)
    }

    static var innsbruck: Location { named("Innsbruck Hbf")! }
}

// MARK: - Demo timetable

struct DemoTimetableService: TimetableService {
    var now: @Sendable () -> Date = { Date() }

    func locations(_ query: String, types: LocationTypes, maxResults: Int) async throws -> [Location] {
        let q = StationIndex.normalize(query)
        guard !q.isEmpty else { return [] }
        var hits = DemoPlaces.all.filter { StationIndex.normalize($0.name).contains(q) }.map(DemoPlaces.location)
        if q.count >= 3, hits.isEmpty {
            hits = [Location(lid: "A=2@O=\(query)@", kind: .address, name: query.capitalized + "straße 1, Innsbruck",
                             coordinate: GeoPoint(latitude: 47.2692, longitude: 11.4041))]
        }
        return Array(hits.prefix(maxResults))
    }

    func nearby(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) async throws -> [Location] {
        var here = DemoPlaces.innsbruck
        here.distanceMeters = 120
        return [here]
    }

    func journeys(_ query: JourneyQuery) async throws -> JourneyPage {
        let list = DemoJourneys.journeys(for: query, now: now())
        return JourneyPage(journeys: list, earlierContext: query.pageContext == nil ? "demo-earlier" : nil,
                           laterContext: "demo-later", realtimeUpdatedAt: now())
    }

    func journeys(batch queries: [JourneyQuery]) async throws -> [Result<JourneyPage, LiveError>] {
        var out: [Result<JourneyPage, LiveError>] = []
        for query in queries { out.append(.success(try await journeys(query))) }
        return out
    }

    func refresh(_ refreshToken: String, includeStopovers: Bool, includePolyline: Bool) async throws -> Journey {
        throw LiveError.noConnection
    }

    func refresh(batch refreshTokens: [String]) async throws -> [Result<Journey, LiveError>] {
        refreshTokens.map { _ in .failure(.noConnection) }
    }

    func trip(_ tripID: String, includePolyline: Bool) async throws -> TripDetails {
        DemoJourneys.trip(tripID, now: now(), includePolyline: includePolyline)
    }

    func board(_ query: BoardQuery) async throws -> Board {
        DemoBoards.board(query, now: now())
    }

    func remarks(_ query: RemarksQuery) async throws -> [Remark] { [] }
}

// MARK: - Demo prices

struct DemoPriceProvider: LivePriceProvider {
    func livePrice(_ request: PriceRequest) async throws -> PriceQuote {
        let from = request.from.name.lowercased(), to = request.to.name.lowercased()
        let pair = from + "|" + to
        let now = Date()
        if pair.contains("innsbruck") && pair.contains("lech") {
            return PriceQuote(amountEUR: 29.70, source: .liveOebb, provider: "ÖBB", productName: "Standard-Ticket",
                              travelClass: request.travelClass, travelDate: request.departure, fetchedAt: now, leadTime: .travelDay,
                              explanation: "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt \(Self.clock(now))",
                              alternatives: [PriceAlternative(source: .table, amountEUR: 29.70, label: "Tarif-Tabelle")])
        }
        if pair.contains("innsbruck") && pair.contains("anton") {
            return PriceQuote(amountEUR: 22.00, source: .liveVerbund, provider: "VVT", productName: "VVT Einzelticket",
                              travelClass: request.travelClass, travelDate: request.departure, fetchedAt: now, leadTime: .travelDay,
                              explanation: "Verbund-Einzelticket · VVT 14 Zonen · St. Anton – Innsbruck",
                              alternatives: [PriceAlternative(source: .table, amountEUR: 23.50, label: "Tarif-Tabelle")])
        }
        throw LiveError.noPrice("Demo")
    }

    private static func clock(_ date: Date) -> String { Format.time(date) }
}

// MARK: - Journeys

enum DemoJourneys {
    static func minute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    static func line(_ name: String, category: String, cls: Int, mode: TransportMode, number: String?, train: String?,
                     long: String? = nil, admin: String = "81____") -> Line {
        Line(name: name, fullName: name.replacingOccurrences(of: " ", with: ""), category: category, categoryShort: category,
             categoryLong: long, lineNumber: number, trainNumber: train, lineId: "demo:\(name)", admin: admin,
             operatorName: "Nahreisezug", productClass: cls, mode: mode)
    }

    static let rjx = { (n: String) in line("RJX \(n)", category: "RJX", cls: 1, mode: .train, number: nil, train: n, long: "railjet xpress") }
    static func bus(_ n: String) -> Line { line("Bus \(n)", category: "Bus", cls: 64, mode: .bus, number: n, train: n, long: "Postbus", admin: "40____") }

    static func platform(_ text: String?, kind: Platform.Kind = .track) -> Platform? { text.map { Platform(text: $0, kind: kind) } }

    /// A stop event: planned time, an optional delay in minutes (realtime), platform.
    static func event(_ planned: Date, delay: Int? = 0, platform: String? = nil, kind: Platform.Kind = .track, changedTo: String? = nil,
                      cancelled: Bool = false) -> StopEvent {
        StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval(Double($0) * 60) },
                  plannedPlatform: Self.platform(platform, kind: kind), realtimePlatform: Self.platform(changedTo ?? platform, kind: kind),
                  isCancelled: cancelled, prognosis: delay == nil ? nil : .prognosed, platformChangeFlag: changedTo != nil && changedTo != platform)
    }

    static func stopover(_ loc: Location, arrival: Date?, departure: Date?, index: Int, delay: Int? = 0, platform: String? = nil) -> Stopover {
        Stopover(location: loc, arrival: arrival.map { event($0, delay: delay, platform: platform) },
                 departure: departure.map { event($0, delay: delay, platform: platform) }, index: index)
    }

    static func attributes(_ codes: [String]) -> [Remark] {
        codes.map { Remark(kind: .attribute, code: $0, text: $0) }
    }

    static func stopLocations(_ names: [String]) -> [Location] { names.compactMap(DemoPlaces.named) }

    // MARK: Scripted: Innsbruck Hbf → Lech Rüfiplatz (RJX → Bus), the screenshot hero

    static func innsbruckLech(departure t0: Date, delay: Int?, trainNumber: String, busNumber: String, notice: Remark? = nil,
                              busDelay: Int? = nil) -> Journey {
        let ibk = DemoPlaces.innsbruck, oetz = DemoPlaces.named("Ötztal")!, landeck = DemoPlaces.named("Landeck")!
        let anton = DemoPlaces.named("St.Anton am Arlberg Bahnhof")!, antonVorplatz = DemoPlaces.named("Vorplatz")!, lech = DemoPlaces.named("Lech")!
        let d = delay
        let arrive = t0.addingTimeInterval(69 * 60), busDep = t0.addingTimeInterval(84 * 60), end = t0.addingTimeInterval(113 * 60)
        let rjxLine = rjx(trainNumber)
        let rideRemarks = attributes(["WV", "BR", "HD", "KN", "RO", "FK"]) + (notice.map { [$0] } ?? [])
        let ride = Leg(id: "demo-ride-\(trainNumber)", kind: .ride, origin: ibk, destination: anton,
                       departure: event(t0, delay: d, platform: "3"), arrival: event(arrive, delay: d, platform: "2"),
                       line: rjxLine, direction: "Feldkirch", tripID: "demo|\(trainNumber)",
                       stopovers: [stopover(ibk, arrival: nil, departure: t0, index: 0, delay: d, platform: "3"),
                                   stopover(oetz, arrival: t0.addingTimeInterval(25 * 60), departure: t0.addingTimeInterval(26 * 60), index: 1, delay: d),
                                   stopover(landeck, arrival: t0.addingTimeInterval(47 * 60), departure: t0.addingTimeInterval(48 * 60), index: 2, delay: d),
                                   stopover(anton, arrival: arrive, departure: nil, index: 3, delay: d, platform: "2")],
                       remarks: rideRemarks)
        let walk = Leg(id: "demo-walk-\(trainNumber)", kind: .walk, origin: anton, destination: antonVorplatz,
                       departure: event(arrive, delay: d), arrival: event(arrive.addingTimeInterval(3 * 60), delay: d),
                       walkDistanceMeters: 42, walkDurationSeconds: 180)
        let busLine = bus(busNumber)
        let busLeg = Leg(id: "demo-bus-\(busNumber)", kind: .ride, origin: antonVorplatz, destination: lech,
                         departure: event(busDep, delay: busDelay, platform: "B", kind: .stand), arrival: event(end, delay: busDelay),
                         line: busLine, direction: "Lech Schlosskopf", tripID: "demo|bus\(busNumber)|\(trainNumber)",
                         stopovers: [stopover(antonVorplatz, arrival: nil, departure: busDep, index: 0, delay: busDelay, platform: "B"),
                                     stopover(lech, arrival: end, departure: nil, index: 1, delay: busDelay)])
        var j = Journey(legs: [ride, walk, busLeg], durationSeconds: 113 * 60, changes: 1,
                        refreshToken: "demo-token-\(trainNumber)", serviceDays: "täglich", realtimeUpdatedAt: Date())
        j.shopURL = URL(string: "https://shop.oebbtickets.at/de/ticket")
        return j
    }

    // MARK: Scripted: St. Anton → Innsbruck Hbf (direct RJX)

    static func antonInnsbruck(departure t0: Date, delay: Int?, trainNumber: String) -> Journey {
        let ibk = DemoPlaces.innsbruck, oetz = DemoPlaces.named("Ötztal")!, landeck = DemoPlaces.named("Landeck")!
        let anton = DemoPlaces.named("St.Anton am Arlberg Bahnhof")!
        let end = t0.addingTimeInterval(69 * 60)
        let ride = Leg(id: "demo-ride2-\(trainNumber)", kind: .ride, origin: anton, destination: ibk,
                       departure: event(t0, delay: delay, platform: "2"), arrival: event(end, delay: delay, platform: "5"),
                       line: rjx(trainNumber), direction: "Wien Hbf", tripID: "demo|\(trainNumber)",
                       stopovers: [stopover(anton, arrival: nil, departure: t0, index: 0, delay: delay, platform: "2"),
                                   stopover(landeck, arrival: t0.addingTimeInterval(20 * 60), departure: t0.addingTimeInterval(21 * 60), index: 1, delay: delay),
                                   stopover(oetz, arrival: t0.addingTimeInterval(42 * 60), departure: t0.addingTimeInterval(43 * 60), index: 2, delay: delay),
                                   stopover(ibk, arrival: end, departure: nil, index: 3, delay: delay, platform: "5")],
                       remarks: attributes(["WV", "BR", "RO", "FK"]))
        return Journey(legs: [ride], durationSeconds: 69 * 60, changes: 0, refreshToken: "demo-token-\(trainNumber)", serviceDays: "täglich")
    }

    // MARK: Generic: any two places

    static func generic(from: Location, to: Location, via: [ViaStop], departure t0: Date, delay: Int?, index: Int) -> Journey {
        let km = (from.coordinate ?? DemoPlaces.innsbruck.coordinate!).distanceKm(to: to.coordinate ?? DemoPlaces.innsbruck.coordinate!)
        let points = [from] + via.map(\.location) + [to]
        let totalMinutes = max(12, Int(km * 1.25 + 8))
        var legs: [Leg] = []
        var cursor = t0
        for pair in zip(points, points.dropFirst()).enumerated() {
            let (i, (a, b)) = pair
            let share = Double(totalMinutes) / Double(points.count - 1)
            let end = cursor.addingTimeInterval(share * 60)
            let train = String(540 + index * 3 + i)
            legs.append(Leg(id: "demo-g\(index)-\(i)", kind: .ride, origin: a, destination: b,
                            departure: event(cursor, delay: delay, platform: "\(2 + i)"), arrival: event(end, delay: delay, platform: "\(4 + i)"),
                            line: line("REX \(train)", category: "REX", cls: 16, mode: .train, number: "51", train: train),
                            direction: DisplayNames.name(to.name), tripID: "demo|g\(index)|\(i)",
                            stopovers: [stopover(a, arrival: nil, departure: cursor, index: 0, delay: delay, platform: "\(2 + i)"),
                                        stopover(b, arrival: end, departure: nil, index: 1, delay: delay, platform: "\(4 + i)")]))
            cursor = end.addingTimeInterval(i < points.count - 2 ? 12 * 60 : 0)
        }
        let duration = Int(cursor.timeIntervalSince(t0))
        return Journey(legs: legs, durationSeconds: duration, changes: max(0, points.count - 2),
                       refreshToken: "demo-token-g\(index)", serviceDays: "täglich")
    }

    // MARK: Entry

    static func journeys(for query: JourneyQuery, now: Date) -> [Journey] {
        let start = minute(now).addingTimeInterval(18 * 60)
        let from = query.origin.name.lowercased(), to = query.destination.name.lowercased()
        let pair = from + "|" + to
        var out: [Journey] = []
        let shift: TimeInterval = query.pageContext == "demo-earlier" ? -3 * 3600 : (query.pageContext == "demo-later" ? 3 * 3600 : 0)
        let base = query.pageContext == nil && query.date.timeIntervalSince(now) > 900 ? minute(query.date) : start
        if pair.contains("innsbruck") && pair.contains("lech") && query.via.isEmpty {
            let crowd = Remark(kind: .realtime, code: "ZG", title: "Andere Zuggarnitur – weniger Sitzplätze 1. Kl.", text: "Andere Zuggarnitur – weniger Sitzplätze 1. Kl.", priority: 60)
            out = [innsbruckLech(departure: base, delay: 0, trainNumber: "19910", busNumber: "760"),
                   innsbruckLech(departure: base.addingTimeInterval(3600), delay: 0, trainNumber: "19912", busNumber: "750", notice: crowd),
                   innsbruckLech(departure: base.addingTimeInterval(7200), delay: 4, trainNumber: "19914", busNumber: "760", busDelay: 4)]
        } else if pair.contains("anton") && pair.contains("innsbruck") && query.via.isEmpty {
            out = [antonInnsbruck(departure: base, delay: 0, trainNumber: "19911"),
                   antonInnsbruck(departure: base.addingTimeInterval(3600), delay: 2, trainNumber: "19913"),
                   antonInnsbruck(departure: base.addingTimeInterval(7200), delay: 0, trainNumber: "19915")]
        } else {
            out = (0..<4).map { generic(from: query.origin, to: query.destination, via: query.via,
                                         departure: base.addingTimeInterval(Double($0) * 3600 + Double($0 % 2) * 900),
                                         delay: $0 == 2 ? 4 : 0, index: $0) }
        }
        if shift != 0 { out = out.map { shifted($0, by: shift) } }
        return out
    }

    static func shifted(_ journey: Journey, by seconds: TimeInterval) -> Journey {
        func move(_ e: StopEvent) -> StopEvent {
            var e = e
            e.planned = e.planned?.addingTimeInterval(seconds)
            e.realtime = e.realtime?.addingTimeInterval(seconds)
            return e
        }
        var j = journey
        j.legs = journey.legs.map { leg in
            var l = leg
            l.departure = move(leg.departure)
            l.arrival = move(leg.arrival)
            l.id += "s"
            l.stopovers = leg.stopovers.map { (stop: Stopover) -> Stopover in
                var s = stop
                s.arrival = s.arrival.map(move)
                s.departure = s.departure.map(move)
                return s
            }
            return l
        }
        j.refreshToken = journey.refreshToken.map { $0 + "s" }
        return j
    }

    // MARK: Trip

    static func trip(_ tripID: String, now: Date, includePolyline: Bool) -> TripDetails {
        let base = minute(now).addingTimeInterval(18 * 60)
        if tripID.hasPrefix("demo|g") { return TripDetails(tripID: tripID, realtimeUpdatedAt: now) }
        let journey = innsbruckLech(departure: base, delay: 0, trainNumber: "19910", busNumber: "760")
        let leg = tripID.contains("bus") ? journey.legs[2] : journey.legs[0]
        let points = leg.stopovers.compactMap(\.location.coordinate)
        return TripDetails(tripID: tripID, line: leg.line, direction: leg.direction, stopovers: leg.stopovers,
                           polyline: includePolyline ? curve(points) : nil, remarks: leg.remarks, realtimeUpdatedAt: now)
    }

    /// A gently winding line through the stops (stand-in for the HAFAS polyline).
    static func curve(_ points: [GeoPoint]) -> [GeoPoint] {
        guard points.count >= 2 else { return points }
        var out: [GeoPoint] = []
        for (index, pair) in zip(points, points.dropFirst()).enumerated() {
            let (a, b) = pair
            let steps = 14
            let dx = b.longitude - a.longitude, dy = b.latitude - a.latitude
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                let wobble = sin(t * .pi * 2 + Double(index)) * 0.004 * (index % 2 == 0 ? 1 : -1)
                out.append(GeoPoint(latitude: a.latitude + dy * t - dx * wobble, longitude: a.longitude + dx * t + dy * wobble))
            }
        }
        out.append(points[points.count - 1])
        return out
    }
}

// MARK: - Boards

enum DemoBoards {
    struct Entry {
        var minutes: Int
        var delay: Int?
        var line: Line
        var direction: String
        var platform: String
        var kind: Platform.Kind
        var changedTo: String? = nil
        var cancelled = false
        var notice: String? = nil
    }

    static func board(_ query: BoardQuery, now: Date) -> Board {
        let base = DemoJourneys.minute(now)
        let tram = { (n: String) in DemoJourneys.line("Tram \(n)", category: "Tram", cls: 512, mode: .tram, number: n, train: nil, admin: "45____") }
        let sbahn = { (n: String) in DemoJourneys.line("S \(n)", category: "S", cls: 32, mode: .sBahn, number: n, train: "50\(n)", admin: "81____") }
        let rj = DemoJourneys.line("RJ 83", category: "RJ", cls: 1, mode: .train, number: nil, train: "83", long: "railjet")
        let busF = DemoJourneys.line("Bus F", category: "Bus", cls: 64, mode: .bus, number: "F", train: "F", admin: "45____")
        let rex = DemoJourneys.line("REX 1628", category: "REX", cls: 16, mode: .train, number: nil, train: "1628")
        let cjx = DemoJourneys.line("CJX 1", category: "CJX", cls: 16, mode: .train, number: "1", train: "1", admin: "81____")
        let t3 = tram("3")
        let entries: [Entry] = [
            Entry(minutes: 2, delay: 4, line: tram("5"), direction: "Rum Bahnhst", platform: "F", kind: .stand),
            Entry(minutes: 9, delay: 0, line: sbahn("4"), direction: "Telfs-Pfaffenhofen", platform: "1A-B", kind: .track),
            Entry(minutes: 10, delay: 0, line: rj, direction: "Bologna Centrale", platform: "5", kind: .track, notice: "Starker Reisetag · nur mit Reservierung"),
            Entry(minutes: 14, delay: 2, line: busF, direction: "Flughafen", platform: "G", kind: .stand),
            Entry(minutes: 15, delay: 0, line: sbahn("4"), direction: "Jenbach", platform: "2", kind: .track, changedTo: "3", notice: "Gleiswechsel · heute Gleis 3"),
            Entry(minutes: 18, delay: nil, line: rex, direction: "Brennero/Brenner", platform: "2", kind: .track, cancelled: true, notice: "Ersatz: Bus ab Steig A · 11:45"),
            Entry(minutes: 22, delay: 0, line: cjx, direction: "Kufstein", platform: "5", kind: .track),
            Entry(minutes: 22, delay: 0, line: t3, direction: "Anichstraße/Rathausgalerien", platform: "G", kind: .stand),
        ]
        let list = entries.map { e -> BoardEntry in
            let planned = base.addingTimeInterval(Double(e.minutes) * 60)
            var ev = DemoJourneys.event(planned, delay: e.delay, platform: e.platform, kind: e.kind, changedTo: e.changedTo, cancelled: e.cancelled)
            ev.isCancelled = e.cancelled
            var remarks: [Remark] = []
            if let notice = e.notice {
                let crowd = notice.hasPrefix("Starker")
                remarks.append(Remark(kind: crowd ? .realtime : .disruption, title: notice, text: notice, priority: crowd ? 70 : 40))
            }
            var stop = query.station
            stop.name = query.station.name
            return BoardEntry(tripID: "demo|board|\(e.line.name)|\(e.minutes)", line: e.line, direction: e.direction, stop: stop,
                              event: ev, terminusOrOrigin: Location(lid: "A=1@L=\(e.direction)@", name: e.direction), remarks: remarks)
        }
        return Board(kind: query.kind, entries: list, realtimeUpdatedAt: now)
    }
}

// MARK: - Screenshot scenes

/// CI screenshots of the Fahrplan (`-KBScreenshot planner | plannerResults | plannerVia | connection | connectionPartial |
/// departures | plannerConsent | plannerStates | plannerOptions`): the real tab with the demo timetable – no network.
struct PlannerScreenshotScene: View {
    static let screens: Set<String> = ["planner", "plannerResults", "plannerVia", "connection", "departures", "plannerConsent",
                                       "plannerStates", "plannerOptions", "plannerSearch"]

    let screen: String
    @Environment(AppState.self) private var app

    init(screen: String) { self.screen = screen }

    var body: some View {
        switch screen {
        case "plannerConsent":
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Kicker(text: "Freitag, 9. Oktober")
                    Text("Fahrplan").font(Theme.Typography.heroTitle)
                    LiveConsentCard(style: .card)
                    LiveConsentCard(style: .inline)
                }
                .padding(Theme.Spacing.screen)
            }
            .ambientBackground()
        case "plannerStates":
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    PlannerOfflinePill(since: Date().addingTimeInterval(-1100))
                    PlannerErrorBanner(failure: .unreachable) {}
                    PlannerNoConnectionView(isKlimaTicketOnly: true, onTomorrow: {}, onWiden: {})
                    PlannerUnavailableView(reason: .declined) {}
                    PlannerSkeletonList(count: 1)
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground()
        default:
            MainTabView()
                .task { await prepare() }
        }
    }

    @MainActor
    private func prepare() async {
        let model = app.planner
        app.selectedTab = .planner
        let stations = app.stations
        let innsbruck = stations.station(named: "Innsbruck Hbf")
        let anton = stations.station(named: "St. Anton am Arlberg")
        switch screen {
        case "planner":
            if let innsbruck, let anton {
                var relations = [(from: innsbruck, to: anton)]
                if let hall = stations.station(named: "Hall in Tirol") { relations.append((from: innsbruck, to: hall)) }
                model.screenshotRoutes = relations
            }
            await model.loadNearby()
            await model.refreshHereIfAuthorized()
        case "plannerOptions":
            try? await Task.sleep(for: .milliseconds(500))
            model.showsOptions = true
        case "departures":
            model.mode = .departures
            if let innsbruck { model.boardStation = .station(innsbruck) }
            await model.loadBoard()
        case "plannerResults", "connection", "plannerVia":
            if let innsbruck { model.origin = .station(innsbruck) }
            if screen == "plannerVia" {
                if let bregenz = stations.station(named: "Bregenz") { model.destination = .station(bregenz) }
                model.vias = ["Landeck-Zams", "Feldkirch"].compactMap { stations.station(named: $0).map { .station($0) } }
            } else {
                model.destination = .live(DemoPlaces.named("Lech")!)
            }
            model.startSearch()
            for _ in 0..<40 where model.phase != .loaded { try? await Task.sleep(for: .milliseconds(100)) }
            if screen == "connection", let id = model.rows.first?.id { model.path = [.results, .detail(id)] }
        default:
            break
        }
    }
}
