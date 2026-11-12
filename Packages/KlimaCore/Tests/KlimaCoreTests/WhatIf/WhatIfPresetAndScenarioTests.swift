import XCTest
@testable import KlimaCore

/// Presets (bundled stations, real catalogue) and the saved-scenario book.
final class WhatIfPresetAndScenarioTests: XCTestCase {
    typealias F = WhatIfFixtures

    func bundledStations() throws -> StationIndex {
        try StationIndex(jsonData: Data(contentsOf: PlaceFixtures.resources.appendingPathComponent("stations.json")))
    }

    func bundledCatalog() throws -> TariffCatalog {
        try TariffCatalog.decode(from: Data(contentsOf: PlaceFixtures.resources.appendingPathComponent("tariffs.json")))
    }

    // MARK: Presets

    func testPresetsAreWellFormedAndUseBundledStations() throws {
        let stations = try bundledStations()
        XCTAssertEqual(WhatIfPreset.all.map(\.id), ["commute", "weekend", "occasional"])
        XCTAssertEqual(Set(WhatIfPreset.all.map(\.id)).count, 3)
        for preset in WhatIfPreset.all {
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertTrue((1...WhatIfLimits.maxRoutes).contains(preset.routes.count), preset.id)
            for route in preset.routes {
                XCTAssertNotNil(stations.station(id: route.fromStationID), "\(preset.id): \(route.fromStationID)")
                XCTAssertNotNil(stations.station(id: route.toStationID), "\(preset.id): \(route.toStationID)")
                XCTAssertTrue((1...WhatIfLimits.maxTripsPerMonth).contains(route.tripsPerMonth))
            }
            let input = preset.input(startDate: F.date(2026, 11, 1))
            XCTAssertEqual(input.routes.count, preset.routes.count)
            XCTAssertEqual(Set(input.routes.map(\.id)).count, input.routes.count, "fresh ids")
        }
        XCTAssertEqual(WhatIfPreset.preset(id: "weekend")?.routes.first?.tripsPerMonth, 4)
        XCTAssertNil(WhatIfPreset.preset(id: "nope"))
    }

    /// The three presets on the shipped tariffs (distance model: the relation table is binary and not read here):
    /// a daily commute pays off with a regional ticket, a weekend home trip with KlimaTicket Ö, an occasional trip with neither.
    func testPresetsOnTheBundledCatalogue() throws {
        let calc = WhatIfCalculator(catalog: try bundledCatalog(), relations: .empty, stations: try bundledStations())
        func result(_ id: String) -> WhatIfResult {
            calc.evaluate(WhatIfPreset.preset(id: id)!.input(startDate: F.date(2026, 11, 1)))
        }
        let commute = result("commute")
        XCTAssertEqual(commute.state, .ready)
        XCTAssertTrue(commute.ticketIsCheaper)
        XCTAssertEqual(commute.bestTicket?.family, .regional, "Wiener Neustadt – Wien lies inside the VOR region ticket")
        XCTAssertLessThan(commute.bestTicket!.yearlyCost, F.option(commute, "oe-klassik").yearlyCost)
        XCTAssertNotNil(commute.crossing)

        let weekend = result("weekend")
        XCTAssertEqual(weekend.bestTicket?.id, "oe-klassik")
        XCTAssertTrue(weekend.ticketIsCheaper)
        let fare = weekend.routeFares[0].farePerTrip
        XCTAssertTrue((30...60).contains(fare), "Graz – Wien model fare \(fare) (official 44,30)")

        let occasional = result("occasional")
        XCTAssertEqual(occasional.bestTicket?.id, "oe-klassik")
        XCTAssertFalse(occasional.ticketIsCheaper)
        XCTAssertLessThan(occasional.yearlyDelta, 0, "the ticket would cost more than single tickets")
        XCTAssertEqual(occasional.options.first?.id, "single")
        XCTAssertNil(occasional.crossing)
    }

