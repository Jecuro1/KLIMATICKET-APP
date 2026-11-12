// Opt-in, ONE-TIME measurement for docs/OEBB_LIVE.md §R11 (Zug-Radar: alle Züge). At most 14 JourneyGeoPos requests per run,
// at least 2 s apart, honest User-Agent, never a retry, everything stops at the first problem (403, 429, any error).
//   KB_LIVE_TESTS=1 KB_RADAR_COVERAGE=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarCoverageLiveTests
// Never part of CI. Two switches on purpose: a plain `--filter LiveSmoke` run must not spend 14 requests.
// Prints counts and structure only (no vehicle list, no trip ids, no names): lines start with RADAR_COVERAGE.
import Foundation
import XCTest
@testable import KlimaCore

/// Counts every request that reaches the wire, keeps at least `minGap` seconds between two, and refuses everything after the
/// first transport error or HTTP error. The client's own retry therefore never reaches the network.
final class BudgetedTransport: HTTPTransport, @unchecked Sendable {
    struct Entry: Sendable {
        var seconds: Double
        var status: Int
        var bytes: Int
        var contentLength: String?
        var contentEncoding: String?
    }

    private let base: HTTPTransport
    let limit: Int
    let minGap: TimeInterval
    private let lock = NSLock()
    private var sent = 0
    private var stopped = false
    private var lastEnd: Date?
    private var _entries: [Entry] = []

    init(_ base: HTTPTransport, limit: Int, minGap: TimeInterval = 2.1) {
        self.base = base
        self.limit = limit
        self.minGap = minGap
    }

    var entries: [Entry] { lock.lock(); defer { lock.unlock() }; return _entries }
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return sent }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// Reserves one request; nil when the budget is spent or a problem stopped the run, else the wait before sending.
    private func reserve() -> TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, sent < limit else { return nil }
        sent += 1
        guard let lastEnd else { return 0 }
        return max(0, minGap - Date().timeIntervalSince(lastEnd))
    }

    private func finish(_ entry: Entry?, problem: Bool) {
        lock.lock(); defer { lock.unlock() }
        lastEnd = Date()
        if let entry { _entries.append(entry) }
        if problem { stopped = true }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let wait = reserve() else { throw LiveError.offline }
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
        let t0 = Date()
        do {
            let response = try await base.send(request)
            let headers = response.headers.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
            finish(Entry(seconds: Date().timeIntervalSince(t0), status: response.status, bytes: response.body.count,
                         contentLength: headers["content-length"], contentEncoding: headers["content-encoding"]),
                   problem: response.status >= 400)
            return response
        } catch {
            finish(nil, problem: true)
            throw error
        }
    }
}

final class RadarCoverageLiveTests: XCTestCase {
    static let budget = 14
    static let cap = 256

    struct Probe {
        var label: String
        var box: RadarBox
        var products: ProductMask
        var maxJny: Int
        var offsetMinutes: Int
        var rawCount: Int
        var vehicles: [RadarVehicle]
        var seconds: Double
        var bytes: Int
        var contentLength: String?
        var contentEncoding: String?
        var status: Int
        var ids: Set<String> { Set(vehicles.map(\.tripID)) }
    }

    private var transport: BudgetedTransport!
    private var client: HafasClient!

    private func micro(_ degrees: Double) -> Int { Int((degrees * 1_000_000).rounded()) }

    /// One JourneyGeoPos request with an explicit `maxJny`, sent as given (the app's builder clamps it to `RadarTiling.requestCap`, 1000).
    private func probe(_ label: String, box: RadarBox, products: ProductMask, maxJny: Int, offsetMinutes: Int = 0) async throws -> Probe {
        let when = Date().addingTimeInterval(Double(offsetMinutes) * 60)
        let request = HafasServiceRequest(meth: "JourneyGeoPos", req: HafasRequests.JourneyGeoPos(
            maxJny: maxJny, onlyRT: false, date: HafasTime.dateString(when), time: HafasTime.timeString(when),
            rect: HafasRequests.Rect(llCrd: HafasRequests.Coord(x: micro(box.west), y: micro(box.south)),
                                     urCrd: HafasRequests.Coord(x: micro(box.east), y: micro(box.north))),
            perSize: 30_000, perStep: 10_000, ageOfReport: true,
            jnyFltrL: [.products(products)], trainPosMode: "CALC"))
        let data = try await client.send([request])
        let entry = transport.entries.last
        let snapshot = try HafasCodec.radar(from: data)
        var raw = snapshot.vehicles.count
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let svc = (json["svcResL"] as? [[String: Any]])?.first,
           let res = svc["res"] as? [String: Any], let list = res["jnyL"] as? [Any] {
            raw = list.count
        }
        let p = Probe(label: label, box: box, products: products, maxJny: maxJny, offsetMinutes: offsetMinutes, rawCount: raw,
                      vehicles: snapshot.vehicles, seconds: entry?.seconds ?? -1, bytes: entry?.bytes ?? data.count,
                      contentLength: entry?.contentLength, contentEncoding: entry?.contentEncoding, status: entry?.status ?? -1)
        let boxText = String(format: "N%.2f W%.2f S%.2f E%.2f", box.north, box.west, box.south, box.east)
        print("RADAR_COVERAGE probe label=\(label) box=[\(boxText)] products=\(products.rawValue) maxJny=\(maxJny) " +
              "offsetMin=\(offsetMinutes) http=\(p.status) ms=\(Int(p.seconds * 1000)) bytes=\(p.bytes) " +
              "contentLength=\(p.contentLength ?? "-") encoding=\(p.contentEncoding ?? "-") rawJny=\(raw) " +
              "vehicles=\(p.vehicles.count) request#\(transport.requestCount)")
        return p
    }

