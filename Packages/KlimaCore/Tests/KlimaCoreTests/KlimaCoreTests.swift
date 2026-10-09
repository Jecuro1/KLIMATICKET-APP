import XCTest
@testable import KlimaCore

final class KlimaCoreTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func ticket(price: Double = 1300) -> TicketPeriod {
        let start = date(2026, 1, 1, 0)
        return TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price,
                            start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    func trip(_ d: Date, fare: Double, km: Double = 100, mode: TransportMode = .train, round: Bool = false,
              from: String = "Innsbruck Hbf", to: String = "St. Anton am Arlberg", states: Set<String> = ["T"]) -> TripRecord {
        TripRecord(date: d, fromName: from, toName: to, mode: mode, distanceKm: km, fareEUR: fare, isRoundTrip: round, states: states)
    }

    // MARK: Geo

    func testHaversineWienSalzburg() {
        let wien = GeoPoint(latitude: 48.18523, longitude: 16.37613)   // Wien Hbf
        let sbg = GeoPoint(latitude: 47.81293, longitude: 13.04547)    // Salzburg Hbf
        XCTAssertEqual(wien.distanceKm(to: sbg), 251, accuracy: 4)
    }

    // MARK: Ticket period

    func testStandardEndIs365Days() {
        let t = ticket()
        let days = cal.dateComponents([.day], from: t.start, to: t.end).day!
        XCTAssertEqual(days, 364) // 1 Jan 00:00 → 31 Dec 23:59:59
        XCTAssertEqual(cal.component(.month, from: t.end), 12)
        XCTAssertEqual(cal.component(.day, from: t.end), 31)
    }

    // MARK: Fares

    func testFareModelIsMonotonicAndBounded() {
        let m = FareModel.fallback
        var last = 0.0
        for km in stride(from: 1.0, through: 900, by: 7) {
            let f = m.fullFare(railKm: km)
            XCTAssertGreaterThanOrEqual(f, last - 0.0001, "fare must not decrease (km \(km))")
            XCTAssertLessThanOrEqual(f, m.maximumFare)
            XCTAssertGreaterThanOrEqual(f, m.minimumFare)
            last = f
        }
    }

    func testFareDiscountsAndClass() {
        let m = FareModel.fallback
        let full = m.fare(railKm: 120)
        XCTAssertEqual(m.fare(railKm: 120, discount: .vorteilscard), full * 0.5, accuracy: 0.11)
        XCTAssertGreaterThan(m.fare(railKm: 120, travelClass: .first), full)
    }

    func testEstimatorUsesCityTicketInsideCity() {
        let catalog = TariffCatalog(version: 1, updatedAt: "2026-01-01", products: [], fareModel: .fallback,
                                    cityFares: [CityFare(id: "wien", name: "Wien", singleTicketEUR: 3.2, latitude: 48.2082, longitude: 16.3738, radiusKm: 11)],
                                    kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.6, emissions: .fallback)
        let est = FareEstimator(catalog: catalog)
        let a = GeoPoint(latitude: 48.18523, longitude: 16.37613)  // Hbf
        let b = GeoPoint(latitude: 48.2196, longitude: 16.3925)    // Praterstern
        let e = est.estimate(from: a, to: b, mode: .metro)
        XCTAssertEqual(e.method, .cityTicket)
        XCTAssertEqual(e.fareEUR, 3.2)

        let sbg = GeoPoint(latitude: 47.81293, longitude: 13.04547)
        let long = est.estimate(from: a, to: sbg, mode: .train)
        XCTAssertEqual(long.method, .distanceTariff)
        XCTAssertGreaterThan(long.distanceKm, 280)
        XCTAssertGreaterThan(long.fareEUR, 40)
    }

    func testRelationTableOverridesDistanceTariff() throws {
        let json = """
        {"validFrom":"2025-12-14","source":"test","points":[{"name":"Wien","stationID":"a"},{"name":"Salzburg","stationID":"b"}],
         "prices":[[0,1,6770]]}
        """.data(using: .utf8)!
        let table = try RelationPriceTable(jsonData: json)
        XCTAssertEqual(table.price(from: "b", to: "a"), 67.7)
        let catalog = TariffCatalog(version: 1, updatedAt: "", products: [], fareModel: .fallback, cityFares: [],
                                    kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.6, emissions: .fallback)
        let est = FareEstimator(catalog: catalog, relations: table)
        let a = Station(id: "a", name: "Wien Hbf", lat: 48.185, lon: 16.376, state: "W")
        let b = Station(id: "b", name: "Salzburg Hbf", lat: 47.813, lon: 13.045, state: "S")
        let e = est.estimate(from: a, to: b, mode: .train)
        XCTAssertEqual(e.method, .officialTable)
        XCTAssertEqual(e.fareEUR, 67.7, accuracy: 0.001)
        XCTAssertEqual(est.estimate(from: a, to: b, mode: .train, discount: .vorteilscard).fareEUR, 33.9, accuracy: 0.051)
        XCTAssertTrue(e.explanation.contains("14.12.2025"))
    }

