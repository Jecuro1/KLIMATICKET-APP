import ActivityKit
import Foundation
import AlarmKit
import SwiftUI
import UserNotifications
import KlimaCore

// Aussteige-Wecker: the system alarms (docs/EXIT_ALARM.md §3, §5).
//
//   1. AlarmKit (iOS 26): a real alarm that rings through silent mode and Focus and shows on the Lock Screen. It needs the
//      user's permission (NSAlarmKitUsageDescription) and no entitlement. The app tries it first.
//   2. Local notifications as the fallback: three in a row, 20 seconds apart, at the normal level. Time-sensitive and
//      critical notifications need an entitlement that a sideloaded app does not have, so silent mode and Focus can mute these.
//      Settings and the sheet say which kind the device is using.
//
// Neither kind asks for its permission here: the sheet does that when the user turns an alarm on. The ids are the engine's.

// MARK: AlarmKit

final class AlarmKitExitScheduler {
    private let manager = AlarmManager.shared
    /// Watches the alarms of AlarmKit while the app runs (started with the first alarm that is scheduled).
    private var observer: Task<Void, Never>?
    /// `alerting` and `ownEnds` are touched by the observer task and by the calls of the scheduler's chain: one lock for both.
    private let lock = NSLock()
    private var alerting: Set<UUID> = []
    /// Alarms that left the alerting state because the app cancelled, stopped or replaced them. AlarmKit reports that like a stop
    /// by the user; the app must not hear it as one (a snooze would turn into an acknowledgement).
    private var ownEnds: Set<UUID> = []
    var onEvent: ((ExitAlarmSchedulerEvent) -> Void)?

    var authorization: AlarmManager.AuthorizationState { manager.authorizationState }
    var isAuthorized: Bool { manager.authorizationState == .authorized }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let state = try? await manager.requestAuthorization() else { return false }
        return state == .authorized
    }

    func schedule(_ content: ExitAlarmRingContent, at date: Date) async throws {
        let attributes = AlarmAttributes<ExitAlarmMetadata>(
            presentation: AlarmPresentation(alert: Self.alert(content)),
            metadata: ExitAlarmMetadata(stopName: content.stopName, lineName: content.lineName, kind: content.kind.rawValue),
            tintColor: Theme.accent)
        let sound: ActivityKit.AlertConfiguration.AlertSound = ExitAlarmSound.from(key: content.soundKey).fileName.map { .named($0) } ?? .default
        let configuration = AlarmManager.AlarmConfiguration<ExitAlarmMetadata>.alarm(
            schedule: .fixed(date), attributes: attributes, stopIntent: nil, secondaryIntent: ExitAlarmOpenIntent(), sound: sound)
        _ = try await manager.schedule(id: ExitAlarmUUID.make(from: content.id), configuration: configuration)
        startObserving(id: content.id)
    }

    func cancel(id: String) {
        let uuid = ExitAlarmUUID.make(from: id)
        markOwnEnd(uuid)
        try? manager.cancel(id: uuid)
    }

    func stop(id: String) {
        let uuid = ExitAlarmUUID.make(from: id)
        markOwnEnd(uuid)
        try? manager.stop(id: uuid)
    }

    /// Only an alarm that rings can produce the echo; marking an idle one would swallow a later stop by the user.
    private func markOwnEnd(_ uuid: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if alerting.contains(uuid) { ownEnds.insert(uuid) }
    }

    /// What changed in the set of ringing alarms: the ones that started, and the ones the user ended.
    private func diff(_ now: Set<UUID>) -> (started: Set<UUID>, ended: Set<UUID>) {
        lock.lock()
        defer { lock.unlock() }
        let started = now.subtracting(alerting)
        var ended = alerting.subtracting(now)
        alerting = now
        for uuid in started { ownEnds.remove(uuid) }
        for uuid in ended where ownEnds.remove(uuid) != nil { ended.remove(uuid) }
        return (started, ended)
    }

    /// The alarm the system shows. The title is the one line the Lock Screen reads; the "Öffnen" button opens the app.
    private static func alert(_ content: ExitAlarmRingContent) -> AlarmPresentation.Alert {
        let title: LocalizedStringResource = "\(content.title) \(content.body)"
        let open = AlarmButton(text: "Öffnen", textColor: Theme.accent, systemImageName: "arrow.up.forward.app")
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title, secondaryButton: open, secondaryButtonBehavior: .custom)
        }
        let stop = AlarmButton(text: "Stopp", textColor: Theme.accent, systemImageName: "stop.circle")
        return AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: open, secondaryButtonBehavior: .custom)
    }

    /// While the app runs: an alarm that starts alerting reports `rang`, one that stops after alerting reports `stopped`
    /// (the user pressed the system's stop button).
    private func startObserving(id: String) {
        guard observer == nil else { return }
        observer = Task { [weak self] in
            guard let manager = self?.manager else { return }
            for await alarms in manager.alarmUpdates {
                guard let self else { return }
                let (started, ended) = self.diff(Set(alarms.filter { $0.state == .alerting }.map(\.id)))
                await MainActor.run {
                    for uuid in started { self.report(.rang, uuid: uuid) }
                    for uuid in ended { self.report(.stopped, uuid: uuid) }
                }
            }
        }
    }

    private enum Kind { case rang, stopped }
    /// The engine ids live in `ExitAlarmUUID.make(from:)`, which cannot be inverted: the service keeps the map.
    var idForUUID: (UUID) -> String? = { _ in nil }

    @MainActor
    private func report(_ kind: Kind, uuid: UUID) {
        guard let id = idForUUID(uuid) else { return }
        onEvent?(kind == .rang ? .rang(id) : .stopped(id))
    }
}

