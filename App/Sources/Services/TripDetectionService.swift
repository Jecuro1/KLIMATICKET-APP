import Foundation
import CoreLocation
import UIKit
import UserNotifications
import KlimaCore

// "Hintergrund-Erkennung (Beta)" – docs/TRIP_DETECTION.md. Off by default; switched on only through the explanation screen.
//
// What it does: with "Immer" location access it collects COARSE data – significant location changes (cell-tower level), visits
// (iOS tells when you stayed somewhere) and geofence enter/exit at the stations you use most (up to 20) – into a rolling buffer
// of at most 36 hours on this device. After each event the pure detector (KlimaCore `TripDetector`) turns the buffer into
// CANDIDATE rides; they go to the "Fahrten-Vorschläge" inbox and NEVER become a ride without a tap. Raw points are deleted
// when a candidate is confirmed or dismissed, when the feature is switched off and with "Alle Standortdaten löschen".
// Nothing leaves the device except – with the consent for live data – one timetable question per candidate that carries two
// station names and a time, never a coordinate.
//
// A relaunch for a location event has no UI: stations, prices and the store are resolved on demand through the providers
// AppState sets, and evaluation waits for the store when it is not open yet (it runs again when the app comes to the foreground).

@Observable
@MainActor
final class TripDetectionService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isEnabled: Bool
    /// The one timetable question per candidate (effective only with the consent for live data).
    var timetableLookupEnabled: Bool {
        didSet { UserDefaults.standard.set(timetableLookupEnabled, forKey: DetectionDefaults.timetableLookup) }
    }
    /// The "Erkennungs-Protokoll" (newest first).
    private(set) var log: DetectionLog
    /// What the buffer holds right now (for the settings page: "3 Orte, 2 Aufenthalte").
    private(set) var bufferSummary = BufferSummary()
    /// Counts up when the person accepted a proposal: the savings counter on the Übersicht celebrates (docs/MOTION.md §11).
    private(set) var acceptTick = 0

    struct BufferSummary: Equatable {
        var points = 0
        var visits = 0
        var oldest: Date?
    }

    // MARK: Providers (set by AppState)

    /// The station index with the complete place database attached (builds it when a background launch has no UI).
    @ObservationIgnored var stationIndexProvider: @MainActor () async -> StationIndex = { StationIndex(stations: []) }
    /// Whether the official price table has a relation between two stations.
    @ObservationIgnored var relationProvider: @MainActor () -> (@Sendable (String, String) -> Bool) = { { _, _ in false } }
    /// The repository on the open store, nil while the store is not open (a background launch before the first unlock).
    @ObservationIgnored var repositoryProvider: @MainActor () -> Repository? = { nil }
    /// The live planner: consent, switches and the timetable (nil: no lookup).
    @ObservationIgnored var liveProvider: @MainActor () -> LiveDataService? = { nil }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var buffer: RollingPointBuffer
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var askedAlways = false
    @ObservationIgnored private var monitoredStations: [String: Station] = [:]

    static let notificationCategory = "TRIP_SUGGESTION"
    /// Region identifiers of this feature. Regions are shared by every location manager of the app (the Aussteige-Wecker has its own),
    /// so each side only touches – and only listens to – its own.
    private static let regionPrefix = "tripdetect.station."
    /// iOS allows 20 monitored regions per app; the rest is left to the Aussteige-Wecker.
    private static let maxRegions = 15

    var isAvailable: Bool {
        CLLocationManager.significantLocationChangeMonitoringAvailable() || CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    }
    var isAuthorizedAlways: Bool { authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    /// Whether the explanation screen was confirmed once (it is shown again after the feature was switched off).
    var wasExplained: Bool { UserDefaults.standard.bool(forKey: DetectionDefaults.explained) }

    override init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: DetectionDefaults.backgroundEnabled)
        timetableLookupEnabled = defaults.object(forKey: DetectionDefaults.timetableLookup) as? Bool ?? true
        buffer = LaunchMode.isSandboxed ? RollingPointBuffer() : PointBufferStore.load()
        log = LaunchMode.isSandboxed ? DetectionLog() : DetectionLogStore.load()
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
        refreshSummary()
        registerNotificationCategory()
        if isEnabled, isAuthorizedAlways, !LaunchMode.isSandboxed { startSources() }
    }

    // MARK: Switching on and off

    /// "Verstanden, einschalten" on the explanation screen. Asks for the location permission in two steps (iOS wants
    /// "Beim Verwenden" first, then "Immer"). Never in a screenshot or demo run.
    func enable() {
        guard !LaunchMode.isSandboxed else { return }
        UserDefaults.standard.set(true, forKey: DetectionDefaults.explained)
        isEnabled = true
        UserDefaults.standard.set(true, forKey: DetectionDefaults.backgroundEnabled)
        record(.info("Hintergrund-Erkennung eingeschaltet", at: Date()))
        advanceAuthorization()
    }

    /// Switching off stops every source and deletes the raw points.
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        UserDefaults.standard.set(false, forKey: DetectionDefaults.backgroundEnabled)
        stopSources()
        buffer.removeAll()
        persistBuffer()
        record(.info("Hintergrund-Erkennung ausgeschaltet, Standortpunkte gelöscht", at: Date()))
    }

    /// "Alle Standortdaten löschen": the buffer and the log (the caller removes the candidates through the Repository).
    func deleteAllLocationData() {
        buffer.removeAll()
        persistBuffer()
        log.removeAll()
        DetectionLogStore.save(log)
        scheduled?.cancel()
    }

    func noteAcceptance() { acceptTick += 1 }

    /// Back from the iOS Settings app: the permission may have changed.
    func refreshAuthorization() {
        authorization = manager.authorizationStatus
        if isEnabled { advanceAuthorization() }
    }

    /// Settings › Alle Standortdaten löschen leaves a trace of itself, but of nothing else.
    func noteDeletion() {
        record(.info("Alle Standortdaten gelöscht", at: Date()))
    }

    private func advanceAuthorization() {
        guard !LaunchMode.isSandboxed else { return }
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if !askedAlways {
                askedAlways = true
                manager.requestAlwaysAuthorization()
            }
        case .authorizedAlways:
            startSources()
            requestEvaluation()
        default:
            break
        }
    }

    // MARK: Sources

    /// Stations whose enter/exit marks a stay at a station – the ones used most, at most 15.
    /// Called at launch and after trips or favourites changed.
    func configure(stations index: StationIndex, frequentStationIDs: [String]) {
        let selected = frequentStationIDs.compactMap(index.station(id:)).prefix(Self.maxRegions)
        monitoredStations = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        guard isEnabled, isAuthorizedAlways, !LaunchMode.isSandboxed else { return }
        syncRegions()
    }

    private func startSources() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() }
        manager.startMonitoringVisits()
        syncRegions()
    }

    private func stopSources() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) { manager.stopMonitoring(for: region) }
    }

    private func syncRegions() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let wanted = Set(monitoredStations.keys.map { Self.regionPrefix + $0 })
        let mine = manager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.regionPrefix) }
        for region in mine where !wanted.contains(region.identifier) { manager.stopMonitoring(for: region) }
        let existing = Set(mine.map(\.identifier))
        for (id, station) in monitoredStations where !existing.contains(Self.regionPrefix + id) {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), radius: 250,
                                          identifier: Self.regionPrefix + id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Events

    private func add(points: [CoarsePoint]) {
        let now = Date()
        for point in points { buffer.append(point, now: now) }
        persistBuffer()
        requestEvaluation()
    }

    private func add(visit: VisitRecord) {
        buffer.upsert(visit, now: Date())
        persistBuffer()
        requestEvaluation()
    }

    private func regionEvent(center: GeoPoint, entered: Bool, at date: Date) {
        if entered {
            buffer.upsert(VisitRecord(at: center, accuracyMeters: 120, arrival: date, departure: nil, observedAt: date), now: date)
        } else {
            buffer.closeOpenVisit(near: center, departure: date, now: date)
        }
        persistBuffer()
        requestEvaluation()
    }

    private func persistBuffer() {
        guard !LaunchMode.isSandboxed else { return }
        PointBufferStore.save(buffer)
        refreshSummary()
    }

    private func refreshSummary() {
        bufferSummary = BufferSummary(points: buffer.points.count, visits: buffer.visits.count,
                                      oldest: [buffer.points.first?.time, buffer.visits.first?.firstTimeForSummary].compactMap { $0 }.min())
    }

    // MARK: Evaluation

    /// Runs the detector soon (events come in bursts); runs at launch and when the app comes to the foreground, too.
    func requestEvaluation(after delay: Duration = .seconds(2)) {
        guard isEnabled else { return }
        scheduled?.cancel()
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueue { await self?.evaluate() }
        }
    }

    /// Detector runs one after another, each with extra background time: a relaunch for a location event only gets a few
    /// seconds, and resolving the stations may first have to build the place index.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            let time = DetectionBackgroundTime(name: "TripDetection")
            await work()
            time.end()
        }
    }

    private func evaluate() async {
        guard isEnabled, !LaunchMode.isSandboxed, let repository = repositoryProvider() else { return }
        let now = Date()
        buffer.prune(now: now)
        let index = await stationIndexProvider()
        let detector = TripDetector(matcher: StationMatcher(lookup: index), knownRelation: relationProvider())
        let outcome = detector.detect(buffer.track, now: now, history: repository.pairHistory())
        let triage = repository.triage(outcome, now: now)
        log.record(outcome, duplicates: triage.duplicates, at: now)

        // The optional timetable question – only for rides that are about to be proposed.
        var candidates = triage.fresh
        var lines: [UUID: String] = [:]
        for (i, candidate) in candidates.enumerated() {
            let verdict = await timetableVerdict(for: candidate, index: index)
            if case .confirmed(let connection) = verdict { lines[candidate.id] = connection.summary }
            if verdict != .unavailable { candidates[i] = candidate.ranked(with: verdict) }
        }
        candidates = candidates.filter { $0.rank.isProposable }
        let result = repository.insert(candidates, timetableLines: lines)
        for candidate in candidates where result.inserted.contains(where: { $0.fromStationID == candidate.from.station.id && $0.toStationID == candidate.to.station.id && $0.departedAt == candidate.departure }) {
            log.add(.proposed(candidate, at: now), now: now)
        }
        for replaced in result.replaced { log.add(.replaced(replaced.candidate, count: replaced.count, at: now), now: now) }
        repository.pruneDecidedCandidates(now: now)
        DetectionLogStore.save(log)
        persistBuffer()
        if !result.inserted.isEmpty { notify(result.inserted) }
    }

    /// One timetable question for a candidate: station names (HAFAS location ids) and a time – no coordinate of the person.
    private func timetableVerdict(for candidate: DetectedCandidate, index: StationIndex) async -> TimetableVerdict {
        guard timetableLookupEnabled, let live = liveProvider(), live.consent == .granted, let timetable = live.timetable else { return .unavailable }
        do {
            let origin = try await live.linker.hafasLocation(for: candidate.from.station)
            let destination = try await live.linker.hafasLocation(for: candidate.to.station)
            let query = JourneyQuery(origin: origin, destination: destination, date: candidate.departure.addingTimeInterval(-20 * 60),
                                     results: 5, includeStopovers: false)
            let page = try await timetable.journeys(query)
            let connections = page.journeys.compactMap { journey -> TimetableConnection? in
                let rides = journey.legs.filter { $0.kind == .ride }
                guard let first = rides.first?.departure.effective, let last = rides.last?.arrival.effective else { return nil }
                return TimetableConnection(departure: first, arrival: last, line: rides.first?.line?.name)
            }
            return TimetableConfirmation.verdict(departure: candidate.departure, arrival: candidate.arrival, connections: connections)
        } catch {
            return .unavailable
        }
    }

    // MARK: Log

    private func record(_ entry: DetectionLogEntry) {
        log.add(entry, now: entry.loggedAt)
        guard !LaunchMode.isSandboxed else { return }
        DetectionLogStore.save(log)
    }

    /// Writes a decision of the person (confirmed, dismissed) into the log; the raw points of that ride are deleted.
    func didDecide(_ candidate: TripCandidateEntity, accepted: Bool) {
        buffer.remove(from: candidate.evidenceStart, to: candidate.evidenceEnd)
        persistBuffer()
        let verb = accepted ? "Übernommen" : "Verworfen"
        record(.decision("\(verb). Die Standortpunkte dieser Fahrt sind gelöscht.", title: "\(candidate.fromName) → \(candidate.toName)", at: Date()))
    }

    func clearLog() {
        log.removeAll()
        DetectionLogStore.save(log)
    }

    // MARK: Migration of the earlier geofence detection

    /// The earlier version kept its suggestions in UserDefaults and monitored regions without the new consent. Open
    /// suggestions move into the inbox (as "vielleicht"-free legacy proposals), the switch stays off until the new explanation
    /// was confirmed, and the old regions stop.
    func migrateLegacy(into repository: Repository) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DetectionDefaults.legacySuggestions) != nil || defaults.object(forKey: DetectionDefaults.legacyEnabled) != nil else { return }
        if let data = defaults.data(forKey: DetectionDefaults.legacySuggestions),
           let old = try? JSONDecoder().decode([LegacySuggestion].self, from: data) {
            let known = repository.allCandidates()
            for suggestion in old where Date().timeIntervalSince(suggestion.arrivedAt) < 7 * 86_400
                && !known.contains(where: { $0.fromStationID == suggestion.fromStationID && $0.toStationID == suggestion.toStationID && $0.departedAt == suggestion.departedAt }) {
                let entity = TripCandidateEntity(source: .legacy, fromName: suggestion.fromName, toName: suggestion.toName,
                                                 fromStationID: suggestion.fromStationID, toStationID: suggestion.toStationID, mode: .train,
                                                 departedAt: suggestion.departedAt, arrivedAt: suggestion.arrivedAt, straightKm: suggestion.distanceKm,
                                                 confidence: .wahrscheinlich, sketch: nil)
                repository.context.insert(entity)
            }
            repository.saveCandidates()
        }
        if !LaunchMode.isSandboxed {
            // The earlier version named its regions by station id ("at:47:1187"); an alarm's region is a UUID and ours has the prefix.
            for region in manager.monitoredRegions where region.identifier.contains(":") && !region.identifier.hasPrefix(Self.regionPrefix) {
                manager.stopMonitoring(for: region)
            }
        }
        for key in [DetectionDefaults.legacySuggestions, DetectionDefaults.legacyLastExit, DetectionDefaults.legacyLastArrival, DetectionDefaults.legacyEnabled] {
            defaults.removeObject(forKey: key)
        }
    }

    private struct LegacySuggestion: Codable {
        var fromStationID: String
        var toStationID: String
        var fromName: String
        var toName: String
        var departedAt: Date
        var arrivedAt: Date
        var distanceKm: Double
    }

    // MARK: Notification

    /// "Fahrt erkannt?" – only when notifications are allowed already (nothing is asked here) and it is not the foreground;
    /// opens the app on the Übersicht, where the inbox is. No action button: every ride is looked at first.
    private func notify(_ inserted: [TripCandidateEntity]) {
        guard UIApplication.shared.applicationState != .active else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = inserted.count == 1 ? "Fahrt erkannt?" : "\(inserted.count) Fahrten erkannt?"
            let first = inserted[0]
            content.body = inserted.count == 1 ? "\(first.fromName) → \(first.toName) · \(first.confidence.label) – in der App ansehen und bestätigen."
                                               : "Sieh sie dir in der Übersicht an und bestätige, was stimmt."
            content.sound = .default
            content.categoryIdentifier = Self.notificationCategory
            content.threadIdentifier = "suggestions"
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: first.id.uuidString, content: content, trigger: nil))
        }
    }

    /// All categories are registered together (NotificationCategories): a second `setNotificationCategories` would drop the first.
    private func registerNotificationCategory() {
        NotificationCategories.registerAll()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isEnabled { self.advanceAuthorization() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.compactMap { location -> CoarsePoint? in
            guard location.horizontalAccuracy >= 0 else { return nil }
            return CoarsePoint(time: location.timestamp, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                               accuracyMeters: location.horizontalAccuracy, speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
                               source: .significantChange)
        }
        guard !points.isEmpty else { return }
        Task { @MainActor in self.add(points: points) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let floor = Date(timeIntervalSince1970: 0)
        let record = VisitRecord(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude,
                                 accuracyMeters: visit.horizontalAccuracy >= 0 ? visit.horizontalAccuracy : 100,
                                 arrival: visit.arrivalDate > floor ? visit.arrivalDate : nil,
                                 departure: visit.departureDate < Date.distantFuture.addingTimeInterval(-86_400) ? visit.departureDate : nil,
                                 observedAt: Date())
        Task { @MainActor in self.add(visit: record) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circle = region as? CLCircularRegion, circle.identifier.hasPrefix(Self.regionPrefix) else { return }
        let center = GeoPoint(latitude: circle.center.latitude, longitude: circle.center.longitude), date = Date()
        Task { @MainActor in self.regionEvent(center: center, entered: true, at: date) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circle = region as? CLCircularRegion, circle.identifier.hasPrefix(Self.regionPrefix) else { return }
        let center = GeoPoint(latitude: circle.center.latitude, longitude: circle.center.longitude), date = Date()
        Task { @MainActor in self.regionEvent(center: center, entered: false, at: date) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {}
}

private extension VisitRecord {
    /// The first moment of a visit for the buffer summary.
    var firstTimeForSummary: Date { arrival ?? departure ?? observedAt }
}

/// A UIKit background-task assertion: keeps a process that iOS woke for a location event alive until the work is done.
@MainActor
private final class DetectionBackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