    func testKnotModelMatchesOfficialExamples() {
        let m = FareModel.fallback
        // Wien–Salzburg: 310 km rail → official 67.70
        XCTAssertEqual(m.fare(railKm: 310.3), 67.7, accuracy: 3.5)
        // Wien–Graz: 210.6 km → 44.30
        XCTAssertEqual(m.fare(railKm: 210.6), 44.3, accuracy: 3)
        XCTAssertEqual(m.fare(railKm: 3), 2.4, accuracy: 0.01)          // minimum fare
        XCTAssertEqual(m.fare(railKm: 2000), 101.2, accuracy: 0.01)    // cap
    }

    func testFareIndexAfterDecember2026() {
        let catalog = TariffCatalog(version: 1, updatedAt: "", products: [], fareModel: .fallback, cityFares: [],
                                    kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.47, emissions: .fallback,
                                    fareIndex: [.init(validFrom: "2026-12-13", factor: 1.035)])
        XCTAssertEqual(catalog.fareFactor(on: date(2026, 12, 12)), 1)
        XCTAssertEqual(catalog.fareFactor(on: date(2026, 12, 13)), 1.035, accuracy: 0.0001)
        let json = """
        {"validFrom":"2025-12-14","source":"t","points":[{"name":"A","stationID":"a"},{"name":"B","stationID":"b"}],"prices":[[0,1,2350]]}
        """.data(using: .utf8)!
        let est = FareEstimator(catalog: catalog, relations: try! RelationPriceTable(jsonData: json))
        let a = Station(id: "a", name: "St. Anton", lat: 47.127, lon: 10.267, state: "T")
        let b = Station(id: "b", name: "Innsbruck", lat: 47.263, lon: 11.400, state: "T")
        XCTAssertEqual(est.estimate(from: a, to: b, mode: .train, date: date(2026, 11, 1)).fareEUR, 23.5, accuracy: 0.001)
        XCTAssertEqual(est.estimate(from: a, to: b, mode: .train, date: date(2027, 1, 10)).fareEUR, 24.3, accuracy: 0.001)
    }

    func testBinaryRelationTable() {
        var data = Data()
        for v: UInt16 in [0, 1, 677] { data.append(UInt8(v & 0xFF)); data.append(UInt8(v >> 8)) }
        let t = RelationPriceTable(validFrom: "2025-12-14", source: "", pointIDs: ["x", "y"], triples: data)
        XCTAssertEqual(t.price(from: "y", to: "x"), 67.7)
        XCTAssertEqual(t.count, 1)
    }

    func testEuroFormatting() {
        XCTAssertEqual(FareEstimator.euro(3.2), "€ 3,20")
        XCTAssertEqual(FareEstimator.euro(1300), "€ 1300,00")
    }

    // MARK: Savings

    func testSummaryBreakEvenAndPaidOffDate() {
        let t = ticket(price: 100)
        let trips = [
            trip(date(2026, 1, 5), fare: 30),
            trip(date(2026, 1, 6), fare: 30, round: true),   // 60 → 90
            trip(date(2026, 1, 9), fare: 20),                // 110 → paid off
            trip(date(2025, 12, 31), fare: 500),             // outside period
        ]
        let s = SavingsCalculator.summary(ticket: t, trips: trips, now: date(2026, 1, 10), calendar: cal)
        XCTAssertEqual(s.totalValue, 110, accuracy: 0.001)
        XCTAssertTrue(s.isPaidOff)
        XCTAssertEqual(s.tripCount, 3)
        XCTAssertEqual(s.legCount, 4)
        XCTAssertEqual(s.net, 10, accuracy: 0.001)
        XCTAssertEqual(cal.component(.day, from: s.paidOffDate!), 9)
        XCTAssertNil(s.forecastBreakEvenDate)
        XCTAssertEqual(s.daysElapsed, 10)
        XCTAssertEqual(s.daysTotal, 365)
    }

