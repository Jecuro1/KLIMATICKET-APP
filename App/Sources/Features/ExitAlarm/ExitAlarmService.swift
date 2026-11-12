import Foundation
import Observation
import UserNotifications
import KlimaCore

// Aussteige-Wecker: the app's side (docs/EXIT_ALARM.md). One observable service wraps the engine of KlimaCore, the real
// location provider and the system alarms, restores the saved alarms at launch (also when iOS relaunches the app for a
// geofence), ticks while an alarm is armed and tells the views what is going on. Screenshot, perf and demo runs use the
// engine with the fakes of KlimaCore: no permission prompt, no real alarm, no location.
//
// Lifecycle: an alarm belongs to a follow ("Live verfolgen") of its run. The tracker feeds timetable answers in
// (`followUpdated`), and tells when the follow ended (`followEnded`) or live data went off (`liveDataOff`).

@MainActor
@Observable
final class ExitAlarmService {
    static let shared = ExitAlarmService()

    /// Counts up on every change of the engine: views that read `book` re-render.
    private(set) var revision = 0
    private(set) var locationAuthorization: ExitAlarmLocationAuthorization
    /// "Genauer Standort" is off in iOS: the location is only good to some kilometres, so the timetable carries the alarm.
    private(set) var locationIsApproximate = false
    private(set) var alarmKind: ExitAlarmKind
    /// The user declined AlarmKit and the notification fallback in iOS: nothing can ring when the app is closed.
    private(set) var cannotRingInBackground = false

    @ObservationIgnored let engine: ExitAlarmEngine
    @ObservationIgnored private let system: SystemExitAlarmScheduler?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var restored = false
    /// What the Live Activity last heard about the alarms (stop, kind of line, approaching): it is refreshed when this changes, so the
    /// "Aussteigen in 4 Min" line does not outlive the alarm until the next poll.
    @ObservationIgnored private var activitySignature: String?
    /// Screenshot, perf or demo run: fakes, no prompts, nothing real.
    let isSimulated: Bool

    var book: ExitAlarmBook {
        _ = revision
        return engine.book
    }

    var testRang: Bool {
        _ = revision
        return engine.testRang
    }

    var testAt: Date? {
        _ = revision
        return engine.testAt
    }

    var geofenceFailed: Bool {
        _ = revision
        return engine.geofenceFailed
    }

    /// The alarm whose full-screen moment is up: it rang and waits for the user.
    var attention: ExitAlarmState? { book.needsAttention }

    init(simulated: Bool = LaunchMode.isSandboxed || LaunchMode.useDemoData) {
        isSimulated = simulated
        if simulated {
            let location = ScriptedLocationProvider(authorization: .always)
            let scheduler = FakeAlarmScheduler(kind: .alarmKit)
            engine = ExitAlarmEngine(location: location, scheduler: scheduler, persistence: MemoryAlarmPersistence())
            system = nil
            locationAuthorization = .always
            alarmKind = .alarmKit
        } else {
            let scheduler = SystemExitAlarmScheduler()
            engine = ExitAlarmEngine(location: CLExitAlarmLocation(), scheduler: scheduler,
                                     persistence: ExitAlarmUserDefaultsStorage())
            system = scheduler
            locationAuthorization = engine.location.authorization
            alarmKind = scheduler.kind
        }
        system?.onStatusChange = { [weak self] in MainActor.assumeIsolated { self?.refreshStatus() } }
        engine.onChange = { [weak self] in
            // Engine callbacks arrive on the main thread (location, timers, notification responses).
            MainActor.assumeIsolated { self?.engineChanged() }
        }
    }

    // MARK: Launch

    /// Brings the saved alarms back: the time-based alarms are scheduled again and the geofences set again. Called from the
    /// app delegate at launch, so a relaunch for a geofence entry finds the engine ready. Idempotent.
    func restoreIfNeeded() {
        guard !restored, !isSimulated else { return }
        restored = true
        engine.restore()
        refreshStatus()
        updateTicker()
    }

    /// The scene became active: the clock may have run while the app slept.
    func sceneBecameActive() {
        guard !isSimulated else { return }
        engine.tick()
        refreshStatus()
        ExitAlarmWindow.shared.update()
    }

    // MARK: Arming and changing

    /// Turns an alarm on. The permissions are asked before (`prepare`).
    @discardableResult
    func arm(_ spec: ExitAlarmSpec, arrival: Date?, departure: Date? = nil, delaySeconds: Int? = nil) -> ExitAlarmBook.ArmResult {
        let result = engine.arm(spec, arrival: arrival, departure: departure, delaySeconds: delaySeconds)
        updateTicker()
        return result
    }

    func acknowledge(_ id: String) {
        engine.acknowledge(id: id)
        updateTicker()
    }

    func snooze(_ id: String, minutes: Int = 5) {
        engine.snooze(id: id, minutes: minutes)
    }

    func cancel(_ id: String) {
        engine.cancel(id: id)
        updateTicker()
    }

    func acknowledgeTest() { engine.acknowledgeTest() }

    /// Demo scenes and CI screenshots only: "Genauer Standort" is off (the fakes say so; nothing real is touched).
    func simulateApproximateLocation() {
        guard isSimulated, let scripted = engine.location as? ScriptedLocationProvider else { return }
        scripted.isReducedAccuracy = true
        refreshStatus()
    }

