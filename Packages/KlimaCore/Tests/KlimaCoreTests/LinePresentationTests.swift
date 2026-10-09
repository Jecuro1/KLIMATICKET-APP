import Foundation
import XCTest
@testable import KlimaCore

/// WP-C3 presentation helpers (docs/ENRICH_SPEC.md §2.5, AT-C4/AT-C6 presentation parts, BADGE_SPEC §2.1/§3/§5).
final class LinePresentationTests: XCTestCase {
    private var n = 0
    private func line(_ ref: String, _ mode: LineMode, flags: LineFlags = [], name: String? = nil, net: TransitNetwork? = nil,
                      op: String? = nil, states: [String] = [], from: String? = nil, to: String? = nil,
                      sources: LineSources = .timetable, synthetic: Bool = false) -> LineRef {
        n += 1
        return LineRef(id: "l:\(n)", ref: ref, mode: mode, network: net, operatorName: op, name: name,
                       termini: from == nil && to == nil ? nil : LineTermini(from: from, to: to), flags: flags,
                       states: states, sources: sources, isSynthetic: synthetic)
    }

    private func plate(_ l: LineRef, _ size: LinePlateText.Size = .s) -> String { LinePlateText.text(for: l, size: size).text }

    // MARK: LineKind

    func testClassification() {
        let cases: [(LineRef, LineKind)] = [
            (line("RJX", .rail), .fern), (line("RJ 255", .rail), .fern), (line("ICE 21", .rail), .fern),
            (line("ECE", .rail), .fern), (line("EC 163", .rail), .fern), (line("IC", .rail), .fern),
            (line("D 300", .rail), .fern), (line("TGV", .rail), .fern), (line("WB", .rail), .fern),
            (line("WESTbahn", .rail), .fern),
            (line("NJ 466", .rail), .nacht), (line("EN 40465", .rail, flags: .night), .nacht),
            (line("R 2345", .rail, flags: .night), .nacht),
            (line("REX 41", .rail), .regio), (line("CJX9", .rail), .regio), (line("R5", .rail), .regio),
            (line("RE 4", .rail), .regio), (line("RB 6/S6", .rail), .regio), (line("STB", .rail), .regio),
            (line("S4", .rail), .sBahn), (line("S", .rail), .sBahn), (line("S45", .sBahn), .sBahn),
            (line("U4", .subway), .uBahn), (line("D", .tram), .tram), (line("1", .tram), .tram),
            (line("O1", .trolleybus), .bus), (line("852", .bus), .bus), (line("13A", .bus), .bus),
            (line("N25", .bus), .nachtbus), (line("40", .bus, flags: .night), .nachtbus),
            (line("Skibus", .bus, flags: [.ski, .winter]), .skibus), (line("4", .bus, name: "Schibus Lech"), .skibus),
            (line("Ski-Bus", .bus), .skibus),
            (line("581", .bus, flags: .onDemand), .rufbus), (line("Rufbus", .bus), .rufbus),
            (line("AST 8", .bus), .rufbus), (line("612", .bus, name: "Anrufsammeltaxi Pitztal"), .rufbus),
            (line("412", .bus, name: "Bus 412: Wanderbus Kaunertal"), .wanderbus), (line("Almbus", .bus), .wanderbus),
            (line("SV400", .bus), .sev), (line("SEV", .bus), .sev), (line("4150", .bus, flags: .railReplacement), .sev),
            (line("SV400", .railReplacement), .sev),
            (line("Hungerburgbahn", .cable), .seilbahn), (line("Achenseeschifffahrt", .ship), .schiff),
            (line("581", .onDemand), .rufbus), (line("Fernbus Graz - Wien", .other), .sonst),
        ]
        for (l, k) in cases { XCTAssertEqual(l.kind, k, l.ref) }
        // AST / ALT only as whole words
        XCTAssertEqual(line("Pasta", .bus).kind, .bus)
        XCTAssertEqual(line("320", .bus, name: "Altenmarkt – Radstadt").kind, .bus)
        // stop services classify only lines without a number of their own
        XCTAssertEqual(LineKind.classify(line("852", .bus), services: [.hikingBus]), .bus)
        XCTAssertEqual(LineKind.classify(line("Bus", .bus), services: [.hikingBus]), .wanderbus)
        XCTAssertEqual(LineKind.classify(line("110", .bus), services: [.skiBus]), .bus, "Warth: 110 stays a bus")
    }