    func testForecastPredictsBreakEven() {
        let t = ticket(price: 1300)
        // 10 €/day for 30 days
        let trips = (1...30).map { trip(date(2026, 1, $0), fare: 10) }
        let s = SavingsCalculator.summary(ticket: t, trips: trips, now: date(2026, 1, 30, 20), calendar: cal)
        XCTAssertFalse(s.isPaidOff)
        XCTAssertNotNil(s.forecastBreakEvenDate)
        XCTAssertTrue(s.forecastReachesBreakEven)
        // remaining 1000 € at 10 €/day ≈ 100 days after 30 Jan → around 10 May
        let month = cal.component(.month, from: s.forecastBreakEvenDate!)
        XCTAssertTrue((4...6).contains(month), "unexpected forecast month \(month)")
        XCTAssertGreaterThan(s.forecastEndValue, 3000)
    }

    func testCumulativeSeriesIsMonotonic() {
        let t = ticket()
        let trips = [trip(date(2026, 2, 1), fare: 12), trip(date(2026, 2, 1, 18), fare: 12), trip(date(2026, 3, 4), fare: 40)]
        let series = SavingsCalculator.cumulativeSeries(ticket: t, trips: trips, now: date(2026, 4, 1), calendar: cal)
        XCTAssertEqual(series.first?.value, 0)
        XCTAssertEqual(series.last?.value ?? 0, 64, accuracy: 0.001)
        XCTAssertEqual(zip(series, series.dropFirst()).allSatisfy { $0.value <= $1.value && $0.date <= $1.date }, true)
    }

    // MARK: Stats

    func testWeekdayBucketsMondayFirst() {
        // 5 Jan 2026 is a Monday, 11 Jan a Sunday
        let w = StatsAggregator.weekdays([trip(date(2026, 1, 5), fare: 1), trip(date(2026, 1, 11), fare: 1)], calendar: cal)
        XCTAssertEqual(w[0].trips, 1)
        XCTAssertEqual(w[6].trips, 1)
        XCTAssertEqual(w[0].shortName, "Mo")
    }

    func testMonthsInPeriodHasTwelveBuckets() {
        let m = StatsAggregator.months([trip(date(2026, 3, 3), fare: 5)], in: ticket(), calendar: cal)
        XCTAssertEqual(m.count, 12)
        XCTAssertEqual(m[2].value, 5)
    }

    func testStreaksAndTopRoutes() {
        let trips = [trip(date(2026, 1, 1), fare: 5), trip(date(2026, 1, 2), fare: 5), trip(date(2026, 1, 3), fare: 5),
                     trip(date(2026, 1, 7), fare: 5, from: "Wien Hbf", to: "Linz Hbf", states: ["W", "NÖ", "OÖ"])]
        let r = StatsAggregator.records(trips, now: date(2026, 1, 3, 20), calendar: cal)
        XCTAssertEqual(r.longestStreakDays, 3)
        XCTAssertEqual(r.currentStreakDays, 3)
        XCTAssertEqual(r.statesVisited, ["T", "W", "NÖ", "OÖ"])
        let top = StatsAggregator.topRoutes(trips)
        XCTAssertEqual(top.first?.trips, 3)
    }

    // MARK: Stations

    func testStationSearch() {
        let idx = StationIndex(stations: [
            Station(id: "1", name: "Innsbruck Hbf", lat: 47.263, lon: 11.401, state: "T", importance: 95),
            Station(id: "2", name: "St. Anton am Arlberg", lat: 47.128, lon: 10.268, state: "T", importance: 70),
            Station(id: "3", name: "Wörgl Hbf", lat: 47.489, lon: 12.067, state: "T", importance: 70),
            Station(id: "4", name: "Wien Hauptbahnhof", lat: 48.185, lon: 16.376, state: "W", importance: 100),
            Station(id: "5", name: "Innsbruck Westbahnhof", lat: 47.262, lon: 11.380, state: "T", importance: 40),
        ])
        XCTAssertEqual(idx.search("innsb").first?.name, "Innsbruck Hbf")
        XCTAssertEqual(idx.search("st anton").first?.name, "St. Anton am Arlberg")
        XCTAssertEqual(idx.search("Sankt Anton").first?.name, "St. Anton am Arlberg")
        XCTAssertEqual(idx.search("wörgl").first?.name, "Wörgl Hbf")
        XCTAssertEqual(idx.search("Worgl").first?.name, "Wörgl Hbf")
        XCTAssertEqual(idx.search("wien hauptbahnhof").first?.id, "4")
        XCTAssertEqual(idx.search("anton").first?.id, "2")
        XCTAssertEqual(idx.search("").first?.id, "4")
        XCTAssertEqual(idx.station(named: "wien hbf")?.id, "4")
    }