    /// "Alle Daten löschen" (Einstellungen › Daten): every alarm, the system alarms and circles of them and the saved book go.
    func deleteAll() {
        engine.reset()
        updateTicker()
    }

    /// "Wecker testen": rings in ten seconds like a real one.
    func startTest() async {
        await prepare(askForPermissions: true)
        engine.scheduleTest(after: 10, soundKey: ExitAlarmPrefs.shared.sound.rawValue)
        updateTicker()
    }

    // MARK: Permissions

    /// Asks for the system alarm (AlarmKit, else notifications) when the sheet turns an alarm on. Nothing is asked in
    /// simulated runs. Location is a separate step with its own explanation screen (`requestLocation`).
    func prepare(askForPermissions: Bool) async {
        guard let system, !isSimulated else { return }
        if askForPermissions { await system.requestPermissions() } else { await system.refresh() }
        refreshStatus()
    }

    /// The pre-prompt screen ended with "Weiter": the system's location prompt follows.
    func requestLocation(always: Bool) {
        guard !isSimulated else { return }
        engine.requestLocation(always: always)
    }

    func refreshStatus() {
        locationAuthorization = engine.location.authorization
        locationIsApproximate = engine.locationIsApproximate
        if let system {
            alarmKind = system.kind
            cannotRingInBackground = system.kind == .none
        }
    }

    // MARK: From the follow

    /// A fresh answer for the followed run: every alarm of the run takes the data of its stop.
    func followUpdated(tripID: String, stopovers: [Stopover]) {
        guard !book.active.isEmpty else { return }
        engine.timetable(tripID: tripID, stopovers: stopovers)
    }

    func followEnded(tripID: String) {
        guard !book.active.isEmpty else { return }
        engine.followEnded(tripID: tripID)
        updateTicker()
    }

    /// Live-Daten went off (kill switch, withdrawn consent): the alarms depend on live timetable data and end.
    func liveDataOff() {
        let affected = book.active
        guard !affected.isEmpty else { return }
        engine.liveDataOff()
        updateTicker()
        postSwitchedOffNotice(affected)
    }

    /// The alarms ended without the user's doing. Nobody may sleep on believing that an alarm is armed, so the app says it once
    /// (a normal notification; it is dropped silently when notifications are not allowed).
    private func postSwitchedOffNotice(_ alarms: [ExitAlarmState]) {
        guard !isSimulated else { return }
        let content = UNMutableNotificationContent()
        content.title = "Aussteige-Wecker ist aus"
        content.body = alarms.count == 1
            ? "Für \(alarms[0].spec.stopName) klingelt nichts mehr, weil Live-Daten ausgeschaltet sind. Stell den Wecker neu, wenn sie wieder an sind."
            : "Es klingelt nichts mehr, weil Live-Daten ausgeschaltet sind. Stell die Wecker neu, wenn sie wieder an sind."
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: "exitalarm.switchedoff", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// What the Live Activity shows while an alarm is armed.
    func activityInfo(now: Date = Date()) -> FollowExitAlarmInfo? {
        engine.book.activityInfo(now: now)
    }

    // MARK: Notification actions

    /// "Quittieren" and "5 Min später" of the notification path. Works without the store being open.
    func handleNotification(action: String, userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["exitAlarmID"] as? String else { return }
        restoreIfNeeded()
        switch action {
        case NotificationCategories.exitAlarmAcknowledge:
            id == ExitAlarmEngine.testID ? engine.acknowledgeTest() : engine.acknowledge(id: id)
        case NotificationCategories.exitAlarmSnooze:
            engine.snooze(id: id, minutes: 5)
        default:
            engine.tick()
        }
        updateTicker()
    }

    // MARK: Ticking

    private func engineChanged() {
        revision &+= 1
        locationAuthorization = engine.location.authorization
        locationIsApproximate = engine.locationIsApproximate
        if let system { alarmKind = system.kind }
        ExitAlarmWindow.shared.update()   // the full-screen moment shows or hides with the alarm's state
        refreshActivityIfNeeded()
    }

    /// The Live Activity says "Aussteigen in 4 Min" while an alarm is armed. When the alarm stops being armed (cancelled, rang, ended
    /// by Live-Daten off) or a new one appears, the follow refreshes its activity at once: a line that says "armed" after the alarm is
    /// gone would be a promise nobody keeps. Only a change of the line's shape counts, not the passing minutes.
    private func refreshActivityIfNeeded() {
        guard !isSimulated else { return }
        let info = engine.book.activityInfo(now: Date())
        let signature = info.map { "\($0.stopName)|\($0.isTransfer)|\($0.isApproaching)" }
        guard signature != activitySignature else { return }
        activitySignature = signature
        LiveFollowTracker.shared.exitAlarmChanged()
    }

    /// A tick every 5 seconds while an alarm is active (or a test waits): the app is awake then, in the foreground or kept
    /// alive by the location mode. With nothing active there is no timer at all.
    private func updateTicker() {
        let needed = engine.hasActiveAlarms || engine.testAt != nil
        if needed, ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self else { return }
                    self.engine.tick()
                    if !(self.engine.hasActiveAlarms || self.engine.testAt != nil) {
                        self.ticker = nil
                        return
                    }
                }
            }
        } else if !needed {
            ticker?.cancel()
            ticker = nil
        }
    }
}
