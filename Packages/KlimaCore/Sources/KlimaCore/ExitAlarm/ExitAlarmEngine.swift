import Foundation

// Aussteige-Wecker: the engine that carries the planner's decisions out (docs/EXIT_ALARM.md §3, §5). It owns the book of
// alarms, talks to a location provider and a scheduler through two protocols, and saves the book. Everything Apple-specific
// (CLLocationManager, AlarmKit, UNUserNotificationCenter) sits behind the protocols, so CI, the demo scenes and the unit
// tests drive the same engine with scripted tracks and a fake scheduler.
//
// Privacy: the engine never keeps a track. Fixes go straight into the planner, which keeps only the newest one in memory.
// The saved book holds stops and schedules, never positions (`ExitAlarmState.CodingKeys`).

// MARK: Location

public enum ExitAlarmLocationAuthorization: String, Codable, Sendable, Hashable {
    case notDetermined, restricted, denied, whenInUse, always

    /// Fixes arrive while the app runs (in the background too, with the location background mode).
    public var allowsUpdates: Bool { self == .whenInUse || self == .always }
    /// The system can wake or relaunch the app for the geofence.
    public var allowsWakeUp: Bool { self == .always }
}

public protocol ExitAlarmLocationHandler: AnyObject {
    func locationProvider(didUpdate fix: LocationFix)
    func locationProvider(didEnterRegion id: String)
    func locationProviderDidChangeAuthorization()
    /// The system refused the region (too many regions, monitoring unavailable): the GPS estimate carries on.
    func locationProvider(regionMonitoringFailed id: String)
}

/// The device's location, behind a protocol. The real one wraps CLLocationManager.
public protocol ExitAlarmLocationProviding: AnyObject {
    var authorization: ExitAlarmLocationAuthorization { get }
    var isRegionMonitoringAvailable: Bool { get }
    var handler: ExitAlarmLocationHandler? { get set }
    /// Only after the pre-prompt screen: the system asks "Beim Verwenden", then offers "Immer".
    func requestWhenInUse()
    func requestAlways()
    /// Low-power updates (kilometres, not metres); only while a trip runs and an alarm waits.
    func startUpdates()
    func stopUpdates()
    func startMonitoring(regionID: String, center: GeoPoint, radius: Double)
    func stopMonitoring(regionID: String)
}

// MARK: Scheduler

/// Which kind of alarm the device uses for the time-based path. Settings says it.
public enum ExitAlarmKind: String, Codable, Sendable, Hashable {
    /// iOS 26 AlarmKit: rings through silent mode and Focus.
    case alarmKit
    /// Local notifications, three in a row 20 s apart: silent mode or Focus can mute them.
    case notifications
    /// Nothing can ring (no permission for either).
    case none
}

public enum ExitAlarmSchedulerEvent: Sendable, Hashable {
    /// The scheduled alarm went off (or is ringing now).
    case rang(String)
    /// The user stopped the ringing alarm outside the app (Lock Screen).
    case stopped(String)
    /// The scheduler could not take the alarm.
    case failed(String)
}

/// The time-based alarm and the immediate ring, behind a protocol. The real one tries AlarmKit and falls back to local
/// notifications; the ids are the alarm ids of the engine.
public protocol ExitAlarmScheduling: AnyObject {
    var kind: ExitAlarmKind { get }
    var onEvent: ((ExitAlarmSchedulerEvent) -> Void)? { get set }
    func schedule(_ content: ExitAlarmRingContent, at date: Date)
    func cancel(id: String)
    func ringNow(_ content: ExitAlarmRingContent)
    func stopRinging(id: String)
}

public protocol ExitAlarmPersisting: AnyObject {
    func load() -> ExitAlarmBook?
    func save(_ book: ExitAlarmBook)
}

// MARK: Engine

public final class ExitAlarmEngine: ExitAlarmLocationHandler {
    public private(set) var book = ExitAlarmBook()
    /// The "Wecker testen" moment, nil when no test is waiting.
    public private(set) var testAt: Date?
    /// A test alarm rang (the full-screen moment shows it until it is acknowledged).
    public private(set) var testRang = false
    /// Why the last geofence failed, when it did (the card says GPS carries on).
    public private(set) var geofenceFailed = false

    /// Called after every change of the book (the app's observable store mirrors it).
    public var onChange: (() -> Void)?

    public let location: ExitAlarmLocationProviding
    public let scheduler: ExitAlarmScheduling
    private let persistence: ExitAlarmPersisting
    private let clock: () -> Date
    public let config: ExitAlarmConfig
    private var updatesRunning = false
    /// The geofences that are set, by alarm id.
    private var regions: Set<String> = []
    /// Geofences the system refused: not asked again.
    private var failedRegions: Set<String> = []
    /// The user agreed to "Immer" in the pre-prompt: ask for the upgrade when "Beim Verwenden" has been answered.
    private var wantsAlways = false