    // MARK: Comparator

    func testComparatorPrefersRegionalForTyrolOnlyTrips() {
        let products = [
            TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö", variant: .klassik, priceEUR: 1300, validFrom: "2026-01-01"),
            TicketProduct(id: "t-klassik", family: .regional, states: ["T"], name: "KlimaTicket Tirol", variant: .klassik, priceEUR: 600, validFrom: "2026-01-01"),
        ]
        let trips = (1...100).map { trip(date(2026, 1, 1).addingTimeInterval(Double($0) * 86_400), fare: 15) }
        let opts = TicketComparator.compare(trips: trips, products: products, variant: .klassik, currentProductID: "oe-klassik")
        XCTAssertEqual(opts.first?.id, "t-klassik")
        XCTAssertEqual(opts.last?.id, "single")
    }

    func testPriceDependsOnStartDate() {
        let p = TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik, priceEUR: 1400, validFrom: "2026-01-01",
                              priceHistory: [.init(validFrom: "2021-10-26", priceEUR: 1095), .init(validFrom: "2025-01-01", priceEUR: 1179.3),
                                             .init(validFrom: "2025-08-01", priceEUR: 1300)])
        XCTAssertEqual(p.price(forStart: date(2026, 3, 1)), 1400)
        XCTAssertEqual(p.price(forStart: date(2025, 9, 1)), 1300)
        XCTAssertEqual(p.price(forStart: date(2025, 7, 31)), 1179.3)
        XCTAssertEqual(p.price(forStart: date(2023, 5, 1)), 1095)
        XCTAssertEqual(p.price(forStart: date(2020, 5, 1)), 1095)
    }

    // MARK: Achievements

    func testAchievements() {
        let t = ticket(price: 100)
        let trips = [trip(date(2026, 1, 5, 23), fare: 120, km: 1200)]
        let s = SavingsCalculator.summary(ticket: t, trips: trips, now: date(2026, 1, 6), calendar: cal)
        let a = AchievementEngine.evaluate(summary: s, trips: trips, records: StatsAggregator.records(trips, calendar: cal))
        XCTAssertTrue(a.first { $0.id == "break-even" }!.isUnlocked)
        XCTAssertTrue(a.first { $0.id == "km-1000" }!.isUnlocked)
        XCTAssertTrue(a.first { $0.id == "night-owl" }!.isUnlocked)
        XCTAssertFalse(a.first { $0.id == "double" }!.isUnlocked)
        XCTAssertEqual(AchievementEngine.group(10000), "10.000")
    }

    // MARK: Updates

    func testSemanticVersion() {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(SemanticVersion("2"), SemanticVersion(major: 2))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.9")!)
        XCTAssertEqual(SemanticVersion("1.2.3-beta+5")?.description, "1.2.3")
    }

    func testUpdateDecision() throws {
        let json = """
        {"version":"1.3.0","build":42,"publishedAt":"2026-10-09T10:00:00Z","downloadURL":"https://example.com/a.ipa",
         "releaseNotes":["Neu"],"minimumSupportedVersion":"1.1.0"}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(UpdateManifest.self, from: json)
        XCTAssertEqual(UpdateDecision.evaluate(installed: SemanticVersion("1.3.0")!, installedBuild: 42, manifest: m), .upToDate)
        XCTAssertEqual(UpdateDecision.evaluate(installed: SemanticVersion("1.2.0")!, installedBuild: 1, manifest: m), .available(m))
        XCTAssertEqual(UpdateDecision.evaluate(installed: SemanticVersion("1.0.9")!, installedBuild: 1, manifest: m), .required(m))
        XCTAssertEqual(UpdateDecision.evaluate(installed: SemanticVersion("1.3.0")!, installedBuild: 41, manifest: m), .available(m))
    }

    // MARK: CSV

    func testCSV() {
        let csv = CSVExport.trips([trip(date(2026, 1, 5, 7), fare: 12.5, km: 10, round: true, from: "A; B", to: "C")], calendar: cal)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Datum;"))
        XCTAssertTrue(csv.contains("05.01.2026;07:00;\"A; B\";C;Zug;ja;20,0;12,50;25,00"))
    }
}
