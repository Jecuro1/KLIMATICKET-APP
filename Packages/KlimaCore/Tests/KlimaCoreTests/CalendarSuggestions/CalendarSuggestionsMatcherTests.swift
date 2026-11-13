import XCTest
@testable import KlimaCore

final class CalendarSuggestionsNormalizerTests: XCTestCase {
    func testStationAndStreetPieces() {
        let n = LocationNormalizer.normalize("Mirabellplatz 4, 5020 Salzburg")
        XCTAssertEqual(n.segments.map(\.text), ["Mirabellplatz 4"])
        XCTAssertEqual(n.segments.map(\.isStreet), [true])
        XCTAssertEqual(n.postalTown, "Salzburg")
        XCTAssertFalse(n.isVirtual)

        let venue = LocationNormalizer.normalize("Großes Festspielhaus\nHofstallgasse 1, 5020 Salzburg, Österreich")
        XCTAssertEqual(venue.segments.map(\.text), ["Großes Festspielhaus", "Hofstallgasse 1"])
        XCTAssertEqual(venue.segments.map(\.isStreet), [false, true])
        XCTAssertEqual(venue.postalTown, "Salzburg")

        XCTAssertEqual(LocationNormalizer.normalize("Salzburg Hbf").segments.map(\.text), ["Salzburg Hbf"])
        XCTAssertEqual(LocationNormalizer.normalize("Salzburg Hbf, Gleis 3").segments.map(\.text), ["Salzburg Hbf"])
        XCTAssertEqual(LocationNormalizer.normalize("Salzburg (Hbf) Bahnsteig 4a").segments.map(\.text), ["Salzburg Hbf"])
        XCTAssertEqual(LocationNormalizer.normalize("A-6580 St. Anton am Arlberg").postalTown, "St. Anton am Arlberg")
        XCTAssertEqual(LocationNormalizer.normalize("AT-1060 Wien").postalTown, "Wien")
        XCTAssertEqual(LocationNormalizer.normalize("Schwarzach-St. Veit").segments.map(\.text), ["Schwarzach-St. Veit"])
        XCTAssertEqual(LocationNormalizer.normalize("Linz - Hauptplatz").segments.map(\.text), ["Linz", "Hauptplatz"])
    }

    func testVirtualAndEmpty() {
        for text in ["Zoom", "Microsoft Teams-Besprechung", "https://example.org/meeting/123", "Online", "Telefon",
                     "Google Meet: meet.google.com/abc", "Webex Raum 4"] {
            XCTAssertTrue(LocationNormalizer.normalize(text).isVirtual, text)
        }
        for text: String? in [nil, "", "   ", "Büro", "Home Office", "tbd", "Österreich"] {
            let n = LocationNormalizer.normalize(text)
            XCTAssertTrue(n.isEmpty, text ?? "nil")
            XCTAssertFalse(n.isVirtual, text ?? "nil")
        }
    }

    func testStreetDetection() {
        XCTAssertTrue(LocationNormalizer.isStreet("Mirabellplatz 4"))
        XCTAssertTrue(LocationNormalizer.isStreet("Hauptstraße 12/3"))
        XCTAssertTrue(LocationNormalizer.isStreet("Bahnhofstraße"))
        XCTAssertTrue(LocationNormalizer.isStreet("Südtiroler Platz"))
        XCTAssertTrue(LocationNormalizer.isStreet("Am Hauptbahnhof 1"))
        XCTAssertFalse(LocationNormalizer.isStreet("Salzburg Hbf"))
        XCTAssertFalse(LocationNormalizer.isStreet("Neumarkt"))
        XCTAssertFalse(LocationNormalizer.isStreet("St. Anton am Arlberg"))
        XCTAssertFalse(LocationNormalizer.isStreet("Großes Festspielhaus"))
    }
}

final class CalendarSuggestionsMatcherTests: XCTestCase {
    private let matcher = CalendarFixtures.matcher

    private func assertMatch(_ location: String, _ id: String, _ precision: CalendarPlaceMatch.Precision, place: String? = nil,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let m = matcher.match(location: location) else {
            return XCTFail("no match for \(location)", file: file, line: line)
        }
        XCTAssertEqual(m.station.id, id, "\(location) → \(m.station.name)", file: file, line: line)
        XCTAssertEqual(m.precision, precision, location, file: file, line: line)
        if let place { XCTAssertEqual(m.placeText, place, location, file: file, line: line) }
    }

    private func assertNoMatch(_ location: String?, file: StaticString = #filePath, line: UInt = #line) {
        let m = matcher.match(location: location)
        XCTAssertNil(m, "\(location ?? "nil") → \(m?.station.name ?? "")", file: file, line: line)
    }

    func testStationNames() {
        assertMatch("Salzburg Hbf", "at:45:50002", .station)
        assertMatch("Salzburg Hauptbahnhof", "at:45:50002", .station)
        assertMatch("Hauptbahnhof Salzburg", "at:45:50002", .station)
        assertMatch("Hbf. Salzburg", "at:45:50002", .station)
        assertMatch("Salzburg Hauptbahnhof, Südtiroler Platz 1, 5020 Salzburg", "at:45:50002", .station)
        assertMatch("Linz Hbf", "at:44:41164", .station)
        assertMatch("Bahnhof Linz", "at:44:41164", .station)
        assertMatch("Linz/Donau Hauptbahnhof", "at:44:41164", .station)
        assertMatch("Wien Mitte", "at:49:743", .station)
        assertMatch("Salzburg Süd", "at:45:50458", .station)
        assertMatch("Bahnhof St. Anton am Arlberg", "at:47:1222", .station)
        assertMatch("St.Anton am Arlberg Bahnhof", "at:47:1222", .station)
        assertMatch("Bahnhof Bregenz", "at:48:452", .station)
        // The rail station wins over the U-Bahn station of the same name.
        assertMatch("Wien Hauptbahnhof", "at:49:1349", .station)
        assertMatch("Wien Westbahnhof", "at:49:1468", .station)
        assertMatch("Westbahnhof Wien", "at:49:1468", .station)
        // A generic word becomes a station with the postcode's town.
        assertMatch("Westbahnhof, 1150 Wien", "at:49:1468", .station)
        assertMatch("Hauptbahnhof, 4020 Linz", "at:44:41164", .station)
    }

