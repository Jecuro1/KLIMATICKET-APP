import XCTest
@testable import KlimaCore

/// Via stops (docs/VIA.md): encoding, fare + distance rule, CSV.
final class TripViaTests: XCTestCase {
    // Real stations (stations.json) and official prices (relations.bin, Tarif ab 14.12.2025, 2. Kl.).
    let innsbruck = Station(id: "at:47:1187", name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T")
    let feldkirch = Station(id: "at:48:817", name: "Feldkirch", lat: 47.2416, lon: 9.60493, state: "V")
    let bregenz = Station(id: "at:48:452", name: "Bregenz", lat: 47.50237, lon: 9.73977, state: "V")
    let bludenz = Station(id: "at:48:130", name: "Bludenz", lat: 47.15529, lon: 9.81408, state: "V")
    let graz = Station(id: "at:46:3040", name: "Graz Hauptbahnhof", lat: 47.07248, lon: 15.41751, state: "ST")
    let villach = Station(id: "at:42:3654", name: "Villach Hauptbahnhof", lat: 46.61824, lon: 13.84857, state: "K")

    func catalog(fareIndex: [TariffCatalog.FareIndexPoint]? = nil) -> TariffCatalog {
        TariffCatalog(version: 1, updatedAt: "", products: [], fareModel: .fallback,
                      cityFares: [CityFare(id: "wien", name: "Wien", singleTicketEUR: 3.2, latitude: 48.2082, longitude: 16.3738, radiusKm: 11)],
                      kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.6, emissions: .fallback, fareIndex: fareIndex)
    }

    func table() throws -> RelationPriceTable {
        let ids = [innsbruck, feldkirch, bregenz, bludenz, graz, villach].map(\.id)
        let points = ids.enumerated().map { "{\"name\":\"\($0.offset)\",\"stationID\":\"\($0.element)\"}" }.joined(separator: ",")
        // [a, b, cents] – indices into `ids`
        let prices = [[0, 1, 3600], [0, 2, 4330], [1, 2, 890], [0, 3, 3200], [3, 2, 1330], [1, 3, 490],
                      [0, 4, 8110], [0, 5, 6260], [5, 4, 3790]]
        let json = "{\"validFrom\":\"2025-12-14\",\"source\":\"test\",\"points\":[\(points)],\"prices\":\(prices)}"
        return try RelationPriceTable(jsonData: Data(json.utf8))
    }

    func estimator(fareIndex: [TariffCatalog.FareIndexPoint]? = nil) throws -> FareEstimator {
        FareEstimator(catalog: catalog(fareIndex: fareIndex), relations: try table())
    }

    // MARK: Encoding

    func testCodecRoundTrip() {
        let vias = [TripVia(feldkirch), TripVia(name: "Lech Postamt")]
        let raw = TripViaCodec.encode(vias)
        XCTAssertEqual(raw, "at:48:817\tFeldkirch\n\tLech Postamt")
        XCTAssertEqual(TripViaCodec.decode(raw), vias)
    }

    func testCodecEmptyAndLegacy() {
        XCTAssertEqual(TripViaCodec.encode([]), "")
        XCTAssertEqual(TripViaCodec.decode(""), [])
        // A bare name and extra (future) fields are read, too.
        XCTAssertEqual(TripViaCodec.decode("Feldkirch"), [TripVia(name: "Feldkirch")])
        XCTAssertEqual(TripViaCodec.decode("at:48:817\tFeldkirch\t15\r\n"), [TripVia(feldkirch)])
    }

    func testCodecSanitizes() {
        let raw = TripViaCodec.encode([TripVia(name: "A\tB\nC"), TripVia(name: "  "), TripVia(name: "D"), TripVia(name: "E")])
        XCTAssertEqual(TripViaCodec.decode(raw), [TripVia(name: "A B C"), TripVia(name: "D")], "max 2, no empty names")
        XCTAssertEqual(TripViaCodec.sanitized([TripVia(feldkirch), TripVia(feldkirch), TripVia(bludenz)]),
                       [TripVia(feldkirch), TripVia(bludenz)], "a stop twice in a row counts once")
        XCTAssertEqual(TripVia.maxCount, JourneyQuery.maxViaStops)
    }

    func testNamesForCSV() {
        XCTAssertEqual(TripVia.joinedNames([TripVia(feldkirch), TripVia(bludenz)]), "Feldkirch · Bludenz")
        XCTAssertEqual(TripVia.parseNames("Feldkirch · Bludenz"), ["Feldkirch", "Bludenz"])
        XCTAssertEqual(TripVia.parseNames("Linz/Donau Hbf / Wels Hbf"), ["Linz/Donau Hbf", "Wels Hbf"])
        XCTAssertEqual(TripVia.parseNames("Feldkirch > Bludenz"), ["Feldkirch", "Bludenz"])
        XCTAssertEqual(TripVia.parseNames(" "), [])
    }

    // MARK: Tariff km

    func testTariffKmFromOfficialPrice() {
        let model = FareModel.fallback
        XCTAssertEqual(model.railKm(forFullFare: 36.0)!, 159.78, accuracy: 0.05)   // Innsbruck – Feldkirch
        XCTAssertEqual(model.railKm(forFullFare: 43.3)!, 194.12, accuracy: 0.05)   // Innsbruck – Bregenz
        XCTAssertEqual(model.fullFare(railKm: model.railKm(forFullFare: 62.6)!), 62.6, accuracy: 0.001)
        XCTAssertNil(model.railKm(forFullFare: 2.4), "minimum fare: any short hop fits")
        XCTAssertNil(model.railKm(forFullFare: 101.2), "maximum fare: any long trip fits")
        XCTAssertNil(model.railKm(forFullFare: 0))
    }

    // MARK: Fare + distance

    func testWithoutViaIsTheDirectEstimate() throws {
        let est = try estimator()
        let direct = est.estimate(from: innsbruck, to: bregenz, mode: .train)
        XCTAssertEqual(est.estimate(from: innsbruck, via: [], to: bregenz, mode: .train), direct)
        XCTAssertEqual(est.estimate(from: innsbruck, via: [innsbruck, bregenz], to: bregenz, mode: .train), direct,
                       "vias equal to start or destination are ignored")
        XCTAssertEqual(direct.fareEUR, 43.3, accuracy: 0.001)
        XCTAssertEqual(direct.distanceKm, 155.9, accuracy: 0.001)
    }

    func testViaOnTheDefaultPathKeepsTheOfficialPrice() throws {
        let est = try estimator()
        // Feldkirch lies on the Arlberg line to Bregenz: 159.8 + 37.8 tariff km ≈ 194.1 of the direct relation.
        let e = est.estimate(from: innsbruck, via: [feldkirch], to: bregenz, mode: .train)
        XCTAssertEqual(e.method, .officialTable)
        XCTAssertEqual(e.fareEUR, 43.3, accuracy: 0.001, "not 36,00 + 8,90 = 44,90")
        XCTAssertEqual(e.distanceKm, 202.8, accuracy: 0.001, "route distance = sum of the legs")
        XCTAssertEqual(e.explanation, "über Feldkirch · am Weg · ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025")

        let bludenzRoute = est.estimate(from: innsbruck, via: [bludenz], to: bregenz, mode: .train)
        XCTAssertEqual(bludenzRoute.method, .officialTable)
        XCTAssertEqual(bludenzRoute.fareEUR, 43.3, accuracy: 0.001)
        XCTAssertEqual(bludenzRoute.distanceKm, 194.5, accuracy: 0.001)
    }

    func testDetourIsPricedOnTheSummedTariffKm() throws {
        let est = try estimator()
        // Innsbruck → Villach → Graz: 299.7 + 168.7 = 468.4 tariff km (direct relation 431.5 km, € 81,10).
        let e = est.estimate(from: innsbruck, via: [villach], to: graz, mode: .train)
        XCTAssertEqual(e.method, .distanceTariff)
        XCTAssertEqual(e.fareEUR, 85.3, accuracy: 0.001, "degressive: one ticket over 468 km, not 62,60 + 37,90 = 100,50")
        XCTAssertEqual(e.distanceKm, 401.1, accuracy: 0.001)
        XCTAssertEqual(e.explanation, "über Villach Hauptbahnhof · geschätzt nach Tarif-km · 2. Kl.")

        // Feldkirch, then back to Bludenz: a real detour (237.9 tariff km).
        let back = est.estimate(from: innsbruck, via: [feldkirch, bludenz], to: bregenz, mode: .train)
        XCTAssertEqual(back.method, .distanceTariff)
        XCTAssertEqual(back.fareEUR, 51.4, accuracy: 0.001)
        XCTAssertEqual(back.distanceKm, 234.2, accuracy: 0.001)
        XCTAssertTrue(back.explanation.hasPrefix("über Feldkirch und Bludenz · "))
    }

    func testDetourWithDiscountsAndFareIndex() throws {
        let est = try estimator(fareIndex: [.init(validFrom: "2026-12-13", factor: 1.035)])
        let vc = est.estimate(from: innsbruck, via: [villach], to: graz, mode: .train, discount: .vorteilscard)
        XCTAssertEqual(vc.fareEUR, 42.6, accuracy: 0.001)
        XCTAssertTrue(vc.explanation.hasSuffix("· mit Vorteilscard"))
        let later = Calendar.vienna.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 8))!
        let onPath = est.estimate(from: innsbruck, via: [feldkirch], to: bregenz, mode: .train, date: later)
        XCTAssertEqual(onPath.fareEUR, 44.8, accuracy: 0.001, "the direct official price with the 2027 tariff increase")
    }

    func testWithoutTableTheLegsAreSummedGeometrically() {
        let est = FareEstimator(catalog: catalog())
        let e = est.estimate(from: innsbruck, via: [feldkirch], to: bregenz, mode: .train)
        XCTAssertEqual(e.method, .distanceTariff)
        XCTAssertEqual(e.distanceKm, 202.8, accuracy: 0.001)
        XCTAssertEqual(e.fareEUR, 45.1, accuracy: 0.001, "fare(202.8 km), not fare(165.3) + fare(37.5)")
        XCTAssertLessThan(e.fareEUR, FareModel.fallback.fare(railKm: 165.3) + FareModel.fallback.fare(railKm: 37.5))
        XCTAssertGreaterThanOrEqual(e.fareEUR, est.estimate(from: innsbruck, to: bregenz, mode: .train).fareEUR)
    }

    func testCityRouteStaysOneSingleTicket() throws {
        let est = try estimator()
        let hbf = Station(id: "w1", name: "Wien Hbf", lat: 48.18519, lon: 16.37641, state: "W", kind: .metro)
        let karlsplatz = Station(id: "w2", name: "Karlsplatz", lat: 48.2002, lon: 16.3696, state: "W", kind: .metro)
        let praterstern = Station(id: "w3", name: "Praterstern", lat: 48.2196, lon: 16.3925, state: "W", kind: .metro)
        let e = est.estimate(from: hbf, via: [karlsplatz], to: praterstern, mode: .metro)
        XCTAssertEqual(e.method, .cityTicket)
        XCTAssertEqual(e.fareEUR, 3.2, accuracy: 0.001)
        XCTAssertEqual(e.explanation, "über Karlsplatz · Einzelfahrt Wien · € 3,20")
        // Leaving the Kernzone on the way: the whole route on the distance tariff.
        let out = est.estimate(from: hbf, via: [feldkirch], to: praterstern, mode: .train)
        XCTAssertEqual(out.method, .distanceTariff)
        XCTAssertGreaterThan(out.fareEUR, 90)
    }

    // MARK: CSV

    func testCSVExportImportWithVia() {
        let cal = Calendar.vienna
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 7, minute: 12))!
        let viaTrip = TripRecord(date: d, fromName: "Innsbruck Hauptbahnhof", toName: "Bregenz", fromStationID: innsbruck.id,
                                 toStationID: bregenz.id, mode: .train, distanceKm: 202.8, fareEUR: 43.3,
                                 via: [TripVia(name: "Landeck-Zams", stationID: "at:47:1212"), TripVia(feldkirch)])
        let direct = TripRecord(date: d.addingTimeInterval(3600), fromName: "Bregenz", toName: "Feldkirch", mode: .train,
                                distanceKm: 37.5, fareEUR: 8.9)
        let csv = TripCSVExport.trips([viaTrip, direct])
        let header = csv.dropFirst().split(separator: "\r\n").first.map(String.init)
        XCTAssertEqual(header, "Datum;Uhrzeit;Von;Nach;Über;Verkehrsmittel;Hin & Retour;Kategorie;Ohne Ticket nicht gefahren;"
                       + "Distanz gesamt (km);Normalpreis (€);Wert gesamt (€);Notiz")
        XCTAssertTrue(csv.contains(";Innsbruck Hauptbahnhof;Bregenz;Landeck-Zams · Feldkirch;Zug;"))

        let text = CSVImport.decode(Data(csv.utf8)).text
        let rows = CSVImport.parse(text, delimiter: CSVImport.sniffDelimiter(text))
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.format, .klimaBilanz)
        XCTAssertEqual(guess.fields, [.date, .time, .from, .to, .via, .mode, .roundTrip, .category, .induced, .totalDistance, .price,
                                      .totalValue, .note])
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed.map(\.via), [["Landeck-Zams", "Feldkirch"], []])
        XCTAssertEqual(parsed[0].fare, 43.3)
        XCTAssertEqual(parsed[0].distanceKm, 202.8)
        XCTAssertTrue(parsed.allSatisfy(\.isValid))
        // Re-importing the export finds the via trip as a duplicate; another via is another trip.
        XCTAssertEqual(CSVImport.duplicateKey(date: parsed[0].date!, fromName: parsed[0].fromName, toName: parsed[0].toName,
                                              fare: parsed[0].fare!, via: parsed[0].via),
                       CSVImport.duplicateKey(date: viaTrip.date, fromName: viaTrip.fromName, toName: viaTrip.toName,
                                              fare: viaTrip.fareEUR, via: viaTrip.via.map(\.name)))
        XCTAssertNotEqual(CSVImport.duplicateKey(date: d, fromName: "A", toName: "B", fare: 1, via: ["X"]),
                          CSVImport.duplicateKey(date: d, fromName: "A", toName: "B", fare: 1))
    }

    func testCSVWithoutViaColumnStillImports() {
        // A file from before via stops (v2 header without "Über").
        let old = "\u{FEFF}Datum;Uhrzeit;Von;Nach;Verkehrsmittel;Hin & Retour;Kategorie;Ohne Ticket nicht gefahren;"
            + "Distanz gesamt (km);Normalpreis (€);Wert gesamt (€);Notiz\r\n"
            + "09.10.2026;07:12;St. Anton am Arlberg;Innsbruck Hbf;Zug;ja;Arbeitsweg;nein;202,0;23,50;47,00;\r\n"
        let text = CSVImport.decode(Data(old.utf8)).text
        let rows = CSVImport.parse(text, delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertFalse(guess.fields.contains(.via))
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertTrue(parsed[0].isValid)
        XCTAssertEqual(parsed[0].via, [])
        XCTAssertEqual(parsed[0].fare, 23.5)
    }

    func testCSVViaHeaderSynonymsAndLimits() {
        let csv = "Datum;Von;Nach;Zwischenhalte;Preis\n01.10.2026;Innsbruck Hbf;Bregenz;Landeck-Zams / Bludenz / Feldkirch;43,30\n"
            + "02.10.2026;Innsbruck Hbf;Bregenz;Bregenz;43,30\n"
        let rows = CSVImport.parse(csv, delimiter: .semicolon)
        let guess = CSVImport.guessMapping(rows: rows)
        XCTAssertEqual(guess.fields[3], .via)
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed[0].via, ["Landeck-Zams", "Bludenz"], "at most two")
        XCTAssertEqual(parsed[1].via, [], "a via equal to the destination is dropped")
    }

    func testTemplateHasAViaExample() {
        let text = CSVImport.decode(Data(TripCSVExport.template().utf8)).text
        let rows = CSVImport.parse(text, delimiter: CSVImport.sniffDelimiter(text))
        let guess = CSVImport.guessMapping(rows: rows)
        let parsed = CSVImport.parseRows(rows, fields: guess.fields, hasHeader: guess.hasHeader)
        XCTAssertEqual(parsed.map(\.via), [[], ["Linz Hbf"]])
        XCTAssertTrue(parsed.allSatisfy(\.isValid))
    }

    // MARK: Atlas, rides

    func testAtlasDrawsTheRouteThroughTheVias() {
        let index = StationIndex(stations: [innsbruck, feldkirch, bregenz, bludenz])
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        let viaTrip = TripRecord(date: d, fromName: innsbruck.name, toName: bregenz.name, fromStationID: innsbruck.id,
                                 toStationID: bregenz.id, mode: .train, distanceKm: 202.8, fareEUR: 43.3, via: [TripVia(feldkirch)])
        let back = TripRecord(date: d, fromName: bregenz.name, toName: innsbruck.name, fromStationID: bregenz.id,
                              toStationID: innsbruck.id, mode: .train, distanceKm: 202.8, fareEUR: 43.3, via: [TripVia(feldkirch)])
        let direct = TripRecord(date: d, fromName: innsbruck.name, toName: bregenz.name, fromStationID: innsbruck.id,
                                toStationID: bregenz.id, mode: .train, distanceKm: 155.9, fareEUR: 43.3)
        let summary = Atlas.summarize([viaTrip, back, direct], stations: index)
        XCTAssertEqual(summary.routes.count, 2, "the via route (both directions) and the direct one")
        let route = try? XCTUnwrap(summary.routes.first { !$0.via.isEmpty })
        XCTAssertEqual(route?.legs, 2)
        XCTAssertEqual(route?.from.name, "Bregenz", "west → east")
        XCTAssertEqual(route?.to.name, "Innsbruck Hauptbahnhof")
        XCTAssertEqual(route?.via.map(\.name), ["Feldkirch"])
        XCTAssertTrue(route?.touches(Atlas.placeKey(feldkirch)) == true)
        // The path passes Feldkirch.
        let passes = route?.path.contains { $0.distanceKm(to: feldkirch.location) < 0.01 } ?? false
        XCTAssertTrue(passes)
        XCTAssertTrue(summary.places.contains { $0.name == "Feldkirch" })
    }

    func testRideTripKeepsViasAndOldRecordsDecode() throws {
        let ride = RideTrip(fromName: "Innsbruck Hbf", toName: "Bregenz", mode: .train, distanceKm: 202.8, fareEUR: 43.3,
                            via: [TripVia(feldkirch)])
        let data = try JSONEncoder().encode(ride)
        XCTAssertEqual(try JSONDecoder().decode(RideTrip.self, from: data).via, [TripVia(feldkirch)])
        let old = #"{"fromName":"A","toName":"B","mode":"train","distanceKm":1,"fareEUR":2}"#
        XCTAssertEqual(try JSONDecoder().decode(RideTrip.self, from: Data(old.utf8)).via, [])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(RideTrip(fromName: "A", toName: "B", mode: .train,
                                                                          distanceKm: 1, fareEUR: 2)), as: UTF8.self).contains("via"))
        XCTAssertEqual(RideNames.via(["Landeck-Zams", "Innsbruck Hauptbahnhof"]), "über Landeck-Zams und Innsbruck Hbf")
        XCTAssertNil(RideNames.via([]))
    }

    func testStopNames() {
        let t = TripRecord(date: Date(), fromName: "Innsbruck Hbf", toName: "Bregenz", mode: .train, distanceKm: 202.8, fareEUR: 43.3,
                           via: [TripVia(feldkirch)])
        XCTAssertEqual(t.stopNames, ["Innsbruck Hbf", "Feldkirch", "Bregenz"])
    }
}
