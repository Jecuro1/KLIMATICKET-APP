// Opt-in, approved by the owner: ONE JourneyDetails request on a long-distance train, to check for Wagenreihung data.
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --no-parallel --filter JourneyDetailsFormationLiveTests
// Prerequisite: one TripSearch Wien Hbf → Salzburg Hbf to obtain a trip id (no id was stored from the earlier search).
// Total ÖBB requests in this test: 2 (TripSearch + JourneyDetails). Raw bodies are scanned, nothing is stored.
import Foundation
import XCTest
@testable import KlimaCore

final class JourneyDetailsFormationLiveTests: XCTestCase {
    func testJourneyDetailsFormationKeys() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        let wien = Location(lid: "A=1@L=8100003@", kind: .station, extId: "8100003", name: "Wien Hbf")
        let salzburg = Location(lid: "A=1@L=8100108@", kind: .station, extId: "8100108", name: "Salzburg Hbf")
        let page = try await HafasLiveTests.client.journeys(JourneyQuery(origin: wien, destination: salzburg, date: Date(), products: .rail, results: 3))
        // Long-distance first (RJX/RJ/EC/IC), else any ride with a trip id.
        let rides = page.journeys.flatMap(\.rideLegs).filter { $0.tripID != nil }
        let longDistance = rides.first { ($0.line?.productClass ?? 0) & ProductMask.highSpeed.union(.intercity).rawValue != 0 }
        guard let tripID = (longDistance ?? rides.first)?.tripID else {
            print("FORMATION_JD outcome=no_trip_id")
            throw XCTSkip("TripSearch returned no ride with a trip id")
        }
        do {
            _ = try await HafasLiveTests.client.trip(tripID, includePolyline: false)
        } catch {
            print("FORMATION_JD outcome=\(error)")
            throw XCTSkip("JourneyDetails failed: \(error)")
        }
        // Same key-NAME scan as §R6 (KeyScan): key names and counts only, no values or body excerpts.
        let body = HafasLiveTests.recorder.last?.1.body ?? Data()
        let scan = KeyScan.run(body)
        print("FORMATION_JD outcome=ok bytes=\(body.count) line=\(longDistance?.line?.name ?? "?") " +
              "jsonOK=\(scan.isJSON) distinctKeys=\(scan.distinctKeys) formationKeyHits=\(scan.matched) " +
              "excludedInformationKeys=\(scan.excludedInformation)")
    }
}
