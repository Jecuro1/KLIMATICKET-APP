// Opt-in, ONE request: does ÖBB's HAFAS answer carry Wagenreihung (formation / coach sequence) data?
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --no-parallel --filter FormationLiveTests
// Request: TripSearch Wien Hbf → Salzburg Hbf (long-distance, rail). The raw response body is scanned for formation
// keys; no response is stored. JourneyDetails is NOT called (it would need a second request).
import Foundation
import XCTest
@testable import KlimaCore

final class FormationLiveTests: XCTestCase {
    // JSON keys only (quoted): plain substrings hit German words such as "Informationen".
    static let keywords = ["formation", "sector", "coach", "wagon", "waggon", "carsequence", "prognosedcoach"]

    func testTripSearchFormationKeywords() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        let wien = Location(lid: "A=1@L=8100003@", kind: .station, extId: "8100003", name: "Wien Hbf")
        let salzburg = Location(lid: "A=1@L=8100108@", kind: .station, extId: "8100108", name: "Salzburg Hbf")
        let query = JourneyQuery(origin: wien, destination: salzburg, date: Date(), products: .rail, results: 3)
        let page: JourneyPage
        do {
            page = try await HafasLiveTests.client.journeys(query)
        } catch {
            print("FORMATION_LIVE outcome=\(error)")
            throw XCTSkip("TripSearch failed: \(error)")
        }
        let body = HafasLiveTests.recorder.last?.1.body ?? Data()
        let text = String(decoding: body, as: UTF8.self)
        let lower = text.lowercased()
        let hits = Self.keywords.filter { lower.contains("\"" + $0) }
        var samples: [String] = []
        for k in hits.prefix(3) {
            if let r = lower.range(of: k) {
                let start = lower.index(r.lowerBound, offsetBy: -60, limitedBy: lower.startIndex) ?? lower.startIndex
                let end = lower.index(r.upperBound, offsetBy: 60, limitedBy: lower.endIndex) ?? lower.endIndex
                samples.append(String(lower[start..<end]).replacingOccurrences(of: "\n", with: " "))
            }
        }
        let rideIDs = page.journeys.flatMap(\.rideLegs).compactMap(\.tripID)
        print("FORMATION_LIVE outcome=ok bytes=\(body.count) journeys=\(page.journeys.count) rideTripIDs=\(rideIDs.count) " +
              "keywordHits=\(hits) samples=\(samples)")
    }
}
