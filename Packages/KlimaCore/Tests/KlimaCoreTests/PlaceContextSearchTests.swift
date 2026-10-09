import Foundation
import XCTest
@testable import KlimaCore

/// WP-C4: search context words (docs/ENRICH_SPEC.md §2.4, AT-C7) on the shipped data. The same rule is in
/// scripts/places_reference.py; the goldens (`contextWords` cases, typing prefixes of "Warth am Arlberg Dorfplatz")
/// check Swift == reference.
final class PlaceContextSearchTests: XCTestCase {
    static let warth = "at:48:344"
    static let warthTown = "osm:n73089810"

    var index: PlaceIndex { PlaceFixtures.index }

    func ids(_ q: String, _ mode: PlaceSearchContext.Mode, _ n: Int = 5) -> [String] {
        index.search(q, context: PlaceSearchContext(mode: mode), limit: 20).prefix(n).map(\.id)
    }

    // MARK: AT-C7

    func testWarthAmArlbergDorfplatz() throws {
        for mode in [PlaceSearchContext.Mode.planner, .tripLog] {
            let rows = index.search("Warth am Arlberg Dorfplatz", context: PlaceSearchContext(mode: mode), limit: 20)
            XCTAssertEqual(rows.first?.id, Self.warth, "\(mode)")
            XCTAssertEqual(rows.first?.name, "Warth (Vorarlberg) Dorfplatz")
            XCTAssertGreaterThanOrEqual(rows[0].score - rows[1].score, 100, "\(mode): #1 ahead of #2 by ≥ 100 points")
            // the row carries what the picker shows: Vorarlberg · Ski Arlberg · 110 · 852 · Skibus
            XCTAssertEqual(rows[0].state, "V")
            XCTAssertEqual(rows[0].tags.primarySkiArea?.id, "ski-arlberg")
            XCTAssertEqual(index.skiArea(id: rows[0].tags.primarySkiArea?.id ?? "")?.name, "Ski Arlberg")
            XCTAssertEqual(rows[0].lines.map(\.ref), ["110", "852", "Skibus"])
            XCTAssertEqual(PlaceTitle.display(name: rows[0].name, stateShown: true), "Warth Dorfplatz")
        }
        // without the context words it was the only hit at 104.2 (prototype); now the area word adds +0.10
        XCTAssertEqual(index.searchRaw("warth am arlberg dorfplatz", context: .planner, limit: 1).first?.score ?? 0, 207.6,
                       accuracy: 0.05)
    }

    func testWarthAmArlberg() throws {
        XCTAssertEqual(ids("warth am arlberg", .tripLog).first, Self.warth)
        let planner = index.search("warth am arlberg", context: .planner, limit: 20)
        XCTAssertEqual(planner.first?.id, Self.warthTown)
        XCTAssertEqual(planner.first?.mainStopID, Self.warth, "Ort Warth taps through to its main stop")
        XCTAssertEqual(planner.dropFirst().first?.id, Self.warth)
    }

    func testPartialAndShortForms() {
        for q in ["warth arlberg", "warth am arlberg dorf", "warth arlb"] {
            XCTAssertTrue(ids(q, .planner, 2).contains(Self.warth), q)
            XCTAssertEqual(ids(q, .tripLog).first, Self.warth, q)
        }
        XCTAssertEqual(ids("warth", .tripLog).first, Self.warth, "unchanged")
    }

    func testStateWords() throws {
        let v = index.search("warth vorarlberg", context: .planner, limit: 20).prefix(5)
        XCTAssertEqual(v.count, 5)
        XCTAssertFalse(v.contains { $0.state == "NÖ" }, "\(v.map(\.name))")
        let noe = index.search("warth niederösterreich", context: .planner, limit: 20).prefix(5)
        XCTAssertEqual(noe.count, 5)
        XCTAssertTrue(noe.allSatisfy { $0.state == "NÖ" }, "\(noe.map(\.name))")
        let tripLog = index.search("warth vorarlberg", context: .tripLog, limit: 20).prefix(5)
        XCTAssertTrue(tripLog.allSatisfy { $0.state == "V" && $0.name.hasPrefix("Warth (Vorarlberg)") })
    }

    func testValleyWords() {
        for (q, prefix) in [("sölden ötztal", "Sölden"), ("mayrhofen zillertal", "Mayrhofen"), ("ischgl paznaun", "Ischgl"),
                            ("zürs am arlberg", "Zürs")] {
            let rows = index.search(q, context: .tripLog, limit: 20).prefix(5)
            XCTAssertEqual(rows.count, 5, q)
            XCTAssertTrue(rows.allSatisfy { $0.name.hasPrefix(prefix) && $0.state == rows.first?.state }, "\(q): \(rows.map(\.name))")
        }
    }

