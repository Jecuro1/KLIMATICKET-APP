import XCTest
@testable import KlimaCore

/// SPEC §C3.2 / §D2 WP-C 5 („LinePresentationTests“; that class name belongs to the enrichment tests): plates delegate
/// to `LinePlateText` (ENRICH_SPEC D7), titles follow §C3.2.
final class LiveLinePresentationTests: XCTestCase {
    static func line(cls: Int, cat: String?, short: String? = nil, long: String? = nil, line: String? = nil, num: String? = nil,
                     name: String, full: String? = nil, lineId: String? = nil) -> Line {
        Line(name: name, fullName: full ?? name, category: cat, categoryShort: short ?? cat, categoryLong: long, lineNumber: line,
             trainNumber: num, lineId: lineId, productClass: cls, mode: HafasCodec.mode(forClass: cls))
    }

    static let rjx = line(cls: 1, cat: "RJX", long: "railjet xpress", num: "19910", name: "RJX 19910", full: "RJX19910")
    static let bus = line(cls: 64, cat: "Bus", long: "Bus", line: "750", num: "47120", name: "Bus 750", lineId: "vvv-1-750")
    static let sBahn = line(cls: 32, cat: "S", short: "s", long: "S-Bahn", line: "4", num: "5123", name: "S 4", full: "S 4 (Zug-Nr. 5123)")
    static let tram = line(cls: 512, cat: "Tram", short: "str", long: "Straßenbahn", line: "5", num: "105222", name: "Tram 5")
    static let u6 = line(cls: 256, cat: "U", long: "U-Bahn", line: "U6", num: "950813", name: "U6")
    static let u6bare = line(cls: 256, cat: "U", long: "U-Bahn", line: "6", name: "U6")
    static let cjx = line(cls: 16, cat: "CJX", long: "cityjet xpress", line: "5", num: "1914", name: "CJX 5", full: "CJX 5 (Zug-Nr. 1914)")
    static let rex = line(cls: 16, cat: "REX", long: "RegionalExpress", line: "51", num: "1628", name: "REX 51", full: "REX 51 (Zug-Nr. 1628)")
    static let nj = line(cls: 8, cat: "NJ", long: "nightjet", num: "466", name: "NJ 466")
    static let wb = line(cls: 4096, cat: "WB", long: "WESTbahn", num: "912", name: "WB 912")
    static let coach = line(cls: 1024, cat: "Bus", short: "FBM", long: "Bus", line: "102806", num: "102819", name: "Bu102806")

    func testPlates() {
        XCTAssertEqual(LinePresentation.plate(Self.rjx), "RJX")
        XCTAssertEqual(LinePresentation.plate(Self.bus), "750")
        XCTAssertEqual(LinePresentation.plate(Self.u6), "U6", "the reference printed „UU6“")
        XCTAssertEqual(LinePresentation.plate(Self.u6bare), "U6")
        // BADGE_SPEC supersedes the §C3.2 table (ENRICH D7): „S4“, „5“, „CJX5“ instead of „S 4“, „T 5“, „CJX 5“.
        XCTAssertEqual(LinePresentation.plate(Self.sBahn), "S4")
        XCTAssertEqual(LinePresentation.plate(Self.tram), "5")
        XCTAssertEqual(LinePresentation.plate(Self.cjx), "CJX5")
        XCTAssertEqual(LinePresentation.plate(Self.rex), "REX51")
        XCTAssertEqual(LinePresentation.plate(Self.nj), "NJ")
        XCTAssertEqual(LinePresentation.plate(Self.nj, size: .s).glyph, .moonStars)
        XCTAssertEqual(LinePresentation.plate(Self.wb), "WB")
        XCTAssertEqual(LinePresentation.plate(Self.coach, size: .s).glyph, .bus, "6-character coach number → glyph only")
        XCTAssertEqual(LinePresentation.kind(Self.rjx), .fern)
        XCTAssertEqual(LinePresentation.kind(Self.nj), .nacht)
        XCTAssertEqual(LinePresentation.kind(Self.cjx), .regio)
        XCTAssertEqual(LinePresentation.kind(Self.sBahn), .sBahn)
        XCTAssertEqual(LinePresentation.kind(Self.u6), .uBahn)
        XCTAssertEqual(LinePresentation.kind(Self.tram), .tram)
        XCTAssertEqual(LinePresentation.kind(Self.bus), .bus)
        let ski = Self.line(cls: 64, cat: "Bus", line: "Skibus", name: "Bus Skibus")
        XCTAssertEqual(LinePresentation.kind(ski), .skibus)
        XCTAssertEqual(LinePresentation.plate(ski), "")
        XCTAssertEqual(LinePresentation.plate(ski, size: .s).glyph, .snowflake)
        XCTAssertEqual(LinePresentation.plate(ski, size: .m).text, "Ski")
    }

