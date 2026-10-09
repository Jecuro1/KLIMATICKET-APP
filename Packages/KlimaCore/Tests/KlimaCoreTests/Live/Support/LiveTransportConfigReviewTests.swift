import XCTest
@testable import KlimaCore

/// App files that import KlimaCore and KlimaCloud (both declare `HTTPTransport` / `URLSessionTransport`) use these names.
final class LiveTransportConfigReviewTests: XCTestCase {
    func testUnambiguousTransportNames() {
        let transport: any LiveHTTPTransport = LiveURLSessionTransport()
        XCTAssertTrue(transport is URLSessionTransport)
    }

    /// A shop base URL without a host (remote config typo) is rejected instead of producing unusable request URLs.
    func testShopBaseURLNeedsAHost() throws {
        var c = LiveConfig.default
        c.version = 9
        c.shop.baseURL = try XCTUnwrap(URL(string: "https:shop.oebbtickets.at"))
        XCTAssertNil(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default))
        c.shop.baseURL = try XCTUnwrap(URL(string: "https://shop.oebbtickets.at"))
        XCTAssertNotNil(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default))
    }
}