    /// The bundled catalogue: the products the screen relies on exist (Klassik, Jugend, Senior of KlimaTicket Ö).
    func testBundledCatalogueHasTheVariantsTheScreenOffers() throws {
        let catalog = try bundledCatalog()
        for variant in [TicketVariant.klassik, .jugend, .senior] {
            XCTAssertTrue(catalog.products.contains { $0.family == .oe && $0.variant == variant }, variant.rawValue)
        }
        XCTAssertFalse(catalog.updatedAt.isEmpty, "Tarifstand")
    }

    // MARK: Scenarios

    func scenario(_ name: String, usesHistory: Bool = false) -> WhatIfScenario {
        WhatIfScenario(name: name, createdAt: F.date(2026, 11, 12), usesHistory: usesHistory,
                       input: F.input([F.tirol(8)]), savedHeadline: "KlimaTicket Tirol · € 1.000 weniger im Jahr")
    }

    func testBookHoldsFiveScenarios() {
        var book = WhatIfScenarioBook()
        for index in 1...5 { XCTAssertTrue(book.add(scenario("S\(index)"))) }
        XCTAssertTrue(book.isFull)
        XCTAssertFalse(book.add(scenario("S6")), "full: nothing is dropped silently")
        XCTAssertEqual(book.scenarios.map(\.name), ["S5", "S4", "S3", "S2", "S1"], "newest first")
        book.remove(id: book.scenarios[2].id)
        XCTAssertFalse(book.isFull)
        XCTAssertTrue(book.add(scenario("S7")))
        book.rename(id: book.scenarios[0].id, to: "Neu")
        XCTAssertEqual(book.scenarios[0].name, "Neu")
    }

    func testBookRoundTrip() throws {
        var book = WhatIfScenarioBook()
        var input = F.input([F.tirol(8), F.westbahn(2)], variant: .jugend)
        input.excludedMonths = [7, 8]
        input.regionFilter = "T"
        input.volumeFactor = 1.5
        input.useFirstClass = true
        book.add(WhatIfScenario(name: "Test", createdAt: F.date(2026, 11, 12), usesHistory: true, input: input, savedHeadline: "x"))
        let data = try XCTUnwrap(book.encoded())
        XCTAssertEqual(WhatIfScenarioBook.decode(data), book)
        XCTAssertEqual(WhatIfScenarioBook.decode(data).version, WhatIfScenarioBook.currentVersion)
    }

    func testDamagedOrNewerSaveGivesAnEmptyBook() throws {
        XCTAssertTrue(WhatIfScenarioBook.decode(nil).scenarios.isEmpty)
        XCTAssertTrue(WhatIfScenarioBook.decode(Data("not json".utf8)).scenarios.isEmpty)
        XCTAssertTrue(WhatIfScenarioBook.decode(Data("{\"version\":1}".utf8)).scenarios.isEmpty)
        var book = WhatIfScenarioBook(scenarios: [scenario("A")])
        book.version = 99
        XCTAssertTrue(WhatIfScenarioBook.decode(book.encoded()).scenarios.isEmpty, "a save from a newer app is not guessed at")
        // A hand-edited save with too many entries is cut to five.
        let many = WhatIfScenarioBook(scenarios: (1...9).map { scenario("S\($0)") })
        XCTAssertEqual(WhatIfScenarioBook.decode(many.encoded()).scenarios.count, 5)
    }

    func testScenarioInputsSurviveAClampedReload() throws {
        // Out-of-range values in a saved scenario never reach the calculator unclamped.
        var input = F.input([F.tirol(9_999)])
        input.volumeFactor = 77
        input.excludedMonths = [99]
        let book = WhatIfScenarioBook(scenarios: [WhatIfScenario(name: "x", usesHistory: false, input: input)])
        let loaded = try XCTUnwrap(WhatIfScenarioBook.decode(book.encoded()).scenarios.first)
        let result = F.calculator().evaluate(loaded.input)
        XCTAssertEqual(result.tripsPerMonth, 60, accuracy: 1e-9)
        XCTAssertEqual(loaded.input.clampedVolume, 2)
        XCTAssertTrue(loaded.input.validExcludedMonths.isEmpty)
    }
}
