import Foundation
import CoreLocation
import KlimaCore

// "Fahrt aufzeichnen" (Mode A, docs/TRIP_DETECTION.md §2): the reliable way. The person starts a recording, the phone delivers
// precise GPS fixes – in the background too, with the blue location indicator – the live screen shows time, distance, speed and
// the station you are at, and stopping proposes the ride for confirmation. Location is used ONLY while a recording runs
// ("Beim Verwenden" is enough). Nothing is kept after the ride is decided except the ordinary trip.

/// CoreLocation as a `LocationProviding` source: dense fixes for a recording.
final class CoreLocationFeed: NSObject, CLLocationManagerDelegate, LocationProviding, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: AsyncStream<CoarsePoint>.Continuation?
    /// Called on the main thread when the permission changes.
    var onAuthorization: (@Sendable (CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func positions() -> AsyncStream<CoarsePoint> {
        AsyncStream { continuation in
            self.continuation = continuation
            // Background updates need the "location" background mode (Info.plist); without it the call would raise.
            let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
            if modes.contains("location") {
                self.manager.allowsBackgroundLocationUpdates = true
                self.manager.showsBackgroundLocationIndicator = true
            }
            self.manager.startUpdatingLocation()
        }
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization?(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 {
            continuation?.yield(CoarsePoint(time: location.timestamp, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                            accuracyMeters: location.horizontalAccuracy, speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
                                            source: .recording))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

@Observable
@MainActor
final class TripRecorder {
    static let shared = TripRecorder()

    enum Phase: Equatable {
        case idle
        /// Waiting for the permission dialog.
        case needsPermission
        case denied
        case recording
        /// Stopped; `proposal` holds the ride (nil when the recording was too short to be one).
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var snapshot: RecordingSnapshot?
    private(set) var proposal: RecordingProposal?
    /// The proposal was handed to the inbox as this candidate.
    private(set) var candidateID: UUID?

    var isRecording: Bool { phase == .recording }

    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var feed: (any LocationProviding)?
    @ObservationIgnored private var consume: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let makeFeed: @MainActor () -> any LocationProviding
    @ObservationIgnored private var lookup: (any StationLookup)?

    /// `makeFeed`: where the fixes come from – CoreLocation on the device, a scripted track in CI and demos.
    init(makeFeed: @escaping @MainActor () -> any LocationProviding = { CoreLocationFeed() }) {
        self.makeFeed = makeFeed
    }

    /// A recorder that shows a recording in progress without running one (CI scenes): the fixes of a scripted track up to
    /// `until` are taken in at once.
    static func demo(lookup: any StationLookup, track: [CoarsePoint], startedAt: Date, until: Int) -> TripRecorder {
        let recorder = TripRecorder(makeFeed: { ScriptedTrackProvider(script: []) })
        var session = RecordingSession(startedAt: startedAt, lookup: lookup)
        for point in track.prefix(until) { session.ingest(point) }
        recorder.session = session
        recorder.phase = .recording
        recorder.snapshot = session.snapshot(now: track.prefix(until).last?.time ?? startedAt)
        return recorder
    }

    // MARK: Start and stop

    /// Starts a recording. The permission is asked here (and only here), never in a screenshot or demo run.
    func start(lookup: any StationLookup) {
        guard phase != .recording else { return }
        self.lookup = lookup
        proposal = nil
        candidateID = nil
        if LaunchMode.isSandboxed {
            begin(lookup: lookup, feed: makeFeed())
            return
        }
        let live = CoreLocationFeed()
        switch live.status {
        case .denied, .restricted:
            phase = .denied
        case .notDetermined:
            phase = .needsPermission
            live.onAuthorization = { [weak self] status in
                Task { @MainActor in
                    guard let self, self.phase == .needsPermission else { return }
                    switch status {
                    case .authorizedWhenInUse, .authorizedAlways: self.begin(lookup: lookup, feed: live)
                    case .denied, .restricted: self.phase = .denied
                    default: break
                    }
                }
            }
            feed = live
            live.requestPermission()
        default:
            begin(lookup: lookup, feed: live)
        }
    }

    private func begin(lookup: any StationLookup, feed: any LocationProviding) {
        let startedAt = Date()
        self.feed = feed
        let session = RecordingSession(startedAt: startedAt, lookup: lookup)
        phase = .recording
        snapshot = session.snapshot(now: startedAt)
        self.session = session
        consume = Task { @MainActor [weak self] in
            for await point in feed.positions() {
                guard let self, self.phase == .recording else { break }
                self.session?.ingest(point)
                guard let snapshot = self.session?.snapshot(now: max(Date(), point.time)) else { continue }
                self.snapshot = snapshot
                RecordingActivityController.shared.update(snapshot)
            }
        }
        // The clock of the live screen: elapsed time and "GPS verloren" tick even when no fix arrives.
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase == .recording, let session = self.session else { return }
                self.snapshot = session.snapshot(now: Date())
            }
        }
        RecordingActivityController.shared.begin(startedAt: startedAt)
    }

    /// Stops the recording and builds the proposal. Idempotent.
    @discardableResult
    func stop(now: Date = Date()) -> RecordingProposal? {
        guard phase == .recording || phase == .needsPermission else { return proposal }
        consume?.cancel()
        ticker?.cancel()
        feed?.stop()
        feed = nil
        let result = session?.proposal(endedAt: now)
        snapshot = session?.snapshot(now: now)
        proposal = result
        phase = .finished
        RecordingActivityController.shared.end(proposal: result)
        return result
    }

    /// Throws the recording away (nothing is kept).
    func discard() {
        consume?.cancel()
        ticker?.cancel()
        feed?.stop()
        feed = nil
        session = nil
        snapshot = nil
        proposal = nil
        candidateID = nil
        phase = .idle
        RecordingActivityController.shared.end(proposal: nil)
    }

    /// Back to the start (after the ride was decided).
    func reset() { discard() }

    func attach(candidate: TripCandidateEntity) { candidateID = candidate.id }
}
