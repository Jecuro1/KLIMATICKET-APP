// Opt-in, ONE-TIME measurement for docs/RADAR_TIMETRAVEL.md §R12 (Radar-Zeitreise). At most 6 JourneyGeoPos requests per run
// (a baseline for now, then +60, +180, -30 and +720 minutes: 5 are used), at least 2 s apart, honest User-Agent, never a retry, everything
// stops at the first 403 or 429.
//   KB_LIVE_TESTS=1 KB_RADAR_TIME=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarTimeLiveTests/testMeasureTimeTravel
// Never part of CI. Two switches on purpose: a plain `--filter LiveSmoke` run must not spend these requests.
// Prints counts and distances only (no vehicle list, no trip ids, no names): lines start with RADAR_TIME.
//   KB_RADAR_TIME_RAW_DIR=<dir outside the repository> additionally keeps the raw answers there, so the analysis can be repeated offline:
//   KB_RADAR_TIME_ANALYSE_DIR=<same dir> swift test ... --filter RadarTimeLiveTests/testAnalyseSavedAnswers   (no request)
import Foundation
import XCTest
@testable import KlimaCore

final class RadarTimeLiveTests: XCTestCase {
    static let budget = 6
    static let offsets = [0, 60, 180, -30, 720]

    struct Frame {
        var offset: Int
        var when: Date
        var http: Int
        var ms: Int
        var bytes: Int
        var rawCount: Int
        var snapshot: RadarSnapshot?
        var error: String?
    }

    private func micro(_ degrees: Double) -> Int { Int((degrees * 1_000_000).rounded()) }

    private func request(_ when: Date) -> HafasServiceRequest<HafasRequests.JourneyGeoPos> {
        let box = RadarBox.austria
        return HafasServiceRequest(meth: "JourneyGeoPos", req: HafasRequests.JourneyGeoPos(
            maxJny: 1000, onlyRT: false, date: HafasTime.dateString(when), time: HafasTime.timeString(when),
            rect: HafasRequests.Rect(llCrd: HafasRequests.Coord(x: micro(box.west), y: micro(box.south)),
                                     urCrd: HafasRequests.Coord(x: micro(box.east), y: micro(box.north))),
            perSize: 30_000, perStep: 10_000, ageOfReport: true,
            jnyFltrL: [.products(.rail)], trainPosMode: "CALC"))
    }