    /// AT-C9 (ENRICH): the live plate equals `LinePlateText` of the same line as an offline `LineRef`.
    func testLivePlateEqualsOfflinePlate() {
        let offline: [(Line, LineRef)] = [
            (Self.rjx, LineRef(id: "l:1", ref: "RJX", mode: .rail)),
            (Self.bus, LineRef(id: "l:2", ref: "750", mode: .bus)),
            (Self.sBahn, LineRef(id: "l:3", ref: "S4", mode: .sBahn)),
            (Self.tram, LineRef(id: "l:4", ref: "5", mode: .tram)),
            (Self.u6, LineRef(id: "l:5", ref: "U6", mode: .subway)),
            (Self.cjx, LineRef(id: "l:6", ref: "CJX5", mode: .rail)),
            (Self.rex, LineRef(id: "l:7", ref: "REX 51", mode: .rail)),
            (Self.nj, LineRef(id: "l:8", ref: "NJ 466", mode: .rail)),
        ]
        for (live, ref) in offline {
            for size in LinePlateText.Size.allCases {
                let a = LinePresentation.plate(live, size: size), b = LinePlateText.text(for: ref, size: size)
                XCTAssertEqual(a.text, b.text, "\(live.name) \(size)")
                XCTAssertEqual(a.glyph, b.glyph, "\(live.name) \(size)")
            }
            XCTAssertEqual(LinePresentation.kind(live), ref.kind, live.name)
        }
    }

    func testTitles() {
        XCTAssertEqual(LinePresentation.title(Self.rjx), "RJX 19910")
        XCTAssertEqual(LinePresentation.title(Self.bus), "Bus 750")
        XCTAssertEqual(LinePresentation.title(Self.rex), "REX 51 (Zug-Nr. 1628)")
        XCTAssertEqual(LinePresentation.title(Self.cjx), "CJX 5 (Zug-Nr. 1914)")
        XCTAssertEqual(LinePresentation.title(Self.sBahn), "S 4")
        XCTAssertEqual(LinePresentation.title(Self.tram), "Tram 5")
        XCTAssertEqual(LinePresentation.title(Self.u6), "U6")
        XCTAssertEqual(LinePresentation.title(Self.u6bare), "U6")
        XCTAssertEqual(LinePresentation.title(Self.nj), "NJ 466")
        XCTAssertEqual(LinePresentation.title(Self.wb), "WB 912")
        XCTAssertEqual(LinePresentation.title(Self.line(cls: 16, cat: "REX", line: "1", num: "1", name: "REX 1")), "REX 1")
        XCTAssertEqual(LinePresentation.title(Self.line(cls: 16, cat: "R", num: "5100", name: "R 5100")), "R 5100")
        XCTAssertEqual(LinePresentation.title(Self.line(cls: 64, cat: "Bus", name: "Bus")), "Bus", "never „Bus Bus“")
        XCTAssertEqual(LinePresentation.lineSummary([Self.rjx, Self.bus]), "RJX 19910 · Bus 750")
    }

    /// Plates and titles of every ride leg in the trips goldens and every board row (BADGE_SPEC form, see `VM.badgePlate`).
    func testGoldenPlatesAndTitles() throws {
        var n = 0
        for (vm, scenario) in VM.trips {
            let page = try CoverageFixtures.page(scenario)
            for (j, g) in zip(page.journeys, try VM.connections(vm)) {
                for (leg, gl) in zip(j.legs, try XCTUnwrap(g["legs"] as? [[String: Any]])) where leg.kind == .ride {
                    let product = try XCTUnwrap(gl["product"] as? [String: Any])
                    let line = try XCTUnwrap(leg.line)
                    XCTAssertEqual(LinePresentation.plate(line), VM.badgePlate(product["plate"] as! String, mode: product["mode"] as? String))
                    XCTAssertEqual(LinePresentation.title(line), product["title"] as? String)
                    XCTAssertEqual(line.mode.rawValue, product["mode"] as? String)
                    n += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(n, 18)
    }
}