    func testTowns() {
        assertMatch("Mirabellplatz 4, 5020 Salzburg", "at:45:50002", .town, place: "Salzburg")
        assertMatch("Großes Festspielhaus, Hofstallgasse 1, 5020 Salzburg, Österreich", "at:45:50002", .town, place: "Salzburg")
        assertMatch("Wien", "at:49:1349", .town, place: "Wien")
        assertMatch("Wien, Österreich", "at:49:1349", .town, place: "Wien")
        assertMatch("Mariahilfer Straße 1, 1060 Wien-Mariahilf", "at:49:1349", .town, place: "Wien")
        assertMatch("Graz", "at:46:3040", .town)
        assertMatch("Sankt Pölten", "at:43:4848", .town)
        assertMatch("3100 St. Pölten", "at:43:4848", .town)
        // A station named exactly like the town, written without a station word: the town, "ungefähr".
        assertMatch("Bregenz", "at:48:452", .town, place: "Bregenz")
        assertMatch("St. Anton am Arlberg", "at:47:1222", .town)
    }

    func testNoConfidentMatchGivesNil() {
        assertNoMatch("Zoom")
        assertNoMatch("Büro")
        assertNoMatch("")
        assertNoMatch(nil)
        assertNoMatch("Mirabellplatz 4")             // a street alone
        assertNoMatch("Siemensstraße")               // street-like alias of Wien Siemensstraße
        assertNoMatch("Hauptbahnhof")                // which one?
        assertNoMatch("Neumarkt")                    // Neumarkt am Wallersee and Neumarkt in Steiermark
        assertNoMatch("Lech am Arlberg")             // no rail station
        assertNoMatch("Lech")
        assertNoMatch("Langen")                      // "Langen am Arlberg" is another place than "Langen"
        assertNoMatch("Konzerthaus Wien")            // a venue and a town in one piece: not a town alone
        assertNoMatch("Marienplatz 1, 80331 München, Deutschland")
        assertNoMatch("U3")
        assertNoMatch("Flughafen")
    }

    func testAmbiguityResolvedByPostcodeTown() {
        // "Westbahnhof" alone names several stations; the town decides.
        assertNoMatch("Westbahnhof")
        assertMatch("Westbahnhof, 6020 Innsbruck", "at:47:1189", .station)
    }

    func testMunicipalityWithOneRailStation() {
        let a = Station(id: "x:1", name: "Schwarzach-St. Veit", lat: 47.32, lon: 13.15, state: "S")
        let b = Station(id: "x:2", name: "Feldkirch", lat: 47.24, lon: 9.6, state: "V")
        let c = Station(id: "x:3", name: "Feldkirch Amberg", lat: 47.25, lon: 9.61, state: "V")
        let catalog = CalendarStationCatalog(stations: [a, b, c], municipalities: ["x:1": "Schwarzach im Pongau", "x:2": "Feldkirch",
                                                                                   "x:3": "Feldkirch"])
        let m = CalendarTripMatcher(catalog: catalog)
        XCTAssertEqual(m.match(location: "5620 Schwarzach im Pongau")?.station.id, "x:1")
        XCTAssertEqual(m.match(location: "5620 Schwarzach im Pongau")?.precision, .town)
        // Two rail stations, but one is named like the town.
        XCTAssertEqual(m.match(location: "Feldkirch")?.station.id, "x:2")
        XCTAssertEqual(m.match(location: "Feldkirch Amberg")?.precision, .station)
    }

    /// The matcher builds keys from the normalizer's folded words; they must equal the station list's keys for every name and alias.
    func testKeysFromFoldedWordsEqualStationKeys() {
        for station in CalendarFixtures.stations {
            for name in [station.name] + (station.aliases ?? []) {
                XCTAssertEqual(CalendarStationCatalog.keyWords(folded: StationIndex.foldedWords(name)),
                               CalendarStationCatalog.keyWords(name), name)
            }
        }
        for text in ["Hauptbahnhof Salzburg", "Sankt Pölten Bhf", "Bahnhof St. Anton am Arlberg", "Linz/Donau Hbf (Bstg 3)"] {
            XCTAssertEqual(CalendarStationCatalog.keyWords(folded: StationIndex.foldedWords(text)), CalendarStationCatalog.keyWords(text), text)
        }
    }

    func testCatalogFromThePlaceDatabase() {
        let catalog = CalendarStationCatalog.make(stations: CalendarFixtures.stations, places: PlaceFixtures.index)
        let m = CalendarTripMatcher(catalog: catalog)
        XCTAssertEqual(m.match(location: "Salzburg")?.station.id, "at:45:50002")
        XCTAssertEqual(m.match(location: "Linz Hbf")?.station.id, "at:44:41164")
        XCTAssertNil(m.match(location: "Lech am Arlberg"))
        XCTAssertNil(m.match(location: "Neumarkt"))
    }
}