    public static let testID = "exitalarm-test"

    public init(location: ExitAlarmLocationProviding, scheduler: ExitAlarmScheduling, persistence: ExitAlarmPersisting,
                config: ExitAlarmConfig = .standard, clock: @escaping () -> Date = Date.init) {
        self.location = location
        self.scheduler = scheduler
        self.persistence = persistence
        self.config = config
        self.clock = clock
        location.handler = self
        scheduler.onEvent = { [weak self] event in self?.schedulerEvent(event) }
    }

    // MARK: Lifecycle

    /// Loads the saved alarms and puts the system back in line with them: the time-based alarms are scheduled again (the
    /// scheduler replaces an alarm with the same id), the geofences are set again and a clock tick checks the moment.
    /// Called at launch, also when the system relaunched the app for a geofence.
    public func restore() {
        guard var saved = persistence.load() else { return }
        let now = clock()
        saved.prune(now: now)
        book = saved
        for state in book.active {
            if let scheduled = state.scheduledTimeAlarm, scheduled > now {
                scheduler.schedule(ExitAlarmPresentation.ringContent(state.spec, kind: .arrival, now: now), at: scheduled)
            }
            if state.phase != .fired, let radius = state.geofenceRadius, let center = state.spec.stopCoordinate ?? state.spec.path.last {
                location.startMonitoring(regionID: state.id, center: center, radius: radius)
                regions.insert(state.id)
            }
        }
        tick()
    }

    public var hasActiveAlarms: Bool { !book.active.isEmpty }

    // MARK: Arming

    @discardableResult
    public func arm(_ spec: ExitAlarmSpec, arrival: Date?, departure: Date? = nil, delaySeconds: Int? = nil) -> ExitAlarmBook.ArmResult {
        let now = clock()
        let outcome = book.arm(spec, arrival: arrival, departure: departure, delaySeconds: delaySeconds, now: now, config: config)
        run(outcome.commands, now: now)
        changed()
        return outcome.result
    }

    /// A fresh timetable answer for a run: every alarm of that run takes the data of its stop.
    public func timetable(tripID: String, stopovers: [Stopover]) {
        let now = clock()
        var commands: [ExitAlarmCommand] = []
        for state in book.active where state.spec.tripID == tripID {
            if let data = ExitAlarmStops.timetable(for: state.spec, in: stopovers) {
                commands += book.apply(.timetable(arrival: data.arrival, departure: data.departure, delaySeconds: data.delaySeconds),
                                       to: state.id, now: now, config: config)
            }
        }
        run(commands, now: now)
        changed()
    }

    public func tick() {
        let now = clock()
        let commands = book.apply(.tick, now: now, config: config)
        book.prune(now: now)
        if let testAt, !testRang, now >= testAt { testRang = true }
        run(commands, now: now)
        changed()
    }

    // MARK: User actions

    public func acknowledge(id: String) {
        let now = clock()
        run(book.apply(.acknowledge, to: id, now: now, config: config), now: now)
        changed()
    }

    public func acknowledgeTest() {
        testRang = false
        testAt = nil
        scheduler.stopRinging(id: Self.testID)
        scheduler.cancel(id: Self.testID)
        onChange?()
    }

    public func snooze(id: String, minutes: Int = 5) {
        let now = clock()
        run(book.apply(.snooze(minutes: minutes), to: id, now: now, config: config), now: now)
        changed()
    }

    public func cancel(id: String, reason: ExitAlarmEndReason = .cancelledByUser) {
        let now = clock()
        run(book.apply(.end(reason), to: id, now: now, config: config), now: now)
        changed()
    }

    /// The follow of a run ended: its alarms end with it.
    public func followEnded(tripID: String) {
        let now = clock()
        run(book.apply(.end(.followEnded), tripID: tripID, now: now, config: config), now: now)
        changed()
    }

    /// Live-Daten went off (kill switch or the user's switch): the alarms depend on live timetable data, so they end.
    public func liveDataOff() {
        let now = clock()
        run(book.apply(.end(.killSwitch), now: now, config: config), now: now)
        changed()
    }

    /// "Wecker testen": one alarm in `seconds`, not part of the book. It rings like the real one (same scheduler, same
    /// sound), so the owner can check silent mode, Focus and the locked screen.
    public func scheduleTest(after seconds: TimeInterval = 10, soundKey: String) {
        let now = clock()
        let spec = ExitAlarmSpec(tripID: "test", lineName: "Test", stopID: "test", stopName: "Testhalt", lead: .atArrival,
                                 createdAt: now, soundKey: soundKey)
        var content = ExitAlarmPresentation.ringContent(spec, kind: .test, now: now)
        content.id = Self.testID
        testAt = now.addingTimeInterval(seconds)
        testRang = false
        scheduler.schedule(content, at: now.addingTimeInterval(seconds))
        onChange?()
    }

