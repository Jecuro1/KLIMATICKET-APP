import XCTest
@testable import KlimaCore

/// Störungen: filter logic (line, Bundesland, validity) and the HimSearch window.
final class DisruptionFeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_796_500)

    private func him(_ id: String, title: String, text: String = "", lines: [String] = [], until: TimeInterval? = nil,
                     modified: TimeInterval = 0) -> Remark {
        Remark(kind: .disruption, id: id, title: title, text: text, validFrom: now.addingTimeInterval(-3600),
               validUntil: until.map { now.addingTimeInterval($0) }, modifiedAt: now.addingTimeInterval(modified), affectedLines: lines)
    }

    private var sample: [Remark] {
        [
            him("1", title: "Bauarbeiten Wien Meidling", text: "Die S 45 fährt zwischen Wien Hbf und Meidling nicht.", lines: ["S 45", "S 80"], modified: -60),
            him("2", title: "Streckensperre Tirol", text: "Zwischen Innsbruck und Landeck Schienenersatzverkehr.", lines: ["RJX 66"], modified: -120),
            him("3", title: "Alte Meldung", text: "Ende.", lines: ["U6"], until: -10, modified: -999),
            Remark(kind: .info, text: "WLAN verfügbar"),
        ]
    }

    func testOnlyDisruptionsAndCurrentByDefault() {
        let ids = DisruptionFilter().apply(sample, now: now).compactMap(\.id)
        XCTAssertEqual(ids, ["1", "2"], "info remarks and expired messages are dropped; newest first")
    }

    func testExpiredShownWhenAsked() {
        let ids = DisruptionFilter(onlyCurrent: false).apply(sample, now: now).compactMap(\.id)
        XCTAssertEqual(ids, ["1", "2", "3"])
    }

    func testLineFilterNormalisesSpacing() {
        XCTAssertEqual(DisruptionFilter(line: "s45").apply(sample, now: now).compactMap(\.id), ["1"])
        XCTAssertEqual(DisruptionFilter(line: "S 80").apply(sample, now: now).compactMap(\.id), ["1"])
        XCTAssertEqual(DisruptionFilter(line: "RJX").apply(sample, now: now).compactMap(\.id), ["2"])
        XCTAssertEqual(DisruptionFilter(line: "  ").apply(sample, now: now).count, 2)
    }

    func testRegionFilterUsesWholeWords() {
        XCTAssertEqual(DisruptionFilter(region: .wien).apply(sample, now: now).compactMap(\.id), ["1"])
        XCTAssertEqual(DisruptionFilter(region: .tirol).apply(sample, now: now).compactMap(\.id), ["2"], "Innsbruck and Landeck")
        XCTAssertEqual(DisruptionFilter(region: .steiermark).apply(sample, now: now), [])
    }

    func testRegionKeywordsRespectUmlauts() {
        let text = " Zwischen St. Pölten und Wiener Neustadt ".normalizedForRegion
        XCTAssertTrue(AustrianRegion.niederoesterreich.matches(normalizedText: text))
        XCTAssertFalse(AustrianRegion.wien.matches(normalizedText: text), "'Wiener' is not 'Wien'")
    }

    func testQueryWindowAndModeFilter() {
        let q = DisruptionFilter(products: .bus).query(now: now, days: 2, maxResults: 40)
        XCTAssertEqual(q.from, now)
        XCTAssertEqual(q.to, now.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(q.products, .bus)
        XCTAssertNil(DisruptionFilter().query(now: now).products, "all modes: no server filter")
    }
}