    /// Queries whose area word is part of the name, or that have none, rank as before.
    func testUnchangedQueries() throws {
        for q in ["lech am arlberg", "st anton am arlberg"] {
            let rows = index.search(q, context: .planner, limit: 20).prefix(5)
            XCTAssertTrue(rows.allSatisfy { PlaceNormalizer.fold($0.name).contains("arlberg") },
                          "\(q): every row matches the area word by name (scored as before): \(rows.map(\.name))")
        }
        for q in ["wien hbf", "innsbruck", "lech post", "st anton bahnhof", "wien floridsdorf", "bad gastein", "st johann",
                  "St. Anton"] {
            XCTAssertFalse(try XCTUnwrap(index.table.compile(q)).hasContext, "\(q): no active context word")
        }
        XCTAssertEqual(ids("st anton bahnhof", .tripLog).first, "at:47:1222")
        XCTAssertEqual(ids("wien floridsdorf", .tripLog).first, "at:49:334")
        XCTAssertEqual(ids("wien hbf", .tripLog).first, "at:49:1349")
        let lech = try XCTUnwrap(index.search("lech post", context: .tripLog, limit: 20).first)
        XCTAssertTrue(lech.name.hasPrefix("Lech am Arlberg Post"), lech.name)
        // "bad gastein": the area word names the place itself (no selective other word) – no neighbouring towns
        XCTAssertTrue(index.search("bad gastein", context: .tripLog, limit: 20).prefix(5).allSatisfy { $0.name.hasPrefix("Bad Gastein") })
    }

    /// A context word never brings in places outside its area ("Maria-Theresien-Straße 1 Innsbruck" keeps Innsbruck,
    /// "Hall i.T." no longer lists the Styrian Hall).
    func testContextWordsDoNotAdmitOtherAreas() {
        let hall = index.search("Hall i.T.", context: .planner, limit: 20).prefix(5)
        XCTAssertTrue(hall.allSatisfy { $0.state == "T" }, "\(hall.map(\.name))")
        let mt = index.searchRaw("Maria-Theresien-Straße 1 Innsbruck", context: .planner, limit: 12)
        XCTAssertEqual(mt.first?.name, "Innsbruck Maria-Theresien-Straße")
        XCTAssertFalse(mt.contains { $0.name.hasPrefix("Maria Rain") || $0.name.hasPrefix("Maria Enzersdorf") })
    }

    func testCompiledContextTokens() throws {
        let q = try XCTUnwrap(index.table.compile("warth am arlberg dorfplatz"))
        XCTAssertTrue(q.hasContext)
        XCTAssertEqual(q.raw, ["warth", "am", "arlberg", "dorfplatz"])
        XCTAssertEqual(q.context.map(\.isEmpty), [true, true, false, true])
        XCTAssertNotEqual(q.flags[2] & PlaceTok.optional, 0, "an exact area word is optional for candidate generation")
        let partial = try XCTUnwrap(index.table.compile("warth arlb"))
        XCTAssertFalse(partial.context[1].isEmpty, "a still-typed prefix (≥ 4 letters) of an area word")
        XCTAssertEqual(partial.flags[1] & PlaceTok.optional, 0, "… stays an ordinary word for candidate generation")
        XCTAssertTrue(try XCTUnwrap(index.table.compile("warth arl ")).context.allSatisfy(\.isEmpty), "complete token: exact only")
        let abbrev = try XCTUnwrap(index.table.compile("Lauterach in Vlbg Hasenfeldgasse"))
        XCTAssertFalse(abbrev.context[2].isEmpty, "Vlbg → vorarlberg (state abbreviation)")
        XCTAssertTrue(try XCTUnwrap(index.table.compile("Hintertux Gletscher")).context.allSatisfy(\.isEmpty),
                      "generic words never become context words")
        XCTAssertFalse(try XCTUnwrap(index.table.compile("innsbruck innsbruck")).hasContext,
                       "a repeated word is a name word again (each query word needs its own name word)")
    }

    // MARK: vocabulary and sets

