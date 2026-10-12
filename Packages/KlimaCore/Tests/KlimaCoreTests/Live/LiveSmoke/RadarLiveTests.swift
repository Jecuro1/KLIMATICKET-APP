// Opt-in: ONE JourneyGeoPos (Zug-Radar) request against the real ÖBB HAFAS (docs/OEBB_LIVE.md §D3, §R2).
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarLiveTests
// Never part of CI. A refusal (PARSE, AUTH, offline …) is reported, not hidden: the test prints the exact outcome.
import Foundation
import XCTest
@testable import KlimaCore

final class RadarLiveTests: XCTestCase {
    func testJourneyGeoPosSingleRequest() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        do {
            let snapshot = try await HafasLiveTests.client.radar(RadarQuery(box: .austria, when: Date(), products: .rail))
            let status = HafasLiveTests.recorder.last?.1.status ?? -1
            print("RADAR_LIVE outcome=ok httpStatus=\(status) vehicles=\(snapshot.vehicles.count) " +
                  "updated=\(snapshot.realtimeUpdatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil") " +
                  "sample=\(snapshot.vehicles.prefix(3).map { "\($0.line?.name ?? "?") → \($0.direction ?? "?")" })")
            try HafasLiveTests.recorder.record("radar_journeygeopos_austria")
        } catch let error as LiveError {
            print("RADAR_LIVE outcome=\(error)")
            throw XCTSkip("ÖBB did not answer JourneyGeoPos: \(error)")
        }
    }
}