    func testFamilyRankAndSpokenNoun() {
        XCTAssertEqual(LineKind.allCases.map(\.familyRank), Array(0..<15))
        XCTAssertEqual(LineKind.bus.spokenNoun, "Bus")
        XCTAssertEqual(LineKind.sBahn.spokenNoun, "S-Bahn")
        XCTAssertEqual(LineKind.skibus.spokenNoun, "Skibus")
        XCTAssertEqual(LineKind.rufbus.spokenNoun, "Rufbus")
        XCTAssertEqual(LineMode.subway.transportMode, .metro)
        XCTAssertEqual(LineMode.railReplacement.transportMode, .bus)
        XCTAssertEqual(LineMode.cable.transportMode, .cableCar)
        XCTAssertEqual(line("852", .bus, net: .vvv).key, "VVV|bus|852")
        XCTAssertEqual(LineMode(keyName: "sev"), .railReplacement)
    }

    // MARK: LinePlateText (§2.5 table, BADGE_SPEC §2.1 rules 1–6)

    func testPlateTexts() {
        XCTAssertEqual(plate(line("EN 40465", .rail, flags: .night)), "EN")
        XCTAssertEqual(LinePlateText.text(for: line("EN 40465", .rail, flags: .night), size: .s).glyph, .moonStars)
        XCTAssertEqual(plate(line("EN40406", .rail)), "EN")
        XCTAssertEqual(plate(line("RJ 255", .rail)), "RJ")
        XCTAssertEqual(plate(line("WESTbahn", .rail)), "WB")
        XCTAssertEqual(plate(line("REX 41", .rail)), "REX41")
        XCTAssertEqual(plate(line("RB 6/S6", .rail)), "S6")
        XCTAssertEqual(plate(line("REX 154x", .rail)), "REX")
        XCTAssertEqual(plate(line("S 4", .sBahn)), "S4")
        XCTAssertEqual(plate(line("4", .sBahn)), "S4")
        XCTAssertEqual(plate(line("Regionalzug", .rail)), "R")
        XCTAssertEqual(plate(line("9773/5", .bus)), "9773")
        XCTAssertEqual(plate(line("611/847", .bus)), "611")
        XCTAssertEqual(plate(line("13A", .bus)), "13A")
        XCTAssertEqual(plate(line("4150", .bus)), "4150")
        XCTAssertEqual(plate(line("N25", .bus)), "N25")
        XCTAssertNil(LinePlateText.text(for: line("N25", .bus), size: .s).glyph, "no moon when the plate says N")
        XCTAssertEqual(LinePlateText.text(for: line("40", .bus, flags: .night), size: .s).glyph, .moonStars)
        XCTAssertEqual(plate(line("SV400", .railReplacement)), "SV400")
        XCTAssertEqual(plate(line("U4", .subway)), "U4")
        XCTAssertEqual(plate(line("D", .tram)), "D")

        let ski = line("Skibus", .bus, flags: [.ski, .winter])
        for size in [LinePlateText.Size.xs, .s] {
            let p = LinePlateText.text(for: ski, size: size)
            XCTAssertEqual(p.text, "")
            XCTAssertEqual(p.glyph, .snowflake)
        }
        for size in [LinePlateText.Size.m, .l] {
            let p = LinePlateText.text(for: ski, size: size)
            XCTAssertEqual(p.text, "Ski")
            XCTAssertEqual(p.glyph, .snowflake)
        }
        XCTAssertEqual(LinePlateText.text(for: line("581", .bus, flags: .onDemand), size: .s).text, "581")
        XCTAssertEqual(LinePlateText.text(for: line("581", .bus, flags: .onDemand), size: .s).glyph, .phone)
        XCTAssertEqual(LinePlateText.text(for: line("Wanderbus", .bus), size: .m).text, "Wander")

        XCTAssertEqual(plate(line("Shuttlebus", .bus), .l), "Shuttle")
        XCTAssertEqual(LinePlateText.text(for: line("Shuttlebus", .bus), size: .s).glyph, .bus, "7 > 5: glyph only")
        XCTAssertEqual(plate(line("Shuttlebus", .bus), .s), "")
        XCTAssertEqual(plate(line("Klinik-Bus", .bus), .m), "Klinik")
        XCTAssertEqual(plate(line("Fernbus Graz - Wien", .bus), .l), "Fernbus")

        XCTAssertEqual(plate(line("Hungerburgbahn", .cable), .l), "Hungerburg")
        XCTAssertEqual(LinePlateText.text(for: line("Hungerburgbahn", .cable), size: .s).text, "")
        XCTAssertEqual(LinePlateText.text(for: line("Hungerburgbahn", .cable), size: .s).glyph, .cableCar)
        XCTAssertEqual(plate(line("Achenseeschifffahrt", .ship), .l), "Achensee")
        XCTAssertEqual(plate(line("Twin City Liner", .ship), .l), "Twin City")
        XCTAssertEqual(plate(line("Nord", .ship, name: "Attersee Schifffahrt Nord"), .l), "Attersee N")
    }