// MARK: Notifications

final class NotificationExitScheduler {
    static let spacing: TimeInterval = 20
    static let repeats = 3
    static let category = "exitalarm"

    private let center = UNUserNotificationCenter.current()

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Three notifications from `date` on, 20 seconds apart. An alarm with the same id is replaced.
    func schedule(_ content: ExitAlarmRingContent, at date: Date) async -> Bool {
        let status = await status()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        cancel(id: content.id)
        var added = false
        for index in 0..<Self.repeats {
            let fire = date.addingTimeInterval(Double(index) * Self.spacing)
            let interval = max(fire.timeIntervalSinceNow, 1)
            let note = UNMutableNotificationContent()
            note.title = content.title
            note.body = content.body
            note.sound = Self.sound(content.soundKey)
            note.categoryIdentifier = Self.category
            note.threadIdentifier = "exitalarm.\(ExitAlarmUUID.make(from: content.id).uuidString)"
            note.userInfo = ["exitAlarmID": content.id]
            // The normal level on purpose: .timeSensitive and .critical need an entitlement a sideloaded build does not have.
            note.interruptionLevel = .active
            let request = UNNotificationRequest(identifier: Self.identifier(content.id, index), content: note,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            if (try? await center.add(request)) != nil { added = true }
        }
        return added
    }

    func cancel(id: String) {
        let ids = (0..<Self.repeats).map { Self.identifier(id, $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func identifier(_ id: String, _ index: Int) -> String {
        "exitalarm.\(ExitAlarmUUID.make(from: id).uuidString).\(index)"
    }

    static func sound(_ key: String) -> UNNotificationSound {
        ExitAlarmSound.from(key: key).fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
    }
}

// MARK: The scheduler the engine uses

/// AlarmKit when the user allowed it, else local notifications, else nothing. `kind` says which one a new alarm uses.
final class SystemExitAlarmScheduler: ExitAlarmScheduling {
    private let alarmKit = AlarmKitExitScheduler()
    private let notifications = NotificationExitScheduler()
    private var notificationsAllowed = false
    private var ids: [UUID: String] = [:]
    /// The last AlarmKit attempt failed (the system said no): `kind` then says what really rings, the notifications.
    private(set) var alarmKitFailed = false
    /// Called on the main actor when what `kind` says may have changed (a permission answered, an attempt failed or worked).
    var onStatusChange: (() -> Void)?
    var onEvent: ((ExitAlarmSchedulerEvent) -> Void)? {
        didSet { alarmKit.onEvent = onEvent }
    }

    init() {
        alarmKit.idForUUID = { [weak self] uuid in self?.ids[uuid] }
        Task { await refresh() }
    }

    var kind: ExitAlarmKind {
        if alarmKit.isAuthorized, !alarmKitFailed { return .alarmKit }
        return notificationsAllowed ? .notifications : .none
    }

    var alarmKitState: AlarmManager.AuthorizationState { alarmKit.authorization }

    /// Reads the two permissions again (after the sheet asked, after the user came back from Settings).
    func refresh() async {
        let status = await notifications.status()
        notificationsAllowed = status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Asks for what is needed: AlarmKit first; the notification permission only when AlarmKit is not allowed.
    func requestPermissions() async {
        if await alarmKit.requestAuthorization() == false {
            _ = await notifications.requestAuthorization()
        }
        await refresh()
    }

    func schedule(_ content: ExitAlarmRingContent, at date: Date) {
        ids[ExitAlarmUUID.make(from: content.id)] = content.id
        enqueue { await self.place(content, at: date) }
    }

    func cancel(id: String) {
        enqueue {
            self.alarmKit.cancel(id: id)
            self.notifications.cancel(id: id)
        }
    }

    func ringNow(_ content: ExitAlarmRingContent) {
        ids[ExitAlarmUUID.make(from: content.id)] = content.id
        enqueue { await self.place(content, at: Date().addingTimeInterval(2)) }
    }

    func stopRinging(id: String) {
        enqueue {
            self.alarmKit.stop(id: id)
            self.notifications.cancel(id: id)
        }
    }

    /// The calls to the system run one after another in the order the engine made them (a cancel must not overtake a schedule).
    private var chain: Task<Void, Never>?
    private func enqueue(_ operation: @escaping () async -> Void) {
        let previous = chain
        chain = Task {
            await previous?.value
            await operation()
        }
    }

    private func place(_ content: ExitAlarmRingContent, at date: Date) async {
        if alarmKit.isAuthorized {
            alarmKit.cancel(id: content.id)   // an alarm of the same id is replaced, not stacked
            do {
                try await alarmKit.schedule(content, at: date)
                await MainActor.run {
                    alarmKitFailed = false
                    onStatusChange?()
                }
                return
            } catch {
                // Too many alarms or the system said no: the notifications take over below, and the status says so.
                await MainActor.run {
                    alarmKitFailed = true
                    onStatusChange?()
                }
            }
        }
        if await notifications.schedule(content, at: date) { return }
        await MainActor.run { onEvent?(.failed(content.id)) }
    }
}
