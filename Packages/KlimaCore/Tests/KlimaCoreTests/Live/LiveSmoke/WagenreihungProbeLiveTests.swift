// Opt-in research probe for docs/OEBB_LIVE.md §R6 (Wagenreihung check). Never part of CI.
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --no-parallel --filter WagenreihungProbeLiveTests
// Hard budget: at most 6 requests to ÖBB. ProbeTransport counts every attempt before it leaves and refuses the 7th.
//   R1 JourneyGeoPos (Zug-Radar, Austria, now): trip ids of several train types in one answer.
//   R2 JourneyDetails, long distance (RJX/RJ/ICE). Not in the answer: TripSearch Wien Hbf → Innsbruck Hbf (now) first.
//   R3 JourneyDetails, EC/IC. Not in the answer: TripSearch Innsbruck Hbf → Bregenz (now) first.
//   R4 JourneyDetails, regional control (REX/R/CJX/S). No fallback.
//   R5 JourneyDetails, Nightjet (NJ/EN). Not in the answer: TripSearch Wien Hbf → Innsbruck Hbf at 21:00 (Vienna) first.
// Only JSON key NAMES are inspected. Values, text and bodies are neither printed nor stored (no recorder.record call).
import Foundation
import XCTest
@testable import KlimaCore

enum ProbeError: Error { case budget }

/// Counts every request attempt before it leaves and refuses anything beyond the cap.
final class ProbeTransport: HTTPTransport, @unchecked Sendable {
    struct Exchange {
        let status: Int
        let body: Data
    }

    static let cap = 6
    private let base: HTTPTransport
    private let lock = NSLock()
    private var attemptCount = 0
    private var stored: [Exchange] = []

    init(_ base: HTTPTransport) { self.base = base }

    var attempts: Int {
        lock.lock()
        defer { lock.unlock() }
        return attemptCount
    }

    var exchanges: [Exchange] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        if attemptCount >= Self.cap {
            lock.unlock()
            throw ProbeError.budget
        }
        attemptCount += 1
        lock.unlock()
        let response = try await base.send(request)
        lock.lock()
        stored.append(Exchange(status: response.status, body: response.body))
        lock.unlock()
        return response
    }
}

/// JSON key NAMES of one answer, matched case-insensitively. Keys containing "information" are counted apart.
enum KeyScan {
    static let terms = ["formation", "sector", "coach", "wagon", "waggon", "carsequence", "prognosedcoach", "wagen"]

    struct Scan {
        var isJSON = false
        var distinctKeys = 0
        var matched: [String] = []
        var excludedInformation = 0
    }

    static func run(_ data: Data) -> Scan {
        var scan = Scan()
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return scan }
        scan.isJSON = true
        var keys = Set<String>()
        collect(root, &keys)
        scan.distinctKeys = keys.count
        for key in keys.sorted() {
            let lower = key.lowercased()
            guard terms.contains(where: { lower.contains($0) }) else { continue }
            if lower.contains("information") {
                scan.excludedInformation += 1
            } else {
                scan.matched.append(key)
            }
        }
        return scan
    }

    private static func collect(_ value: Any, _ keys: inout Set<String>) {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                keys.insert(key)
                collect(child, &keys)
            }
        } else if let list = value as? [Any] {
            for child in list { collect(child, &keys) }
        }
    }
}

/// Trip ids per line category, filled from the radar answer and from TripSearch answers.
final class ProbeState {
    var pool: [String: [String]] = [:]
    var formationKeyNames = Set<String>()

    func pick(_ categories: [String]) -> (cat: String, id: String)? {
        for cat in categories {
            if let id = pool[cat]?.first { return (cat, id) }
        }
        return nil
    }
}

private struct Need {
    let slot: String
    let cats: [String]
    let from: Location?
    let to: Location?
    let when: Date
}

final class WagenreihungProbeLiveTests: XCTestCase {
    static let wien = Location.station(extId: "8100003", name: "Wien Hbf")
    static let pauseNanos: UInt64 = 8_000_000_000

    private func pause() async {
        _ = try? await Task.sleep(nanoseconds: Self.pauseNanos)
    }