    // MARK: Location authorization

    /// The two-step permission: "Beim Verwenden" first, then (when `always`) the system's upgrade to "Immer". The engine
    /// asks for the second step itself once the first one is answered. Called only after the pre-prompt screen.
    public func requestLocation(always: Bool) {
        switch location.authorization {
        case .notDetermined:
            wantsAlways = always
            location.requestWhenInUse()
        case .whenInUse:
            if always { location.requestAlways() }
        default:
            break
        }
    }

    // MARK: ExitAlarmLocationHandler

    public func locationProvider(didUpdate fix: LocationFix) {
        let now = clock()
        let commands = book.apply(.fix(fix), now: now, config: config)
        run(commands, now: now)
        changed()
    }

    public func locationProvider(didEnterRegion id: String) {
        let now = clock()
        run(book.apply(.regionEntered, to: id, now: now, config: config), now: now)
        changed()
    }

    public func locationProviderDidChangeAuthorization() {
        if wantsAlways, location.authorization == .whenInUse {
            wantsAlways = false
            location.requestAlways()
        } else if location.authorization != .notDetermined {
            wantsAlways = false
        }
        syncLocation()
        onChange?()
    }

    public func locationProvider(regionMonitoringFailed id: String) {
        regions.remove(id)
        failedRegions.insert(id)
        geofenceFailed = true
        onChange?()
    }

    // MARK: Scheduler events

    private func schedulerEvent(_ event: ExitAlarmSchedulerEvent) {
        let now = clock()
        switch event {
        case .rang(let id):
            if id == Self.testID {
                testRang = true
                onChange?()
                return
            }
            run(book.apply(.timeAlarmRang, to: id, now: now, config: config), now: now)
        case .stopped(let id):
            if id == Self.testID {
                acknowledgeTest()
                return
            }
            run(book.apply(.acknowledge, to: id, now: now, config: config), now: now)
        case .failed(let id):
            run(book.apply(.timeAlarmUnavailable, to: id, now: now, config: config), now: now)
            run(book.apply(.tick, to: id, now: now, config: config), now: now)
        }
        changed()
    }

    // MARK: Effects

    private func run(_ commands: [ExitAlarmCommand], now: Date) {
        for command in commands {
            guard let state = book.state(id: command.alarmID) else { continue }
            let spec = state.spec
            switch command.effect {
            case .scheduleTimeAlarm(let date):
                scheduler.schedule(ExitAlarmPresentation.ringContent(spec, kind: .arrival, now: now), at: date)
            case .cancelTimeAlarm:
                scheduler.cancel(id: spec.id)
            case .ring:
                scheduler.ringNow(ExitAlarmPresentation.ringContent(spec, kind: .arrival, now: now))
            case .ringPassed:
                scheduler.ringNow(ExitAlarmPresentation.ringContent(spec, kind: .passed, now: now))
            case .stopRinging:
                scheduler.stopRinging(id: spec.id)
            case .setGeofence(let center, let radius):
                if location.isRegionMonitoringAvailable, location.authorization.allowsUpdates {
                    location.startMonitoring(regionID: spec.id, center: center, radius: radius)
                    regions.insert(spec.id)
                }
            case .removeGeofence:
                location.stopMonitoring(regionID: spec.id)
                regions.remove(spec.id)
            }
        }
        syncLocation()
    }

    /// Starts or stops the low-power updates by what the alarms need now. The geofences follow the commands.
    private func syncLocation() {
        let now = clock()
        let need = book.locationNeed(now: now, config: config)
        let authorization = location.authorization
        let wantsUpdates = need == .continuous && authorization.allowsUpdates
        if wantsUpdates, !updatesRunning {
            location.startUpdates()
            updatesRunning = true
        } else if !wantsUpdates, updatesRunning {
            location.stopUpdates()
            updatesRunning = false
        }
        if need == .none {
            for id in regions { location.stopMonitoring(regionID: id) }
            regions.removeAll()
        } else if authorization.allowsUpdates, location.isRegionMonitoringAvailable {
            // A permission that came later (the user chose "Immer" after arming) sets the circles that were not possible before.
            for state in book.active where state.phase != .fired && !regions.contains(state.id) && !failedRegions.contains(state.id) {
                guard let radius = state.geofenceRadius, let center = state.spec.stopCoordinate ?? state.spec.path.last else { continue }
                location.startMonitoring(regionID: state.id, center: center, radius: radius)
                regions.insert(state.id)
            }
        }
    }

    private func changed() {
        persistence.save(book)
        onChange?()
    }
}
