import XCTest
@testable import KlimaCore

/// Crash guards, search folding and the per-day calendar memo (stability stage "global").
final class StabilityTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Station search (bundled stations.json, no place index attached)

    static let stations: StationIndex = {
        let url = PlaceFixtures.resources.appendingPathComponent("stations.json")
        guard let data = try? Data(contentsOf: url), let index = try? StationIndex(jsonData: data) else {
            fatalError("cannot load \(url.path)")
        }
        return index
    }()

    private func first(_ query: String) -> String? { Self.stations.search(query, limit: 10).first?.name }

    func testHalfTypedMainStationsStillMatch() {
        XCTAssertEqual(first("Linz Haupt"), "Linz Hauptbahnhof")
        XCTAssertEqual(first("Linz Hauptbahnho"), "Linz Hauptbahnhof")
        XCTAssertEqual(first("Innsbruck Haupt"), "Innsbruck Hauptbahnhof")
        XCTAssertEqual(first("Wien Hauptb"), "Wien Hauptbahnhof")
        XCTAssertEqual(first("Wiener Neustadt Haupt"), "Wiener Neustadt Hauptbahnhof")
        XCTAssertEqual(first("Wien Westbahn"), "Wien Westbahnhof")
    }

    func testAbbreviationsStillMatch() {
        XCTAssertEqual(first("Linz Hbf"), "Linz Hauptbahnhof")
        XCTAssertEqual(first("Innsbruck Hbf"), "Innsbruck Hauptbahnhof")
        XCTAssertEqual(first("St. Pölten Hbf"), "St. Pölten Hauptbahnhof")
        XCTAssertEqual(first("St.Poelten"), "St. Pölten Hauptbahnhof")
        XCTAssertEqual(first("Innsbruck Westbf"), "Innsbruck Westbahnhof")
        XCTAssertEqual(first("Linz Hb"), "Linz Hauptbahnhof")
    }

    func testSanktAndStFindTheSaints() {
        for query in ["Sankt", "St", "St."] {
            let name = first(query) ?? ""
            XCTAssertTrue(name.hasPrefix("St."), "\(query) → \(name)")
        }
        XCTAssertEqual(first("Sankt Anton"), "St. Anton am Arlberg")
        let wienSt = Self.stations.search("Wien St", limit: 30).map(\.name)
        XCTAssertTrue(wienSt.contains("Wien Stephansplatz"), "\(wienSt)")
    }

    func testStationNamedUsesNamesThenAliases() {
        XCTAssertEqual(Self.stations.station(named: "Innsbruck Hbf")?.name, "Innsbruck Hauptbahnhof")
        XCTAssertEqual(Self.stations.station(named: "innsbruck hauptbahnhof")?.name, "Innsbruck Hauptbahnhof")
        XCTAssertEqual(Self.stations.station(named: "St. Anton am Arlberg")?.name, "St. Anton am Arlberg")
        XCTAssertNil(Self.stations.station(named: "Nirgendwo am See"))
    }

    func testNormalizeKeepsItsComparisonKeys() {
        XCTAssertEqual(StationIndex.normalize("Linz Hauptbahnhof"), "linz hbf")
        XCTAssertEqual(StationIndex.normalize("St. Pölten Hbf"), "st polten hbf")
        XCTAssertEqual(StationIndex.normalize("Sankt Pölten Hauptbahnhof"), "st polten hbf")
        XCTAssertEqual(StationIndex.normalize("Wien Westbahnhof"), "wien westbf")
    }

    func testEmptyQueryRanksByImportanceAndDistance() {
        XCTAssertEqual(Self.stations.search("", limit: 1).first?.name, "Wien Hauptbahnhof")
        let innsbruck = GeoPoint(latitude: 47.2633, longitude: 11.4008)
        let near = Self.stations.search("", limit: 5, near: innsbruck).map(\.name)
        XCTAssertTrue(near.contains("Innsbruck Hauptbahnhof"), "\(near)")
    }

    // MARK: Fare model from remote data

    private func model(knots: [[Double]]?) -> FareModel {
        var m = FareModel.fallback
        m.knots = knots
        return m
    }

    func testMalformedKnotsFallBackToBands() {
        let bands = model(knots: nil)
        for knots: [[Double]] in [[], [[10]], [[10], [20]], [[10, 5]], [[10, 5], [20]], [[10, 5], [.nan, 7]]] {
            let m = model(knots: knots)
            for km in [0.5, 10, 50, 300, 2000] {
                XCTAssertEqual(m.fullFare(railKm: km), bands.fullFare(railKm: km), accuracy: 0.0001, "\(knots) @ \(km)")
            }
        }
        // Two valid points among broken ones still form a curve.
        let curve = model(knots: [[0, 2], [7], [100, 22]])
        XCTAssertEqual(curve.fullFare(railKm: 50), 12, accuracy: 0.0001)
    }

    func testCatalogUsability() {
        let product = TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik,
                                    priceEUR: 1400, validFrom: "2026-01-01")
        let good = TariffCatalog(version: 9, updatedAt: "2026-10-01", products: [product], fareModel: .fallback,
                                 cityFares: [], kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.47, emissions: .fallback)
        XCTAssertTrue(good.isUsable)
        var noProducts = good
        noProducts.products = []
        XCTAssertFalse(noProducts.isUsable)
        var freeTicket = good
        freeTicket.products = [TicketProduct(id: "x", family: .oe, name: "X", variant: .klassik, priceEUR: 0, validFrom: "2026-01-01")]
        XCTAssertFalse(freeTicket.isUsable)
        var zeroFares = good
        zeroFares.fareModel = FareModel(baseFee: 0, bands: [], minimumFare: 0, maximumFare: 0, roundingStep: 0.1,
                                        firstClassFactor: 1, detourFactor: 1, discountFactors: [:], knots: [[0, 0], [10, 0]])
        XCTAssertFalse(zeroFares.isUsable)
    }

    // MARK: Ticket comparison

    func testComparisonPricesOptionsForThePeriodStart() {
        let klassik = TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik,
                                    priceEUR: 1400, validFrom: "2026-01-01",
                                    priceHistory: [TicketProduct.PricePoint(validFrom: "2025-08-01", priceEUR: 1300)])
        let trips = [TripRecord(date: date(2025, 11, 3), fromName: "A", toName: "B", mode: .train, distanceKm: 100,
                                fareEUR: 30, states: ["T"])]
        let autumn = TicketComparator.compare(trips: trips, products: [klassik], variant: .klassik, currentProductID: "oe-klassik",
                                              periodStart: date(2025, 10, 15, 0))
        XCTAssertEqual(autumn.first { $0.id == "oe-klassik" }?.ticketPrice, 1300)
        let today = TicketComparator.compare(trips: trips, products: [klassik], variant: .klassik, currentProductID: "oe-klassik")
        XCTAssertEqual(today.first { $0.id == "oe-klassik" }?.ticketPrice, 1400)
    }

    // MARK: Per-day calendar memo

    func testDayMemoMatchesTheCalendarAcrossDST() {
        var memo = DayMemo(cal)
        // Every 37 minutes over the spring-forward and fall-back weekends of 2026 and a stretch in between.
        var dates: [Date] = []
        for start in [date(2026, 3, 27, 0), date(2026, 10, 23, 0), date(2026, 6, 30, 20)] {
            for step in 0..<(4 * 24 * 60 / 37) { dates.append(start.addingTimeInterval(Double(step) * 37 * 60)) }
        }
        for d in dates {
            XCTAssertEqual(memo.startOfDay(d), cal.startOfDay(for: d), "\(d)")
            XCTAssertEqual(memo.startOfMonth(d), cal.date(from: cal.dateComponents([.year, .month], from: d)), "\(d)")
            XCTAssertEqual(memo.weekday(d), cal.component(.weekday, from: d), "\(d)")
        }
    }

    func testStatsAgreeWithPlainCalendarMath() {
        let period = TicketPeriod(productID: "oe-klassik", name: "Klassik", price: 1400, start: date(2026, 1, 1, 0),
                                  end: TicketPeriod.standardEnd(for: date(2026, 1, 1, 0), calendar: cal))
        var trips: [TripRecord] = []
        var d = date(2026, 1, 1, 6, 10)
        for i in 0..<400 {
            trips.append(TripRecord(date: d, fromName: "A\(i % 7)", toName: "B", mode: .train, distanceKm: 40, fareEUR: 9.5,
                                    isRoundTrip: i % 3 == 0, states: ["T"]))
            d = d.addingTimeInterval(Double(13 + i % 29) * 3600)
        }
        let s = SavingsCalculator.summary(ticket: period, trips: trips, now: date(2026, 12, 31, 23), calendar: cal)
        let inPeriod = trips.filter { period.contains($0.date) }
        XCTAssertEqual(s.travelDays, Set(inPeriod.map { cal.startOfDay(for: $0.date) }).count)
        let days = StatsAggregator.days(inPeriod, calendar: cal)
        XCTAssertEqual(days.map(\.day), Set(inPeriod.map { cal.startOfDay(for: $0.date) }).sorted())
        XCTAssertEqual(days.reduce(0) { $0 + $1.trips }, inPeriod.count)
        let months = StatsAggregator.months(inPeriod, calendar: cal)
        XCTAssertEqual(months.reduce(0) { $0 + $1.trips }, inPeriod.count)
        XCTAssertEqual(months.count, 12)
        let weekdays = StatsAggregator.weekdays(inPeriod, calendar: cal)
        for bucket in weekdays {
            let expected = inPeriod.filter { (cal.component(.weekday, from: $0.date) + 5) % 7 == bucket.weekday - 1 }.count
            XCTAssertEqual(bucket.trips, expected)
        }
        let series = SavingsCalculator.cumulativeSeries(ticket: period, trips: inPeriod, now: date(2026, 12, 31, 23), calendar: cal)
        XCTAssertEqual(series.last?.value ?? 0, inPeriod.reduce(0) { $0 + $1.totalValue }, accuracy: 0.001)
    }

    func testViennaCalendarIsMondayFirstInVienna() {
        XCTAssertEqual(Calendar.vienna.timeZone.identifier, "Europe/Vienna")
        XCTAssertEqual(Calendar.vienna.firstWeekday, 2)
        var copy = Calendar.vienna
        copy.firstWeekday = 1
        XCTAssertEqual(Calendar.vienna.firstWeekday, 2)
    }
}