    /// Runs one step and prints one WAGEN_PROBE line: HTTP status, byte size and key-name hits of the answer.
    private func step(_ probe: ProbeTransport, _ state: ProbeState, slot: String, label: String,
                      _ call: () async throws -> String) async {
        let attemptsBefore = probe.attempts
        let answersBefore = probe.exchanges.count
        var outcome: String
        do {
            outcome = try await call()
        } catch {
            outcome = "error(\(error))"
        }
        let sent = probe.attempts - attemptsBefore
        guard probe.exchanges.count > answersBefore, let answer = probe.exchanges.last else {
            print("WAGEN_PROBE slot=\(slot) \(label) requestsSent=\(sent) httpAnswer=none outcome=\(outcome)")
            return
        }
        let scan = KeyScan.run(answer.body)
        state.formationKeyNames.formUnion(scan.matched)
        print("WAGEN_PROBE slot=\(slot) \(label) requestsSent=\(sent) httpStatus=\(answer.status) bytes=\(answer.body.count) " +
              "jsonOK=\(scan.isJSON) distinctKeys=\(scan.distinctKeys) formationKeyHits=\(scan.matched) " +
              "excludedInformationKeys=\(scan.excludedInformation) outcome=\(outcome)")
    }

    private func details(_ client: HafasClient, _ probe: ProbeTransport, _ state: ProbeState,
                         slot: String, cat: String, id: String) async {
        await step(probe, state, slot: slot, label: "meth=JourneyDetails category=\(cat)") {
            _ = try await client.trip(id, includePolyline: false)
            return "ok"
        }
    }

    private func search(_ client: HafasClient, _ probe: ProbeTransport, _ state: ProbeState,
                        slot: String, from: Location, to: Location, when: Date) async {
        await step(probe, state, slot: slot, label: "meth=TripSearch from=\(from.name) to=\(to.name)") {
            let page = try await client.journeys(JourneyQuery(origin: from, destination: to, date: when,
                                                              products: .rail, results: 6))
            var added = 0
            for leg in page.journeys.flatMap(\.rideLegs) {
                guard let cat = leg.line?.category, let id = leg.tripID else { continue }
                state.pool[cat, default: []].append(id)
                added += 1
            }
            return "ok journeys=\(page.journeys.count) rideTripIDs=\(added)"
        }
    }

    func testWagenreihungProbe() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        let probe = ProbeTransport(URLSessionTransport())
        let client = HafasClient(config: .default, transport: probe, throttle: RequestThrottle(),
                                 health: LiveHealth(), appVersion: "live-test")
        let state = ProbeState()
        let now = Date()
        let tonight = Calendar.vienna.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now

        // R1: one radar request, Austria, rail, now.
        await step(probe, state, slot: "R1", label: "meth=JourneyGeoPos") {
            let snapshot = try await client.radar(RadarQuery(box: .austria, when: now, products: .rail))
            var counts: [String: Int] = [:]
            for vehicle in snapshot.vehicles {
                let cat = vehicle.line?.category ?? "?"
                counts[cat, default: 0] += 1
                state.pool[cat, default: []].append(vehicle.tripID)
            }
            let summary = counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            return "ok vehicles=\(snapshot.vehicles.count) categories=[\(summary)]"
        }

        let needs = [
            Need(slot: "R2", cats: ["RJX", "RJ", "ICE"], from: Self.wien, to: HafasLiveTests.ibk, when: now),
            Need(slot: "R3", cats: ["EC", "IC"], from: HafasLiveTests.ibk, to: HafasLiveTests.bregenz, when: now),
            Need(slot: "R4", cats: ["REX", "R", "CJX", "S"], from: nil, to: nil, when: now),
            Need(slot: "R5", cats: ["NJ", "EN"], from: Self.wien, to: HafasLiveTests.ibk, when: tonight),
        ]
        for need in needs {
            if let hit = state.pick(need.cats) {
                await pause()
                await details(client, probe, state, slot: need.slot, cat: hit.cat, id: hit.id)
                continue
            }
            guard let from = need.from, let to = need.to else {
                print("WAGEN_PROBE slot=\(need.slot) categories=\(need.cats) notInRadarAnswer noFallback")
                continue
            }
            guard probe.attempts + 2 <= ProbeTransport.cap else {
                print("WAGEN_PROBE slot=\(need.slot) categories=\(need.cats) notInRadarAnswer budgetExhausted")
                continue
            }
            await pause()
            await search(client, probe, state, slot: need.slot + "s", from: from, to: to, when: need.when)
            if let hit = state.pick(need.cats) {
                await pause()
                await details(client, probe, state, slot: need.slot, cat: hit.cat, id: hit.id)
            } else {
                print("WAGEN_PROBE slot=\(need.slot) categories=\(need.cats) notInTripSearchAnswer")
            }
        }

        print("WAGEN_PROBE_SUMMARY requestsSent=\(probe.attempts) cap=\(ProbeTransport.cap) " +
              "formationKeyHits=\(state.formationKeyNames.sorted())")
        XCTAssertLessThanOrEqual(probe.attempts, ProbeTransport.cap)
    }
}