    /// Rule 6: never longer than the size allows, never an ellipsis.
    func testPlateBudget() {
        let refs: [(String, LineMode)] = [("EN 40465", .rail), ("REX 154x", .rail), ("Fernbus Graz - Wien", .bus),
                                          ("Shuttlebus", .bus), ("Hungerburgbahn", .cable), ("Twin City Liner", .ship),
                                          ("123456789", .bus), ("Schienenersatzverkehr", .railReplacement),
                                          ("Kitzbüheler Hornbahn", .cable), ("Wörthersee Schifffahrt", .ship)]
        for (ref, mode) in refs {
            for size in LinePlateText.Size.allCases {
                let p = LinePlateText.text(for: line(ref, mode), size: size)
                let budget = (mode == .cable || mode == .ship) && (size == .m || size == .l) ? 10 : size.maxCharacters
                XCTAssertLessThanOrEqual(p.text.count, budget, "\(ref) \(size)")
                XCTAssertFalse(p.text.contains("…"), ref)
                XCTAssertTrue(!p.text.isEmpty || p.glyph != nil, "\(ref) \(size): text or glyph")
            }
        }
    }

    // MARK: LinePlateOrder

    func testNaturalOrder() {
        XCTAssertEqual(["852", "110", "13A", "4"].sorted(by: LinePlateOrder.naturalLess), ["4", "13A", "110", "852"])
        XCTAssertEqual(["S45", "S", "S1", "S7"].sorted(by: LinePlateOrder.naturalLess), ["S", "S1", "S7", "S45"])
        XCTAssertTrue(LinePlateOrder.naturalLess("U1", "U6"))
        XCTAssertFalse(LinePlateOrder.naturalLess("110", "110"))
    }

    /// AT-C4 (presentation part): Warth's compact lines [110, 852, Skibus] in display order, kinds and plates.
    func testWarthCompactRow() {
        let lines = [line("Skibus", .bus, flags: [.ski, .winter], sources: .osm), line("852", .bus, flags: .schoolDaysUncertain),
                     line("110", .bus, op: "Postbus")]
        let ordered = LinePlateOrder.sorted(lines, services: [.skiBus])
        XCTAssertEqual(ordered.map(\.ref), ["110", "852", "Skibus"])
        XCTAssertEqual(ordered.map { LineKind.classify($0, services: [.skiBus]) }, [.bus, .bus, .skibus])
        let plates = ordered.map { LinePlateText.text(for: $0, size: .s, services: [.skiBus]) }
        XCTAssertEqual(plates.map(\.text), ["110", "852", ""])
        XCTAssertEqual(plates.map(\.glyph), [nil, nil, .snowflake])
        XCTAssertEqual(SpokenLabels.plateRow(ordered), "Linien: Bus 110, Bus 852, Skibus")
        let d = LinePlateOrder.diverse(lines, maxCount: 4)
        XCTAssertEqual(d.shown.map(\.ref), ["110", "852", "Skibus"])
        XCTAssertEqual(d.overflow, 0)
    }

    /// AT-C6: St. Anton rail categories (M6) dedupe with the OSM „RJ“ and „EN 40465“, fixed long-distance order.
    func testStAntonRailCategories() {
        var lines = [line("270", .bus, flags: .schoolDaysUncertain), line("760", .bus), line("SV400", .railReplacement, flags: .railReplacement),
                     line("EN 40465", .rail, flags: .night, sources: .osm), line("RJ", .rail, sources: .osm),
                     line("6", .bus, sources: .osm)]
        for cat in ["RJX", "RJ", "ICE", "EC", "IC", "EN", "NJ", "D"] { lines.append(line(cat, .rail, synthetic: true)) }
        let ordered = LinePlateOrder.sorted(lines)
        let texts = ordered.map { LinePlateText.text(for: $0, size: .m).text }
        XCTAssertEqual(texts, ["RJX", "RJ", "ICE", "EC", "IC", "D", "EN", "NJ", "6", "270", "760", "SV400"])
        XCTAssertEqual(ordered.filter { $0.ref == "RJ" }.count, 1)
        XCTAssertFalse(ordered.first { $0.ref.hasPrefix("RJ") && $0.ref.count == 2 }!.isSynthetic,
                       "the first (OSM) RJ wins over the synthetic one")
        XCTAssertEqual(ordered.first { LinePlateText.text(for: $0, size: .m).text == "EN" }?.ref, "EN 40465")
    }