    func testVocabularyAndSets() throws {
        let ctx = try XCTUnwrap(index.table.context)
        XCTAssertGreaterThan(ctx.terms.count, 300)
        XCTAssertEqual(ctx.terms, ctx.terms.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
        for t in ["arlberg", "bregenzerwald", "otztal", "zillertal", "paznaun", "vorarlberg", "vbg", "tirol", "wien"] {
            XCTAssertTrue(ctx.terms.contains(t), t)
        }
        for g in ["ski", "skigebiet", "arena", "region", "see", "tal", "gletscher", "wiener"] { XCTAssertFalse(ctx.terms.contains(g), g) }
        XCTAssertEqual(PlaceContextVocabulary.words("SkiWelt Wilder Kaiser – Brixental"), ["skiwelt", "wilder", "kaiser", "brixental"])
        XCTAssertEqual(PlaceContextVocabulary.words("Ski Arlberg"), ["arlberg"])
        XCTAssertEqual(PlaceContextVocabulary.words("Silvretta Arena"), ["silvretta"])
        XCTAssertTrue(ctx.sets.allSatisfy { !$0.isEmpty && $0 == $0.sorted() })

        let arlberg = try XCTUnwrap(ctx.lookup(raw: "arlberg", canonical: "arlberg", partial: false).sets.first)
        let warthRi = try XCTUnwrap(index.table.byID[Self.warth]), townRi = try XCTUnwrap(index.table.byID[Self.warthTown])
        XCTAssertTrue(ctx.contains(arlberg, warthRi))
        XCTAssertTrue(ctx.contains(arlberg, townRi), "towns through their main stop")
        XCTAssertFalse(ctx.contains(arlberg, try XCTUnwrap(index.table.byID["at:48:187"])), "St. Anton im Montafon")
        let v = try XCTUnwrap(ctx.lookup(raw: "vlbg", canonical: "vorarlberg", partial: false))
        XCTAssertTrue(v.exact)
        XCTAssertTrue(v.sets.contains { ctx.contains($0, warthRi) })
        XCTAssertFalse(v.sets.contains { ctx.contains($0, try! XCTUnwrap(index.table.byID["at:43:30742"])) }, "Warth/NÖ")
        XCTAssertFalse(ctx.lookup(raw: "arl", canonical: "arl", partial: true).exact)
        XCTAssertTrue(ctx.lookup(raw: "arl", canonical: "arl", partial: true).sets.isEmpty, "prefixes need ≥ 4 letters")
        let prefix = ctx.lookup(raw: "arlb", canonical: "arlb", partial: true)
        XCTAssertFalse(prefix.exact)
        XCTAssertEqual(prefix.sets.map { ctx.terms[Int($0)] }, ["arlberg"])
        XCTAssertTrue(ctx.lookup(raw: "arlb", canonical: "arlb", partial: false).sets.isEmpty)
    }

    /// Without enrichment data (v1 files) there are no context words and the ranking is the v1 ranking.
    func testNoContextWithoutTags() throws {
        let dir = PlaceFixtures.dir.appendingPathComponent("v2/v1")
        let idx = try PlaceIndex(placesURL: dir.appendingPathComponent("places.bin"),
                                 localitiesURL: dir.appendingPathComponent("localities.bin"))
        XCTAssertNil(idx.table.context)
        XCTAssertFalse(try XCTUnwrap(idx.table.compile("warth vorarlberg")).hasContext)
        XCTAssertEqual(idx.search("warth am arlberg dorfplatz", context: .tripLog, limit: 3).first?.id, Self.warth)
    }
}

/// AT-C8: the context checks keep a keystroke cheap (release gate in CI, step "Place search performance").
final class PlaceContextSearchPerformanceTests: XCTestCase {
    static let queries = ["warth am arlberg dorfplatz", "warth am arlberg", "warth vorarlberg", "sölden ötztal",
                          "mayrhofen zillertal", "ischgl paznaun", "zürs am arlberg", "hall i.t.", "lauterach in vlbg",
                          "warth arlb"]

    func testTenContextQueries() {
        let index = PlaceFixtures.index
        for q in Self.queries { _ = index.search(q, context: .planner, limit: 20) }
        var best = Double.infinity
        for _ in 0..<5 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            for q in Self.queries { _ = index.search(q, context: .planner, limit: 20) }
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        print(String(format: "[places] 10 context-word queries: %.2f ms (best of 5)", best))
        #if DEBUG
        XCTAssertLessThan(best, 2_000)
        #else
        XCTAssertLessThan(best, 10, "10 context-word queries (the 100-query gate allows 0.5 ms per query)")
        #endif
    }
}
