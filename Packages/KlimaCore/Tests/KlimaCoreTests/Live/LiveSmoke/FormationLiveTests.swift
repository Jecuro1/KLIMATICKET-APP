// Opt-in, ONE request: does ÖBB's HAFAS answer carry Wagenreihung (formation / coach sequence) data?
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --no-parallel --filter FormationLiveTests
// Request: TripSearch Wien Hbf → Salzburg Hbf (long-distance, rail). The raw response body is scanned for formation
// keys; no response is stored. JourneyDetails is NOT called (it would need a second request).
import Foundation
import XCTest
@testable import KlimaCore

final class FormationLiveTests: XCTestCase {
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
        // Same key-NAME scan as §R6 (KeyScan, recursive, case-insensitive, "information" keys excluded).
        // Prints key names and counts only: no values, no text, no body excerpts.
        let body = HafasLiveTests.recorder.last?.1.body ?? Data()
        let scan = KeyScan.run(body)
        let rideIDs = page.journeys.flatMap(\.rideLegs).compactMap(\.tripID)
        print("FORMATION_LIVE outcome=ok bytes=\(body.count) journeys=\(page.journeys.count) rideTripIDs=\(rideIDs.count) " +
              "jsonOK=\(scan.isJSON) distinctKeys=\(scan.distinctKeys) formationKeyHits=\(scan.matched) " +
              "excludedInformationKeys=\(scan.excludedInformation)")
    }
}