    /// AT-C6: Floridsdorf (BADGE_SPEC §2.1 example, v1 line list with modes) → REX S U6 25 + overflow.
    func testFloridsdorfDiverse() {
        var lines = ["REX", "CJX", "R", "REX"].map { line($0, .rail) } + [line("S", .rail), line("U6", .subway)]
        lines += ["25", "26", "30", "31"].map { line($0, .tram) }
        lines += ["150", "151", "29A", "29B", "33A", "34A", "500", "501", "502", "505", "850", "G3"].map { line($0, .bus) }
        let d = LinePlateOrder.diverse(lines, maxCount: 4)
        XCTAssertEqual(d.shown.map { LinePlateText.text(for: $0, size: .s).text }, ["REX", "S", "U6", "25"])
        XCTAssertEqual(d.overflow, 21 - 4, "21 distinct plates (REX twice in the v1 list)")
        XCTAssertGreaterThan(d.overflow, 0)
        // the round-robin prefix property: fewer slots keep the most diverse families
        XCTAssertEqual(LinePlateOrder.diverse(lines, maxCount: 2).shown.map(\.ref), ["REX", "S"])
        XCTAssertEqual(LinePlateOrder.diverse(lines, maxCount: 0).overflow, 21)
        // with the real v2 lines (E1 aside): one plate per family, express first, S before S1
        let v2 = ["CJX9", "R1", "R3", "REX1", "REX2"].map { line($0, .rail) } + ["S1", "S2"].map { line($0, .sBahn) }
            + [line("S", .rail, sources: .osm), line("U6", .subway)] + ["5", "25"].map { line($0, .tram) }
            + ["29A", "N20"].map { line($0, .bus) }
        XCTAssertEqual(LinePlateOrder.diverse(v2, maxCount: 4).shown.map(\.ref), ["REX1", "S", "U6", "5"])
        XCTAssertEqual(LinePlateOrder.diverse(v2, maxCount: 6).shown.map(\.ref), ["REX1", "S", "U6", "5", "29A", "N20"])
    }

    // MARK: PlaceTitle

    func testPlaceTitle() {
        XCTAssertEqual(PlaceTitle.display(name: "Warth (Vorarlberg) Dorfplatz", stateShown: true), "Warth Dorfplatz")
        XCTAssertEqual(PlaceTitle.display(name: "Warth (Vorarlberg) Dorfplatz", stateShown: false),
                       "Warth (Vorarlberg) Dorfplatz")
        XCTAssertEqual(PlaceTitle.display(name: "Lechen (Grafendorf) Fink", stateShown: true), "Lechen (Grafendorf) Fink")
        XCTAssertEqual(PlaceTitle.display(name: "St.Anton am Arlberg Bahnhof", stateShown: true), "St. Anton am Arlberg Bahnhof")
        XCTAssertEqual(PlaceTitle.display(name: "Steeg (Tirol) Gemeindeamt", stateShown: true, state: "T"), "Steeg Gemeindeamt")
        XCTAssertEqual(PlaceTitle.display(name: "Steeg (Tirol) Gemeindeamt", stateShown: true, state: "V"),
                       "Steeg (Tirol) Gemeindeamt", "only the stop's own state folds")
        XCTAssertEqual(PlaceTitle.display(name: "Lauterach (Vlbg.) Hasenfeldgasse", stateShown: true), "Lauterach Hasenfeldgasse")
        XCTAssertEqual(PlaceTitle.display(name: "Kleinmariazell (NÖ)", stateShown: true), "Kleinmariazell")
        XCTAssertEqual(PlaceTitle.display(name: "Amstetten ---> Fa Avenarius", stateShown: false), "Amstetten Fa Avenarius")
        let hero = PlaceTitle.hero(name: "St.Anton am Arlberg Bahnhof")
        XCTAssertEqual(hero.title, "St. Anton am Arlberg")
        XCTAssertEqual(hero.droppedStationWord, "Bahnhof")
        XCTAssertEqual(PlaceTitle.hero(name: "Innsbruck Hbf").title, "Innsbruck")
        XCTAssertEqual(PlaceTitle.hero(name: "Warth (Vorarlberg) Dorfplatz").title, "Warth Dorfplatz")
        XCTAssertNil(PlaceTitle.hero(name: "Bahnhof").droppedStationWord, "never an empty title")
    }