    func testMeasureCoverage() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        guard ProcessInfo.processInfo.environment["KB_RADAR_COVERAGE"] == "1" else { throw XCTSkip("KB_RADAR_COVERAGE=1 not set") }

        var config = LiveConfig.default
        config.hafasFallback = nil   // a fallback profile would be a second request on a PARSE/AUTH answer
        transport = BudgetedTransport(URLSessionTransport(), limit: Self.budget)
        client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(), appVersion: "live-test")

        let vienna = RadarBox(north: 48.32, west: 16.18, south: 48.10, east: 16.58)
        var probes: [Probe] = []
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Vienna")
        f.dateFormat = "EEEE yyyy-MM-dd HH:mm 'Wien'"
        f.locale = Locale(identifier: "en_US_POSIX")
        print("RADAR_COVERAGE start \(f.string(from: Date())) budget=\(Self.budget)")

        do {
            // (a) maxJny 1000, whole Austria, rail: is 256 a hard server cap?
            let a = try await probe("a-austria-max1000", box: .austria, products: .rail, maxJny: 1000)
            probes.append(a)
            let honoured = a.rawCount > Self.cap
            print("RADAR_COVERAGE result(a) maxJny1000 rawJny=\(a.rawCount) aboveCap=\(honoured) hardCap=\(!honoured && a.rawCount == Self.cap)")
            let usedMax = honoured ? 1000 : Self.cap
            let capThreshold = Self.cap   // split while an answer would be cut off at the 256 the app can rely on

            // (b) recursive quad split of the Austria box; leaves below the threshold stop. Reserve 2 requests for (d) and (e).
            var leaves: [(depth: Int, probe: Probe)] = []
            var queue: [(depth: Int, box: RadarBox)] = RadarTiling.quadrants(of: .austria).map { (1, $0) }
            var skippedForBudget = 0
            while !queue.isEmpty {
                let item = queue.removeFirst()
                guard transport.requestCount < Self.budget - 2 else { skippedForBudget += 1; continue }
                let p = try await probe("b-d\(item.depth)", box: item.box, products: .rail, maxJny: usedMax)
                probes.append(p)
                if p.rawCount >= capThreshold, item.depth < 6 {
                    queue.append(contentsOf: RadarTiling.quadrants(of: item.box).map { (item.depth + 1, $0) })
                } else {
                    leaves.append((item.depth, p))
                }
            }
            let atCap = probes.filter { $0.label.hasPrefix("b-") && $0.rawCount >= capThreshold }.count
            let unresolved = skippedForBudget
            let sumLeaves = leaves.reduce(0) { $0 + $1.probe.vehicles.count }
            let allIDs = leaves.flatMap { $0.probe.ids }
            let unique = Set(allIDs).count
            print("RADAR_COVERAGE result(b) leaves=\(leaves.count) leafDepths=\(leaves.map(\.depth)) leafCounts=\(leaves.map { $0.probe.vehicles.count }) " +
                  "probesAtThreshold=\(atCap) boxesNotRequestedForBudget=\(unresolved) sumOfLeafAnswers=\(sumLeaves) uniqueTripIDs=\(unique) " +
                  "duplicatesAcrossLeaves=\(allIDs.count - unique)")

            // (e1) duplicates across neighbouring tiles: ids that occur in two leaves.
            var neighbourPairs = 0
            for i in leaves.indices {
                for j in leaves.indices where j > i {
                    let shared = leaves[i].probe.ids.intersection(leaves[j].probe.ids).count
                    if shared > 0 { neighbourPairs += 1; print("RADAR_COVERAGE dup leaves=\(i),\(j) sharedIDs=\(shared)") }
                }
            }
            print("RADAR_COVERAGE result(e1) leafPairsWithSharedIDs=\(neighbourPairs)")

            // (d) Vienna box, ALL products (bus, tram, metro included).
            let d = try await probe("d-vienna-all", box: vienna, products: .all, maxJny: usedMax)
            probes.append(d)
            let byMode = Dictionary(grouping: d.vehicles) { $0.line?.mode.rawValue ?? "none" }.mapValues(\.count)
            print("RADAR_COVERAGE result(d) vienna all products rawJny=\(d.rawCount) byMode=\(byMode.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })")

            // (e2) a time 60 minutes ahead: accepted? One request, a leaf that was answered below the cap.
            if let reference = leaves.first(where: { $0.probe.vehicles.count > 10 && $0.probe.rawCount < capThreshold })?.probe {
                let future = try await probe("e-future-60min", box: reference.box, products: .rail, maxJny: usedMax, offsetMinutes: 60)
                let same = future.ids.intersection(reference.ids).count
                print("RADAR_COVERAGE result(e2) reference=\(reference.vehicles.count) future=\(future.vehicles.count) sameTripIDs=\(same)")
            }
        } catch {
            print("RADAR_COVERAGE stopped error=\(error) requestsSent=\(transport.requestCount)")
        }
        let totalBytes = transport.entries.reduce(0) { $0 + $1.bytes }
        print("RADAR_COVERAGE done requestsSent=\(transport.requestCount) of \(Self.budget) totalBytes=\(totalBytes) " +
              "statuses=\(Dictionary(grouping: transport.entries, by: \.status).mapValues(\.count).sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })")
        XCTAssertLessThanOrEqual(transport.requestCount, Self.budget)
    }
}
