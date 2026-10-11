import Foundation
import KlimaCore

/// Deterministic offline stand-ins for CI screenshots and previews (`-KBDemo`): the network is never touched.
struct DemoTimetableService: TimetableService {
    func locations(_ query: String, types: LocationTypes, maxResults: Int) async throws -> [Location] { [] }
    func nearby(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) async throws -> [Location] { [] }
    func journeys(_ query: JourneyQuery) async throws -> JourneyPage { throw LiveError.noConnection }
    func journeys(batch queries: [JourneyQuery]) async throws -> [Result<JourneyPage, LiveError>] { queries.map { _ in .failure(.noConnection) } }
    func refresh(_ refreshToken: String, includeStopovers: Bool, includePolyline: Bool) async throws -> Journey { throw LiveError.noConnection }
    func refresh(batch refreshTokens: [String]) async throws -> [Result<Journey, LiveError>] { refreshTokens.map { _ in .failure(.noConnection) } }
    func trip(_ tripID: String, includePolyline: Bool) async throws -> TripDetails { throw LiveError.noConnection }
    func board(_ query: BoardQuery) async throws -> Board { Board(kind: query.kind, entries: []) }
    func remarks(_ query: RemarksQuery) async throws -> [Remark] { [] }
}

struct DemoPriceProvider: LivePriceProvider {
    func livePrice(_ request: PriceRequest) async throws -> PriceQuote { throw LiveError.noPrice("Demo") }
}