    func testHighlightRanges() {
        func bold(_ title: String, _ q: String) -> [String] {
            PlaceTitle.highlightRanges(title: title, query: q).map { String(title[$0]) }
        }
        XCTAssertEqual(bold("Warth Dorfplatz", "warth"), ["Warth"])
        XCTAssertEqual(bold("Warth Dorfplatz", "warth dorf"), ["Warth", "Dorf"])
        XCTAssertEqual(bold("St. Pölten Hbf", "st pol"), ["St", "Pöl"])
        XCTAssertEqual(bold("St. Poelten Hbf", "pol"), ["Poel"])
        XCTAssertEqual(bold("Innsbruck Hbf", "xyz"), [])
        XCTAssertEqual(bold("Innsbruck Hbf", ""), [])
    }

    // MARK: OperatorNames

    func testOperatorNames() {
        XCTAssertEqual(OperatorNames.display("Österreichische Postbus AG"), "Postbus")
        XCTAssertEqual(OperatorNames.display("Österreichische Postbus Aktiengesellschaft"), "Postbus")
        XCTAssertEqual(OperatorNames.display("OEBB Personenverkehr AG Kundenservice"), "ÖBB")
        XCTAssertEqual(OperatorNames.display("ÖBB-Personenverkehr AG"), "ÖBB")
        XCTAssertEqual(OperatorNames.display("Wiener Linien GmbH & Co KG"), "Wiener Linien")
        XCTAssertEqual(OperatorNames.display("Innsbrucker Verkehrsbetriebe und Stubaitalbahn GmbH"), "IVB")
        XCTAssertEqual(OperatorNames.display("Linz Linien GmbH"), "Linz AG Linien")
        XCTAssertEqual(OperatorNames.display("Salzburg AG"), "Salzburg AG")
        XCTAssertEqual(OperatorNames.display("Ötztaler Verkehrsgesellschaft mbH"), "Ötztaler Verkehrsgesellschaft")
        XCTAssertEqual(OperatorNames.display("Landbus Bregenzerwald"), "Landbus Bregenzerwald")
        XCTAssertEqual(OperatorNames.display("Österreichische Postbus AG;Frank Reisen"), "Postbus / Frank Reisen")
        XCTAssertEqual(OperatorNames.display("  "), "")
    }

    // MARK: SpokenLabels (BADGE_SPEC §5)

    func testSpokenPlates() {
        let cases: [(LineRef, String)] = [
            (line("852", .bus), "Bus 852"), (line("S45", .sBahn), "S-Bahn S45"), (line("U4", .subway), "U-Bahn-Linie U4"),
            (line("D", .tram), "Straßenbahn D"), (line("RJX", .rail), "Railjet Xpress"),
            (line("NJ 466", .rail), "Nightjet"), (line("EN 40465", .rail, flags: .night), "Euronight"),
            (line("REX 41", .rail), "Regionalexpress 41"), (line("N25", .bus), "Nachtbus N25"),
            (line("Skibus", .bus, flags: .ski), "Skibus"), (line("412", .bus, name: "Wanderbus Kaunertal"), "Wanderbus 412"),
            (line("581", .bus, flags: .onDemand), "Rufbus 581, nur auf Bestellung"),
            (line("SV400", .railReplacement), "Schienenersatzverkehr SV400"),
            (line("Hungerburgbahn", .cable), "Seilbahn Hungerburgbahn"),
            (line("Achenseeschifffahrt", .ship), "Schiff Achenseeschifffahrt"),
            (line("9773/5", .bus), "Bus 9773/5"), (line("S", .rail), "S-Bahn"),
        ]
        for (l, s) in cases { XCTAssertEqual(SpokenLabels.plate(l), s, l.ref) }
        XCTAssertEqual(SpokenLabels.plateRow([line("110", .bus), line("852", .bus), line("Skibus", .bus, flags: .ski)],
                                             overflow: 5), "Linien: Bus 110, Bus 852, Skibus, und 5 weitere")
        XCTAssertEqual(SpokenLabels.plateRow([line("110", .bus)]), "Linie: Bus 110")
        XCTAssertEqual(SpokenLabels.plateRow([]), "Keine Linien bekannt")
    }

