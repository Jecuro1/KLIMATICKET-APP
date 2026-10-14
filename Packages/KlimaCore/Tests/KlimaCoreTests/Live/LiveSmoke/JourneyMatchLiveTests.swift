// Opt-in: the Zugsuche (HAFAS JourneyMatch) against the real ÖBB HAFAS, at most THREE HTTP requests in total (docs/OEBB_LIVE.md §R9).
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --no-parallel --filter JourneyMatchLiveTests
// Candidates, in order; the test stops after the first one that returns runs: "RJX 66" (high-speed filter), "RJX66"
// (high-speed filter), "66" (rail filter). A refusal by ÖBB (PARSE, HAMM, a codec error) moves on to the next candidate;
// blocks, rate limits, offline and timeouts stop the test. The budget is counted on the wire: a retry counts too.
// Only key names and counts are printed. KB_LIVE_RECORD_DIR=<dir> (outside the repo) keeps the raw body for inspection.
import Foundation
import XCTest
@testable import KlimaCore

/// Counts every HTTP exchange and refuses the one past the budget. Keeps the last exchange for the report.
actor BudgetTransport: HTTPTransport {
    private let base: HTTPTransport
    private let budget: Int
    private(set) var count = 0
    private(set) var last: (HTTPRequest, HTTPResponse, TimeInterval)?

    init(_ base: HTTPTransport, budget: Int) {
        self.base = base
        self.budget = budget
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard count < budget else { throw LiveError.network("Anfrage-Budget im Test erschöpft") }
        count += 1
        let t0 = Date()
        let response = try await base.send(request)
        last = (request, response, Date().timeIntervalSince(t0))
        return response
    }
}

final class JourneyMatchLiveTests: XCTestCase {
    static let budget = 3
    static let enabled = ProcessInfo.processInfo.environment["KB_LIVE_TESTS"] == "1"

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.enabled, "set KB_LIVE_TESTS=1 for live checks")
    }

    func testZugsucheAtMostThreeRequests() async throws {
        var config = LiveConfig.default
        config.hafasFallback = nil          // no second profile: a refusal is one HTTP request, not two
        let transport = BudgetTransport(URLSessionTransport(), budget: Self.budget)
        let client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(),
                                 appVersion: "live-test")
        let candidates = [
            TrainSearchQuery(input: "RJX 66", products: .highSpeed),
            TrainSearchQuery(input: "RJX66", products: .highSpeed),
            TrainSearchQuery(input: "66", products: .rail),
        ]

        candidate: for query in candidates {
            guard await transport.count < Self.budget else { break }
            do {
                let result = try await client.trainRuns(query)
                await report(query, transport, outcome: "ok", runs: result.runs.count)
                if !result.runs.isEmpty { return }
            } catch let error as LiveError {
                await report(query, transport, outcome: "\(error)", runs: nil)
                switch error {
                case .blocked, .rateLimited, .offline, .circuitOpen, .network, .timeout, .disabled, .sessionExpired:
                    break candidate
                default:
                    continue candidate
                }
            }
        }
        throw XCTSkip("ÖBB gab für diese Eingaben keine Fahrt zurück (siehe TRAINSEARCH_LIVE)")
    }

    /// Key names and counts only: no values, no personal data.
    private func report(_ query: TrainSearchQuery, _ transport: BudgetTransport, outcome: String, runs: Int?) async {
        let count = await transport.count
        let last = await transport.last
        let status = last?.1.status ?? -1
        let bytes = last?.1.body.count ?? 0
        let body = last?.1.body ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let svc = (obj?["svcResL"] as? [[String: Any]])?.first
        let res = svc?["res"] as? [String: Any]
        let jny = (res?["jnyL"] as? [[String: Any]])?.first
        let stop = (jny?["stopL"] as? [[String: Any]])?.first
        func keys(_ d: [String: Any]?) -> String { d.map { $0.keys.sorted().joined(separator: ",") } ?? "-" }
        print("TRAINSEARCH_LIVE input=\"\(query.input)\" products=\(query.products.rawValue) outcome=\(outcome) " +
              "http=\(status) bytes=\(bytes) requests=\(count) svcErr=\(svc?["err"] as? String ?? "-") " +
              "runs=\(runs.map(String.init) ?? "-") keysTop=[\(keys(obj))] keysSvc=[\(keys(svc))] keysRes=[\(keys(res))] " +
              "keysJny=[\(keys(jny))] keysStop=[\(keys(stop))]")
        if let dir = ProcessInfo.processInfo.environment["KB_LIVE_RECORD_DIR"], !body.isEmpty {
            let url = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let name = "journeymatch_\(count).response.json"
            try? body.write(to: url.appendingPathComponent(name))
        }
    }
}
