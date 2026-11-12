import Foundation
import CoreLocation
import UIKit
import UserNotifications
import KlimaCore

// "Fahrt aufzeichnen" (Mode A, docs/TRIP_DETECTION.md §2): the reliable way. The person starts a recording, the phone delivers
// precise GPS fixes – in the background too, with the blue location indicator – the live screen shows time, distance, speed and
// the station you are at, and stopping proposes the ride for confirmation. Location is used ONLY while a recording runs
// ("Beim Verwenden" is enough). Nothing is kept after the ride is decided except the ordinary trip. A recording nobody stops ends by
// itself (30 minutes without moving, 12 hours, permission taken away): full-accuracy GPS must not run for days on a forgotten phone.

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
        // No distance filter (the default): a standing train delivers no fix at all under a filter, and the live screen would show its last
        // speed for good, report "GPS-Signal schwach" after 20 s at every station and never see a halt. The jitter of a standing phone
        // is filtered in `RecordingSession` (steps under ~6 m add no distance).
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    /// "Genauer Standort" is off in the iOS settings: the fixes are only good to a few kilometres, the recording would never find a route.
    var isReducedAccuracy: Bool { manager.accuracyAuthorization == .reducedAccuracy }

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
            // iOS asks once whether the exact location may be used for this recording (Info.plist: NSLocationTemporaryUsageDescriptionDictionary).
            if self.isReducedAccuracy { self.manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.fullAccuracyPurposeKey) }
        }
    }

    static let fullAccuracyPurposeKey = "TripRecording"

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
    /// The one recorder of the app. Created on first use – before that no recording can exist in this process, so a "Aufzeichnung
    /// läuft" Live Activity that is still on the Lock Screen belongs to a process that was killed: it ends here.
    static let shared: TripRecorder = {
        RecordingActivityController.shared.endOrphans()
        return TripRecorder()
    }()

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
    /// Why the recording ended without "Beenden" (nil: the person ended it).
    private(set) var autoStopReason: RecordingAutoStop?
    /// "Genauer Standort" is off: no usable fix can come.
    private(set) var accuracyIsReduced = false
    /// A recording was running when the app process ended (iOS ended it, or it was swiped away): the track was only in memory and is gone.
    private(set) var interruptedStart: Date?

    var isRecording: Bool { phase == .recording }

    /// Files the proposal of a recording that ended by itself (the screen may not be open, the app may be in the background). Set by
    /// AppState; returns the inbox entry.
    @ObservationIgnored var autoStopHandler: (@MainActor (RecordingProposal) -> TripCandidateEntity?)?

    /// UserDefaults key: when the running recording started. Present only while one runs – the time, never a place.
    private static let runningKey = "tripdetect.recording.since"

    @ObservationIgnored private var session: RecordingSession?
    @ObservationIgnored private var feed: (any LocationProviding)?
    @ObservationIgnored private var consume: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let makeFeed: @MainActor () -> any LocationProviding
    @ObservationIgnored private var lookup: (any StationLookup)?

    /// `makeFeed`: where the fixes come from – CoreLocation on the device, a scripted track in CI and demos (a sandboxed run never
    /// touches CoreLocation, so it can never raise a permission alert).
    init(makeFeed: @escaping @MainActor () -> any LocationProviding = { LaunchMode.isSandboxed ? ScriptedTrackProvider(script: []) : CoreLocationFeed() }) {
        self.makeFeed = makeFeed
        // A start time that is still there was never cleared by a stop: the process ended during a recording.
        if !LaunchMode.isSandboxed, let started = UserDefaults.standard.object(forKey: Self.runningKey) as? Date {
            interruptedStart = started
            UserDefaults.standard.removeObject(forKey: Self.runningKey)
        }
    }

    func acknowledgeInterruption() { interruptedStart = nil }

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

    /// CI scenes only: a state the live code reaches on a device (a reduced-accuracy permission, a recording that ended by itself, one the
    /// process lost) – nothing of it can be provoked in the simulator without a system dialog.
    func demoState(accuracyIsReduced: Bool = false, autoStop: RecordingAutoStop? = nil, interruptedStart: Date? = nil) {
        self.accuracyIsReduced = accuracyIsReduced
        self.autoStopReason = autoStop
        self.interruptedStart = interruptedStart
    }

    // MARK: Start and stop

    /// Starts a recording. The permission is asked here (and only here), never in a screenshot or demo run.
    func start(lookup: any StationLookup) {
        guard phase != .recording else { return }
        self.lookup = lookup
        proposal = nil
        candidateID = nil
        autoStopReason = nil
        interruptedStart = nil
        if LaunchMode.isSandboxed {
            begin(lookup: lookup, feed: makeFeed())
            return
        }
        let live = CoreLocationFeed()
        // Weak: the feed holds this closure, so a strong reference back to it would keep both (and the location manager) alive
        // for good after the recording was cancelled. It also hears a permission taken away while recording.
        live.onAuthorization = { [weak self, weak live] status in
            Task { @MainActor in
                guard let self, let live else { return }
                self.authorizationChanged(status, feed: live, lookup: lookup)
            }
        }
        switch live.status {
        case .denied, .restricted:
            phase = .denied
        case .notDetermined:
            phase = .needsPermission
            feed = live
            live.requestPermission()
        default:
            begin(lookup: lookup, feed: live)
        }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus, feed live: CoreLocationFeed, lookup: any StationLookup) {
        switch phase {
        case .needsPermission:
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: begin(lookup: lookup, feed: live)
            case .denied, .restricted: phase = .denied
            default: break
            }
        case .recording:
            // Location off in the iOS settings or Control Center: no fix can come any more. End cleanly instead of "GPS-Signal schwach" for good.
            if status == .denied || status == .restricted { finishAutomatically(.locationOff) }
        default:
            break
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
        // The clock of the live screen: elapsed time and "GPS verloren" tick even when no fix arrives. It also ends a forgotten recording.
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase == .recording, let session = self.session else { return }
                let now = Date()
                self.snapshot = session.snapshot(now: now)
                let reduced = (self.feed as? CoreLocationFeed)?.isReducedAccuracy ?? false
                if reduced != self.accuracyIsReduced { self.accuracyIsReduced = reduced }
                if let reason = session.autoStop(now: now) {
                    self.finishAutomatically(reason)
                    return
                }
            }
        }
        if !LaunchMode.isSandboxed { UserDefaults.standard.set(startedAt, forKey: Self.runningKey) }
        RecordingActivityController.shared.begin(startedAt: startedAt)
    }

    /// The recording ends without the person: it proposes the ride up to the moment the phone last moved, files it in the inbox through
    /// `autoStopHandler`, and – with the app in the background and notifications allowed already – says so.
    func finishAutomatically(_ reason: RecordingAutoStop) {
        guard phase == .recording else { return }
        var endedAt = Date()
        if case .idle(let since) = reason { endedAt = since }
        autoStopReason = reason
        let result = stop(now: endedAt)
        if let result, let candidate = autoStopHandler?(result) { candidateID = candidate.id }
        notifyAutoStop(reason, hasProposal: result != nil)
    }

    private func notifyAutoStop(_ reason: RecordingAutoStop, hasProposal: Bool) {
        guard !LaunchMode.isSandboxed, UIApplication.shared.applicationState != .active else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Aufzeichnung beendet"
            content.body = reason.text() + (hasProposal ? " Die Fahrt wartet in der Übersicht." : " Es kam keine Fahrt zusammen.")
            content.sound = .default
            content.categoryIdentifier = TripDetectionService.notificationCategory
            content.threadIdentifier = "recording"
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "recording.autostop", content: content, trigger: nil))
        }
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
        UserDefaults.standard.removeObject(forKey: Self.runningKey)
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
        autoStopReason = nil
        accuracyIsReduced = false
        phase = .idle
        UserDefaults.standard.removeObject(forKey: Self.runningKey)
        RecordingActivityController.shared.end(proposal: nil)
    }

    /// Back to the start (after the ride was decided).
    func reset() { discard() }

    func attach(candidate: TripCandidateEntity) { candidateID = candidate.id }
}