    /// AT-U4 string: the Warth search row label.
    func testStopRowLabel() {
        let warth = Place(id: "at:48:344", kind: .stop, name: "Warth (Vorarlberg) Dorfplatz",
                          coordinate: GeoPoint(latitude: 47.2577, longitude: 10.1823), products: .bus, state: "V",
                          municipality: "Warth")
        let tags = PlaceTags(skiAreas: [ScoredTag(id: "ski-arlberg", confidence: 95, distanceMeters: 77)],
                             services: [.skiBus])
        let lines = LinePlateOrder.sorted([line("110", .bus), line("852", .bus), line("Skibus", .bus, flags: [.ski, .winter])])
        XCTAssertEqual(SpokenLabels.stopRow(place: warth, tags: tags, lines: lines, skiAreaName: "Ski Arlberg"),
                       "Warth (Vorarlberg) Dorfplatz, Bushaltestelle, Vorarlberg, Skigebiet Ski Arlberg, Linien: Bus 110, Bus 852, Skibus")
        XCTAssertEqual(SpokenLabels.stopRow(place: warth, lines: [], isFavourite: true, distanceMeters: 1240),
                       "Warth (Vorarlberg) Dorfplatz, Bushaltestelle, Vorarlberg, Favorit, 1,2 Kilometer")
        XCTAssertEqual(SpokenLabels.stateMark("V"), "Bundesland Vorarlberg")
        XCTAssertEqual(SpokenLabels.skiArea("Ski Arlberg"), "Skigebiet Ski Arlberg")
        XCTAssertEqual(SpokenLabels.bezirk("Favoriten", wienBezirk: 10), "10. Bezirk, Favoriten")
    }

