import Foundation
import XCTest
@testable import KlimaCore

/// The pure presentation helpers (docs/ENRICH_SPEC.md §2.5) get live HAFAS names and every ref of the data: random
/// refs, names and queries never trap, plates keep their character budget, the plate order is a consistent order.
final class PresentationFuzzTests: XCTestCase {
    static let pieces = ["", " ", "  ", "/", "(", ")", "-", "->", "--->", ".", ",", ":", "–", "ß", "Ö", "ö", "Ä", "é", "e\u{301}",
                         "🚌", "\r\n", "\t", "0", "00", "1", "4", "13A", "110", "852", "40465", "154x", "½", "²",
                         "N", "S", "U", "R", "REX", "RJ", "RJX", "EN", "NJ", "SEV", "SV", "AST", "ALT", "WESTbahn", "Hbf",
                         "Bahnhof", "Skibus", "Schi-Bus", "Wanderbus", "Rufbus", "bahn", "schifffahrt", "Nord", "Süd",
                         "Vorarlberg", "Vbg", "NÖ", "Wien", "St.", "Anton", "am", "Arlberg", "Warth", "Postbus", "GmbH",
                         " AG", ";", "\u{0}", "x"]

    static func random(_ rng: inout SeededRNG, maxPieces: Int = 5) -> String {
        (0..<Int(rng.next() % UInt64(maxPieces + 1))).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }.joined()
    }

    func testRandomLinesNeverTrapAndKeepThePlateBudget() {
        var rng = SeededRNG(seed: 0x5EED_0E11)
        var lines: [LineRef] = []
        for k in 0..<3_000 {
            let mode = LineMode.allCases[Int(rng.next() % UInt64(LineMode.allCases.count))]
            var flags = LineFlags(rawValue: UInt16(truncatingIfNeeded: rng.next()))
            if k % 3 == 0 { flags = [] }
            let line = LineRef(id: "f:\(k)", ref: Self.random(&rng), mode: mode,
                               name: k % 2 == 0 ? Self.random(&rng) : nil, flags: flags,
                               states: ["V", "T", "X", "?"].filter { _ in rng.next() % 2 == 0 })
            lines.append(line)
            let services = PlaceService.allCases.filter { _ in rng.next() % 3 == 0 }
            let kind = LineKind.classify(line, services: services)
            for size in LinePlateText.Size.allCases {
                let plate = LinePlateText.text(for: line, size: size, services: services)
                let cap = kind == .seilbahn || kind == .schiff ? max(size.maxCharacters, 10) : size.maxCharacters
                XCTAssertLessThanOrEqual(plate.text.count, cap, "\(line.ref) \(kind) \(size)")
                XCTAssertFalse(plate.text.contains("…"))
            }
            _ = LinePlateText.dedupeKey(line, services: services)
            _ = SpokenLabels.plate(line, services: services)
            _ = SpokenLabels.lineRow(line, services: services)
            _ = SpokenLabels.departure(line: line, direction: Self.random(&rng), planned: Date(timeIntervalSince1970: 0),
                                       realtime: k % 4 == 0 ? Date(timeIntervalSince1970: .nan) : nil,
                                       now: Date(timeIntervalSince1970: k % 5 == 0 ? .infinity : 600))
            _ = OperatorNames.display(Self.random(&rng))
        }
        for chunk in stride(from: 0, to: lines.count, by: 50) {
            let part = Array(lines[chunk..<min(chunk + 50, lines.count)])
            let sorted = LinePlateOrder.sorted(part)
            XCTAssertEqual(LinePlateOrder.sorted(sorted).map(\.id), sorted.map(\.id), "sorting is idempotent")
            for max in [0, 1, 4] {
                let d = LinePlateOrder.diverse(part, maxCount: max)
                XCTAssertLessThanOrEqual(d.shown.count, max)
                XCTAssertEqual(d.shown.count + d.overflow, sorted.count)
            }
            _ = SpokenLabels.plateRow(sorted, overflow: chunk % 7)
        }
        XCTAssertEqual(SpokenLabels.distance(.nan), "0 Meter")
        XCTAssertEqual(SpokenLabels.distance(-5), "0 Meter")
        XCTAssertFalse(SpokenLabels.distance(.infinity).isEmpty)
    }

    func testNaturalOrderIsAConsistentOrder() {
        var rng = SeededRNG(seed: 0x0DE7)
        let words = (0..<400).map { _ in Self.random(&rng, maxPieces: 3) }
        for i in 0..<words.count {
            let a = words[i], b = words[(i * 7 + 3) % words.count], c = words[(i * 13 + 5) % words.count]
            let ab = LinePlateOrder.naturalCompare(a, b), ba = LinePlateOrder.naturalCompare(b, a)
            XCTAssertEqual(ab, -ba, "antisymmetric: \(a.debugDescription) \(b.debugDescription)")
            if ab < 0, LinePlateOrder.naturalCompare(b, c) < 0 {
                XCTAssertLessThan(LinePlateOrder.naturalCompare(a, c), 0, "transitive: \(a.debugDescription) \(b.debugDescription) \(c.debugDescription)")
            }
        }
    }

    func testTitlesAndHighlightsNeverTrap() {
        var rng = SeededRNG(seed: 0x717E)
        for _ in 0..<3_000 {
            let name = Self.random(&rng, maxPieces: 7), query = Self.random(&rng, maxPieces: 3)
            _ = PlaceTitle.display(name: name, stateShown: rng.next() % 2 == 0, state: rng.next() % 2 == 0 ? "V" : nil)
            _ = PlaceTitle.hero(name: name)
            var last = name.startIndex
            for r in PlaceTitle.highlightRanges(title: name, query: query) {
                XCTAssertGreaterThanOrEqual(r.lowerBound, last)
                XCTAssertLessThanOrEqual(r.upperBound, name.endIndex)
                last = r.upperBound
            }
        }
    }

    func testMarksWithOddTagsNeverTrap() {
        var tags = PlaceTags(skiAreas: [ScoredTag(id: "", confidence: 200, distanceMeters: -1)],
                             regions: [ScoredTag(id: "x", confidence: -5)],
                             types: PlaceType.allCases.map { PlaceTypeTag(type: $0, confidence: 100, distanceMeters: Int.max) },
                             services: PlaceService.allCases,
                             lift: LiftStation(name: "", role: .valley, distanceMeters: Int.min, confidence: 100),
                             accessibility: .limited, nationalPark: ScoredTag(id: "", confidence: 99, distanceMeters: 1_000_000))
        for _ in 0..<2 {
            let marks = PlaceMarkSelection.detailMarks(tags: tags)
            for m in marks { _ = (m.label, m.spoken, m.title) }
            _ = PlaceMarkSelection.rowMark(tags: tags)
            _ = PlaceMarkSelection.heroChips(tags: tags)
            _ = tags.lift?.walkMinutes
            tags.lift?.distanceMeters = Int.max
        }
        XCTAssertFalse(GeoBox(minLat: 48, minLon: 11, maxLat: 47, maxLon: 10).contains(GeoPoint(latitude: 47.5, longitude: 10.5)),
                       "an inverted box contains nothing (and does not trap)")
        XCTAssertFalse(GeoBox(minLat: .nan, minLon: 0, maxLat: 1, maxLon: 1).contains(GeoPoint(latitude: 0.5, longitude: 0.5)))
    }
}