    func testMeasureTimeTravel() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        guard ProcessInfo.processInfo.environment["KB_RADAR_TIME"] == "1" else { throw XCTSkip("KB_RADAR_TIME=1 not set") }
        let rawDir = ProcessInfo.processInfo.environment["KB_RADAR_TIME_RAW_DIR"].map { URL(fileURLWithPath: $0) }
        if let rawDir { try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true) }

        var config = LiveConfig.default
        config.hafasFallback = nil   // a fallback profile would be a second request on a PARSE/AUTH answer
        let transport = BudgetedTransport(URLSessionTransport(), limit: Self.budget)
        let client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(), appVersion: "live-test")

        let start = Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Vienna")
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm 'Wien'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        print("RADAR_TIME start \(formatter.string(from: start)) budget=\(Self.budget)")

        var frames: [Frame] = []
        for offset in Self.offsets {
            let when = start.addingTimeInterval(Double(offset) * 60)
            let before = transport.requestCount
            var frame = Frame(offset: offset, when: when, http: -1, ms: -1, bytes: 0, rawCount: 0, snapshot: nil, error: nil)
            do {
                let data = try await client.send([request(when)])
                let entry = transport.entries.last
                frame.http = entry?.status ?? -1
                frame.ms = Int((entry?.seconds ?? -1) * 1000)
                frame.bytes = entry?.bytes ?? data.count
                frame.snapshot = try HafasCodec.radar(from: data)
                frame.rawCount = frame.snapshot?.answeredCount ?? 0
                if let rawDir {
                    try data.write(to: rawDir.appendingPathComponent("probe-\(offset).json"))
                    let meta: [String: Any] = ["offset": offset, "when": when.timeIntervalSince1970, "http": frame.http, "ms": frame.ms, "bytes": frame.bytes]
                    try JSONSerialization.data(withJSONObject: meta).write(to: rawDir.appendingPathComponent("probe-\(offset).meta.json"))
                }
            } catch {
                let entry = transport.entries.last
                frame.http = transport.requestCount > before ? (entry?.status ?? -1) : -1
                frame.ms = Int((entry?.seconds ?? -1) * 1000)
                frame.bytes = entry?.bytes ?? 0
                frame.error = "\(error)"
                if let rawDir, transport.requestCount > before {
                    let meta: [String: Any] = ["offset": offset, "when": when.timeIntervalSince1970, "http": frame.http, "ms": frame.ms, "bytes": frame.bytes, "error": "\(error)"]
                    try? JSONSerialization.data(withJSONObject: meta).write(to: rawDir.appendingPathComponent("probe-\(offset).meta.json"))
                }
            }
            frames.append(frame)
            Self.printProbe(frame, requestNumber: transport.requestCount)
            if transport.isStopped { print("RADAR_TIME stopped after an HTTP error, no further request"); break }
        }
        Self.analyse(frames)
        print("RADAR_TIME done requestsSent=\(transport.requestCount) of \(Self.budget) totalBytes=\(transport.entries.reduce(0) { $0 + $1.bytes }) " +
              "statuses=\(Dictionary(grouping: transport.entries, by: \.status).mapValues(\.count).sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" })")
        XCTAssertLessThanOrEqual(transport.requestCount, Self.budget)
    }

    /// Repeats the analysis on answers kept by an earlier run. Sends nothing.
    func testAnalyseSavedAnswers() throws {
        guard let path = ProcessInfo.processInfo.environment["KB_RADAR_TIME_ANALYSE_DIR"] else { throw XCTSkip("KB_RADAR_TIME_ANALYSE_DIR not set") }
        let dir = URL(fileURLWithPath: path)
        var frames: [Frame] = []
        for offset in Self.offsets {
            let metaURL = dir.appendingPathComponent("probe-\(offset).meta.json")
            guard let metaData = try? Data(contentsOf: metaURL),
                  let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: Any] else { continue }
            var frame = Frame(offset: offset, when: Date(timeIntervalSince1970: meta["when"] as? Double ?? 0), http: meta["http"] as? Int ?? -1,
                              ms: meta["ms"] as? Int ?? -1, bytes: meta["bytes"] as? Int ?? 0, rawCount: 0, snapshot: nil, error: meta["error"] as? String)
            if frame.error == nil, let data = try? Data(contentsOf: dir.appendingPathComponent("probe-\(offset).json")) {
                frame.snapshot = try HafasCodec.radar(from: data)
                frame.rawCount = frame.snapshot?.answeredCount ?? 0
            }
            frames.append(frame)
            Self.printProbe(frame, requestNumber: frames.count)
        }
        Self.analyse(frames)
    }

    // MARK: Output (counts and distances only)

    static func printProbe(_ frame: Frame, requestNumber: Int) {
        guard let snapshot = frame.snapshot else {
            print("RADAR_TIME probe offsetMin=\(frame.offset) http=\(frame.http) ms=\(frame.ms) bytes=\(frame.bytes) error=\(frame.error ?? "?") request#\(requestNumber)")
            return
        }
        var stops = 0, stopsReported = 0, vehiclesReported = 0, vehiclesLate = 0, notStarted = 0, notStartedAtFirstStop = 0, ended = 0, noSchedule = 0
        var fourStops = 0, shapeOriginLastNextDestination = 0
        for vehicle in snapshot.vehicles {
            if vehicle.stopovers.count == 4 {
                fourStops += 1
                // The window: the origin (a departure only), the stop last left, the stop heading for, the destination (an arrival only).
                let s = vehicle.stopovers
                let leftLast = (s[1].departure?.effective ?? s[1].arrival?.effective).map { $0 <= frame.when.addingTimeInterval(1) } ?? false
                let headingNext = (s[2].arrival?.effective ?? s[2].departure?.effective).map { $0 >= frame.when.addingTimeInterval(-1) } ?? false
                if s[0].arrival == nil, s[0].departure != nil, s[3].departure == nil, s[3].arrival != nil, leftLast, headingNext {
                    shapeOriginLastNextDestination += 1
                }
            }
            let schedule = RadarSchedule(vehicle)
            guard schedule.isProjectable else { noSchedule += 1; continue }
            stops += vehicle.stopovers.count
            let reported = vehicle.stopovers.filter { $0.arrival?.hasRealtime == true || $0.departure?.hasRealtime == true }
            stopsReported += reported.count
            if !reported.isEmpty { vehiclesReported += 1 }
            if reported.contains(where: { ($0.arrival?.delaySeconds ?? $0.departure?.delaySeconds ?? 0) >= 60 }) { vehiclesLate += 1 }
            if let first = schedule.firstDeparture, first > frame.when.addingTimeInterval(60) {
                notStarted += 1
                if vehicle.coordinate.distanceKm(to: schedule.stops[0].coordinate) <= RadarProjection.anchorAtStopKm { notStartedAtFirstStop += 1 }
            }
            if let last = schedule.lastArrival, last < frame.when.addingTimeInterval(-60) { ended += 1 }
        }
        let age = snapshot.realtimeUpdatedAt.map { Int(frame.when.timeIntervalSince($0)) }
        print("RADAR_TIME probe offsetMin=\(frame.offset) http=\(frame.http) ms=\(frame.ms) bytes=\(frame.bytes) rawJny=\(frame.rawCount) vehicles=\(snapshot.vehicles.count) " +
              "stopsPerVehicleExactlyFour=\(fourStops) windowOriginLastNextDestination=\(shapeOriginLastNextDestination) " +
              "stops=\(stops) stopsWithRealtime=\(stopsReported) vehiclesWithRealtime=\(vehiclesReported) vehiclesWithDelay1minPlus=\(vehiclesLate) " +
              "firstDepartureAfterFrameTime=\(notStarted) ofWhichAtFirstStop=\(notStartedAtFirstStop) lastArrivalBeforeFrameTime=\(ended) noSchedule=\(noSchedule) " +
              "planrtTSageAtFrameTimeSec=\(age.map(String.init) ?? "nil") request#\(requestNumber)")
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        return sorted[min(Int((Double(sorted.count - 1) * p).rounded()), sorted.count - 1)]
    }

    static func describe(_ label: String, _ errors: [Double]) {
        guard !errors.isEmpty else { print("RADAR_TIME projection \(label) n=0"); return }
        let within1 = Double(errors.filter { $0 <= 1 }.count) / Double(errors.count)
        let within5 = Double(errors.filter { $0 <= 5 }.count) / Double(errors.count)
        print(String(format: "RADAR_TIME projection %@ n=%d medianKm=%.2f p90Km=%.2f p99Km=%.2f maxKm=%.1f within1km=%.0f%% within5km=%.0f%%",
                     label, errors.count, percentile(errors, 0.5), percentile(errors, 0.9), percentile(errors, 0.99), errors.max() ?? 0, within1 * 100, within5 * 100))
    }

    /// Calibrates the projection against the server's own positions at the other times: the trips that are in two frames (counts and
    /// kilometres only), and the hold-out test of the timeline's interpolation: the middle frame predicted from its two neighbours.
    static func analyse(_ frames: [Frame]) {
        let usable = frames.filter { $0.snapshot != nil }.sorted { $0.offset < $1.offset }
        guard let base = usable.first(where: { $0.offset == 0 }), let baseSnapshot = base.snapshot else { return }
        let baseIDs = Set(baseSnapshot.vehicles.map(\.tripID))
        for frame in usable where frame.offset != 0 {
            let ids = Set(frame.snapshot?.vehicles.map(\.tripID) ?? [])
            print("RADAR_TIME overlap offsetMin=\(frame.offset) tripsAlsoInBaseline=\(ids.intersection(baseIDs).count) tripsOnlyInThisFrame=\(ids.subtracting(baseIDs).count) tripsOnlyInBaseline=\(baseIDs.subtracting(ids).count)")
        }
        // Projection of the baseline forward to the other frames' times, against the server's position there.
        for frame in usable where frame.offset > 0 {
            guard let snapshot = frame.snapshot else { continue }
            let truth = Dictionary(snapshot.vehicles.map { ($0.tripID, $0) }, uniquingKeysWith: { first, _ in first })
            var withAnchor: [Double] = [], timetableOnly: [Double] = []
            var ended = 0, missing = 0
            for vehicle in baseSnapshot.vehicles {
                guard let real = truth[vehicle.tripID] else { continue }
                let schedule = RadarSchedule(vehicle)
                guard schedule.isProjectable else { continue }
                let anchor = RadarProjection.validatedAnchor(for: schedule, time: base.when, coordinate: vehicle.coordinate)
                guard let projected = RadarProjection.position(of: schedule, anchor: anchor, at: frame.when) else { ended += 1; continue }
                withAnchor.append(projected.coordinate.distanceKm(to: real.coordinate))
                if let plain = RadarProjection.position(of: schedule, anchor: nil, at: frame.when) {
                    timetableOnly.append(plain.coordinate.distanceKm(to: real.coordinate))
                } else { missing += 1 }
            }
            describe("forward-from-baseline offsetMin=\(frame.offset) anchored", withAnchor)
            describe("forward-from-baseline offsetMin=\(frame.offset) timetableOnly", timetableOnly)
            print("RADAR_TIME projection forward-from-baseline offsetMin=\(frame.offset) projectedAsEnded=\(ended) timetableOnlyHadNoPosition=\(missing)")
        }
        // Hold-out: predict one frame from the others with the timeline (the stops of all answers merged, each answer's position a point of the path).
        func holdout(_ label: String, predict: Frame, from known: [Frame]) {
            guard let target = predict.snapshot, known.allSatisfy({ $0.snapshot != nil }) else { return }
            var timeline = RadarTimeline()
            for frame in known {
                timeline.addFrame(frame.snapshot?.vehicles ?? [], time: frame.when, fetchedAt: base.when, isComplete: false)
            }
            let knownIDs = known.map { Set($0.snapshot?.vehicles.map(\.tripID) ?? []) }
            var errors: [Double] = [], missing = 0, inAll = 0
            for vehicle in target.vehicles where knownIDs.allSatisfy({ $0.contains(vehicle.tripID) }) {
                inAll += 1
                guard let pin = timeline.pin(for: vehicle.tripID, at: predict.when) else { missing += 1; continue }
                errors.append(pin.coordinate.distanceKm(to: vehicle.coordinate))
            }
            describe("holdout \(label)", errors)
            print("RADAR_TIME projection holdout \(label) tripsInAllFrames=\(inAll) notOnMapAtThatTime=\(missing)")
        }
        let by = Dictionary(uniqueKeysWithValues: usable.map { ($0.offset, $0) })
        if let zero = by[0], let back = by[-30], let ahead = by[60] { holdout("offsetMin=0 from [-30,+60]", predict: zero, from: [back, ahead]) }
        if let zero = by[0], let middle = by[60], let late = by[180] { holdout("offsetMin=60 from [0,+180]", predict: middle, from: [zero, late]) }
        // A single snapshot, 30 minutes ahead and 30 minutes back from now.
        if let back = by[-30], let zero = by[0], let snapshot = back.snapshot, let target = zero.snapshot {
            let truth = Dictionary(target.vehicles.map { ($0.tripID, $0) }, uniquingKeysWith: { first, _ in first })
            var errors: [Double] = []
            for vehicle in snapshot.vehicles {
                guard let real = truth[vehicle.tripID] else { continue }
                let schedule = RadarSchedule(vehicle)
                let anchor = RadarProjection.validatedAnchor(for: schedule, time: back.when, coordinate: vehicle.coordinate)
                guard let projected = RadarProjection.position(of: schedule, anchor: anchor, at: zero.when) else { continue }
                errors.append(projected.coordinate.distanceKm(to: real.coordinate))
            }
            describe("forward-from-minus30 to now anchored", errors)
        }
        // Do the reported delays of the same trip differ between frames? (Does the server predict, or only repeat what it knows?)
        for frame in usable where frame.offset > 0 {
            guard let snapshot = frame.snapshot else { continue }
            let other = Dictionary(snapshot.vehicles.map { ($0.tripID, $0) }, uniquingKeysWith: { first, _ in first })
            var compared = 0, changed = 0, reportedOnlyHere = 0, reportedOnlyBaseline = 0
            for vehicle in baseSnapshot.vehicles {
                guard let again = other[vehicle.tripID] else { continue }
                let a = RadarSchedule(vehicle), b = RadarSchedule(again)
                guard a.isProjectable, b.isProjectable else { continue }
                compared += 1
                if b.hasRealtime && !a.hasRealtime { reportedOnlyHere += 1 }
                if a.hasRealtime && !b.hasRealtime { reportedOnlyBaseline += 1 }
                if a.hasRealtime && b.hasRealtime,
                   let lastA = a.stops.last?.arrivalDelay, let lastB = b.stops.last?.arrivalDelay, abs(lastA - lastB) >= 120 { changed += 1 }
            }
            print("RADAR_TIME delays offsetMin=\(frame.offset) commonTrips=\(compared) delayAtLastStopDiffers2minPlus=\(changed) realtimeOnlyInThisFrame=\(reportedOnlyHere) realtimeOnlyInBaseline=\(reportedOnlyBaseline)")
        }
    }
}