    func testLineRowAndDeparture() {
        let l110 = line("110", .bus, net: .vvt, op: "Postbus", states: ["V", "T"])
        XCTAssertEqual(SpokenLabels.lineRow(l110, from: "Reutte Bahnhof", to: "Lech Schlosskopf"),
                       "Bus 110, von Reutte Bahnhof nach Lech Schlosskopf, Postbus, Tirol und Vorarlberg")
        let en = line("EN 40465", .rail, flags: .night, states: ["K", "S", "T", "V", "X"], from: "Zürich HB", to: "Zagreb")
        XCTAssertEqual(SpokenLabels.lineRow(en), "Euronight, von Zürich HB nach Zagreb, Kärnten, Salzburg, Tirol und Vorarlberg")

        let tz = TimeZone(identifier: "Europe/Vienna")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 14, minute: 32))!
        let planned = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 14, minute: 38))!
        let l852 = line("852", .bus)
        XCTAssertEqual(SpokenLabels.departure(line: l852, direction: "Lech Schlosskopf", planned: planned, realtime: planned,
                                              now: now, timeZone: tz),
                       "Bus 852 nach Lech Schlosskopf, in 6 Minuten, um 14:38, Echtzeit")
        XCTAssertEqual(SpokenLabels.departure(line: l852, direction: "Lech Schlosskopf", planned: planned,
                                              realtime: planned.addingTimeInterval(180), now: now, timeZone: tz),
                       "Bus 852 nach Lech Schlosskopf, in 9 Minuten, um 14:41, 3 Minuten verspätet")
        XCTAssertEqual(SpokenLabels.departure(line: l852, direction: "Lech Schlosskopf", planned: planned, now: now, timeZone: tz),
                       "Bus 852 nach Lech Schlosskopf, in 6 Minuten, um 14:38, laut Fahrplan")
        XCTAssertEqual(SpokenLabels.departure(line: l852, direction: "Lech Schlosskopf", planned: planned, isCancelled: true,
                                              now: now, timeZone: tz),
                       "Bus 852 nach Lech Schlosskopf, um 14:38, fällt aus")
        XCTAssertEqual(SpokenLabels.departure(line: l852, direction: "Lech", planned: now.addingTimeInterval(65), now: now,
                                              timeZone: tz), "Bus 852 nach Lech, in 1 Minute, um 14:33, laut Fahrplan")
        XCTAssertEqual(SpokenLabels.departure(line: line("581", .bus, flags: .onDemand), direction: "Jerzens", planned: planned,
                                              now: now, timeZone: tz),
                       "Rufbus 581 nach Jerzens, in 6 Minuten, um 14:38, laut Fahrplan")
    }

    // MARK: PlaceMarkSelection

    func testRowMarkPriority() {
        let stAnton = PlaceTags(skiAreas: [ScoredTag(id: "ski-arlberg", confidence: 92, distanceMeters: 9)],
                                types: [PlaceTypeTag(type: .trainStation, confidence: 98),
                                        PlaceTypeTag(type: .longDistance, confidence: 95),
                                        PlaceTypeTag(type: .nightTrain, confidence: 92),
                                        PlaceTypeTag(type: .parkAndRide, confidence: 72, distanceMeters: 28)],
                                accessibility: .yes)
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: stAnton)?.kind, .nachtzug)
        let warth = PlaceTags(lift: LiftStation(name: "Dorfbahn Warth", role: .valley, liftType: "gondola",
                                                distanceMeters: 77, confidence: 97))
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: warth)?.kind, .talstation)
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: warth)?.label, "Talstation Dorfbahn Warth · 77 m")
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: warth)?.spoken, "Talstation Dorfbahn Warth, 77 Meter")
        var far = warth
        far.lift?.distanceMeters = 650
        XCTAssertNil(PlaceMarkSelection.rowMark(tags: far))
        let airport = PlaceTags(types: [PlaceTypeTag(type: .mainStation, confidence: 99),
                                        PlaceTypeTag(type: .airport, confidence: 90, distanceMeters: 120)])
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: airport)?.kind, .flughafen)
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: PlaceTags(types: [PlaceTypeTag(type: .airport, confidence: 65)])),
                       nil, "below 70 no badge")
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: PlaceTags(accessibility: .limited)), nil)
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: PlaceTags(accessibility: .yes))?.kind, .barrierefrei)
        XCTAssertNil(PlaceMarkSelection.rowMark(tags: .empty))
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: PlaceTags(types: [PlaceTypeTag(type: .parkAndRide, confidence: 80,
                                                                                    distanceMeters: 28)]))?.spoken,
                       "Park and Ride, 28 Meter")
    }

    func testDetailMarksAndHeroChips() {
        let stAnton = PlaceTags(skiAreas: [ScoredTag(id: "ski-arlberg", confidence: 92, distanceMeters: 9)],
                                types: [PlaceTypeTag(type: .trainStation, confidence: 98),
                                        PlaceTypeTag(type: .longDistance, confidence: 95),
                                        PlaceTypeTag(type: .nightTrain, confidence: 92),
                                        PlaceTypeTag(type: .parkAndRide, confidence: 72, distanceMeters: 28)],
                                accessibility: .yes)
        XCTAssertEqual(PlaceMarkSelection.detailMarks(tags: stAnton).map(\.kind),
                       [.bahnhof, .fernverkehr, .nachtzug, .parkAndRide, .barrierefrei])
        XCTAssertEqual(PlaceMarkSelection.heroChips(tags: stAnton).map(\.label), ["P+R · 28 m", "barrierefrei"])
        let warth = PlaceTags(skiAreas: [ScoredTag(id: "ski-arlberg", confidence: 95, distanceMeters: 77)],
                              services: [.skiBus],
                              lift: LiftStation(name: "Dorfbahn Warth", role: .valley, distanceMeters: 77, confidence: 97))
        XCTAssertEqual(PlaceMarkSelection.detailMarks(tags: warth).map(\.kind), [.talstation, .skibus])
        XCTAssertEqual(PlaceMarkSelection.heroChips(tags: warth), [], "valley station is in the ski-pass card")
        let hbf = PlaceTags(types: [PlaceTypeTag(type: .mainStation, confidence: 99), PlaceTypeTag(type: .trainStation, confidence: 99),
                                    PlaceTypeTag(type: .hospital, confidence: 75)],
                            services: [.airportLink], accessibility: .limited)
        let marks = PlaceMarkSelection.detailMarks(tags: hbf)
        XCTAssertEqual(marks.map(\.kind), [.hauptbahnhof, .flughafen, .barrierefrei, .krankenhaus])
        XCTAssertEqual(marks.first { $0.kind == .barrierefrei }?.title, "teilweise barrierefrei")
    }

    func testAreaMarksAndBrandSeam() {
        let warth = Place(id: "at:48:344", kind: .stop, name: "Warth (Vorarlberg) Dorfplatz",
                          coordinate: GeoPoint(latitude: 47.2577, longitude: 10.1823), state: "V", municipality: "Warth")
        let tags = PlaceTags(gkz: 80239, skiAreas: [ScoredTag(id: "ski-arlberg", confidence: 95, distanceMeters: 77)],
                             regions: [ScoredTag(id: "bregenzerwald", confidence: 90), ScoredTag(id: "arlberg", confidence: 92)])
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: warth, tags: tags), .skiArea(id: "ski-arlberg"))
        var noSki = tags
        noSki.skiAreas = []
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: warth, tags: noSki), .region(id: "arlberg"), "highest confidence")
        noSki.regions = [ScoredTag(id: "wiener-alpen", confidence: 75)]
        XCTAssertNil(PlaceMarkSelection.rowAreaMark(place: warth, tags: noSki), "regions need 80")

        struct FakeBrands: AreaBrandProviding {
            func rowBrandID(for q: AreaBrandQuery) -> String? { q.skiArea?.id == "ski-arlberg" ? "ski_arlberg" : nil }
            func heroBrandIDs(for q: AreaBrandQuery) -> [String] {
                q.gkz == "80239" ? ["ski_arlberg", "warth_schroecken", "ski_arlberg", "bregenzerwald"] : []
            }
        }
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: warth, tags: tags, brands: FakeBrands()), .brand(id: "ski_arlberg"))
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: warth, tags: noSki, brands: FakeBrands()), nil,
                       "no brand → own fallback (none here)")
        XCTAssertEqual(PlaceMarkSelection.heroAreaCells(place: warth, tags: tags, brands: FakeBrands()),
                       [.brand(id: "ski_arlberg"), .brand(id: "warth_schroecken")])
        XCTAssertEqual(PlaceMarkSelection.heroAreaCells(place: warth, tags: tags, brands: nil), [])
        let q = PlaceMarkSelection.areaBrandQuery(place: warth, tags: tags)
        XCTAssertEqual(q.gkz, "80239")
        XCTAssertEqual(q.state, "V")
        XCTAssertEqual(q.names, ["Warth (Vorarlberg) Dorfplatz"])

        let ski = SkiArea(id: "ski-arlberg", name: "Ski Arlberg", shortName: "Arlberg", hue: "enzian", monogram: "ARL")
        let names = ["arlberg": "Arlberg", "bregenzerwald": "Bregenzerwald"]
        XCTAssertEqual(PlaceMarkSelection.detailRegions(tags: tags, skiArea: ski, regionName: { names[$0] }).map(\.id),
                       ["bregenzerwald"], "Arlberg next to Ski Arlberg is dropped")
    }

    // MARK: StopKindLabel

    func testStopKindLabel() {
        func p(_ name: String, _ kind: PlaceKind, _ products: PlaceProducts, muni: String? = nil) -> Place {
            Place(id: "x", kind: kind, name: name, coordinate: GeoPoint(latitude: 47, longitude: 11), products: products,
                  state: "T", municipality: muni)
        }
        XCTAssertEqual(StopKindLabel.label(place: p("Warth (Vorarlberg) Dorfplatz", .stop, .bus)), "Bushaltestelle")
        XCTAssertEqual(StopKindLabel.label(place: p("St.Anton am Arlberg Bahnhof", .station, [.highSpeed, .bus])), "Bahnhof")
        XCTAssertEqual(StopKindLabel.label(place: p("Innsbruck Hbf", .station, [.highSpeed])), "Hauptbahnhof")
        XCTAssertEqual(StopKindLabel.label(place: p("X", .stop, .bus),
                                           tags: PlaceTags(types: [PlaceTypeTag(type: .mainStation, confidence: 95)])),
                       "Hauptbahnhof")
        XCTAssertEqual(StopKindLabel.label(place: p("Stephansplatz", .stop, [.subway, .bus])), "U-Bahn")
        XCTAssertEqual(StopKindLabel.label(place: p("Oper", .stop, [.tram, .bus])), "Straßenbahn")
        XCTAssertEqual(StopKindLabel.label(place: p("Pertisau", .stop, .ship)), "Schiffsanlegestelle")
        XCTAssertEqual(StopKindLabel.label(place: p("Hungerburg", .stop, .onDemandOrCable)), "Seilbahn")
        XCTAssertEqual(StopKindLabel.label(place: p("Warth", .town, [])), "Ort")
        let tags = PlaceTags(types: [PlaceTypeTag(type: .trainStation, confidence: 98),
                                     PlaceTypeTag(type: .longDistance, confidence: 95),
                                     PlaceTypeTag(type: .nightTrain, confidence: 92)])
        XCTAssertEqual(StopKindLabel.eyebrow(place: p("St.Anton am Arlberg Bahnhof", .station, .highSpeed), tags: tags),
                       "BAHNHOF · FERNVERKEHR & NACHTZUG")
        XCTAssertEqual(StopKindLabel.eyebrow(place: p("Warth (Vorarlberg) Dorfplatz", .stop, .bus, muni: "Warth")),
                       "BUSHALTESTELLE · GEMEINDE WARTH")
    }

    func testTagHelpers() {
        let lift = LiftStation(name: "Dorfbahn Warth", role: .valley, distanceMeters: 77, confidence: 97)
        XCTAssertEqual(lift.walkMinutes, 1)
        XCTAssertEqual(LiftStation(name: "x", role: .top, distanceMeters: 161, confidence: 80).walkMinutes, 3)
        XCTAssertNil(LiftStation(name: "x", role: .top, confidence: 80).walkMinutes)
        let t = PlaceTags(skiAreas: [ScoredTag(id: "a", confidence: 65), ScoredTag(id: "ski-arlberg", confidence: 95)])
        XCTAssertEqual(t.primarySkiArea?.id, "ski-arlberg")
        XCTAssertTrue(t.showsSnowcap)
        XCTAssertFalse(PlaceTags(skiAreas: [ScoredTag(id: "a", confidence: 85)]).showsSnowcap)
        XCTAssertEqual(PlaceTags.empty.klimaTicket.status, .valid)
    }
}
