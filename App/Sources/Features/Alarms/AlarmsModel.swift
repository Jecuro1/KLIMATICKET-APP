import Foundation
import Observation
import UserNotifications
import KlimaCore

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): the state of the Alarms screen. It reads what is pending in the system and what
// the app keeps (the live follow, the paused alarms, the weekly summary, the history). Nothing here makes a request.
// Live notices (Live verfolgen) are delivered at once and are not pending, so they show as the active follow only.

@MainActor
@Observable
final class AlarmsModel {
    private(set) var items: [AlarmItem] = []
    private(set) var history: [DeliveredNotice] = []
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var pendingCount = 0
    private(set) var isLoaded = false
    @ObservationIgnored private let demoScene: AlarmsDemoScene?

    init(demo: AlarmsDemoScene? = nil) {
        demoScene = demo
        guard let demo else { return }
        authorization = demo.authorization
        items = AlarmSorting.sorted(demo.items)
        pendingCount = demo.pendingCount
        history = demo.history
        isLoaded = true
    }

    // MARK: Reading

    /// Reads the system's pending and delivered notifications and the app's own records.
    func reload(app: AppState, routes: [FavoriteRouteEntity]) async {
        guard demoScene == nil else { return }
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let titles = Dictionary(routes.map { ($0.id.uuidString, $0.displayTitle) }, uniquingKeysWith: { first, _ in first })
        authorization = await center.notificationSettings().authorizationStatus
        let pending = await center.pendingNotificationRequests()
        pendingCount = pending.count

        // Only the kinds that have a row of their own; the weekly summary is read from the settings below.
        let listed = pending.filter { request in
            let kind = AlarmIdentifier.kind(of: request.identifier)
            return kind != .other && kind != .weeklySummary && kind != .liveFollow
        }
        let groups = Dictionary(grouping: listed) { AlarmIdentifier.groupKey(of: $0.identifier) }
        var rows: [AlarmItem] = []
        for (key, requests) in groups {
            if let row = pendingRow(key: key, requests: requests, titles: titles, now: now) { rows.append(row) }
        }
        rows += pausedRows(pendingKeys: Set(groups.keys), titles: titles, now: now)
        if let record = FollowRecordStore.load() { rows.append(liveFollowRow(record, now: now)) }
        rows.append(weeklyRow(enabled: app.settings.weeklySummaryEnabled, now: now))
        items = AlarmSorting.sorted(rows)

        let delivered = await center.deliveredNotifications()
        history = NoticeHistoryStore.merge(delivered.map(NoticeHistoryStore.notice(from:))).entries
        isLoaded = true
    }

    private func pendingRow(key: String, requests: [UNNotificationRequest], titles: [String: String], now: Date) -> AlarmItem? {
        let dated = requests
            .compactMap { request -> (request: UNNotificationRequest, date: Date)? in
                guard let date = AlarmTriggers.nextDate(of: request.trigger) else { return nil }
                return (request, date)
            }
            .sorted { $0.date < $1.date }
        guard let first = dated.first else { return nil }
        let request = first.request
        let kind = AlarmIdentifier.kind(of: request.identifier)
        let isRoute = kind == .routeReminder
        let routeTitle = AlarmIdentifier.routeID(of: request.identifier).flatMap { titles[$0] }
        return AlarmItem(id: key, kind: kind,
                         title: isRoute ? (routeTitle ?? "Gespeicherte Route") : request.content.title,
                         detail: isRoute ? request.content.title : request.content.body,
                         nextDate: first.date,
                         scheduleText: AlarmTriggers.scheduleText(of: requests.compactMap { AlarmTriggers.trigger(of: $0.trigger) }),
                         isOn: true)
    }

    private func pausedRows(pendingKeys: Set<String>, titles: [String: String], now: Date) -> [AlarmItem] {
        let groups = Dictionary(grouping: PausedAlarmStore.load()) { AlarmIdentifier.groupKey(of: $0.id) }
        var rows: [AlarmItem] = []
        for (key, records) in groups where !pendingKeys.contains(key) {
            let ordered = records.sorted { $0.id < $1.id }
            guard let first = ordered.first else { continue }
            let dates = ordered.compactMap { $0.trigger.nextDate(after: now, calendar: AlarmCalendar.vienna) }
            let isRoute = first.kind == .routeReminder
            let routeTitle = AlarmIdentifier.routeID(of: first.id).flatMap { titles[$0] }
            rows.append(AlarmItem(id: key, kind: first.kind,
                                  title: isRoute ? (routeTitle ?? "Gespeicherte Route") : first.title,
                                  detail: isRoute ? "Pausiert · \(first.title)" : first.body,
                                  nextDate: dates.min(),
                                  scheduleText: AlarmTriggers.scheduleText(of: ordered.map(\.trigger)),
                                  isOn: false, canResume: !dates.isEmpty))
        }
        return rows
    }

    private func liveFollowRow(_ record: FollowRecord, now: Date) -> AlarmItem {
        let target = record.target
        let departure = target.plannedDeparture.flatMap { $0 > now ? $0 : nil }
        return AlarmItem(id: "liveFollow", kind: .liveFollow, title: "Live verfolgen · \(target.lineName)",
                         detail: "\(target.boardingStop.name) → \(target.alightStop.name)", nextDate: departure, isOn: true)
    }

    private func weeklyRow(enabled: Bool, now: Date) -> AlarmItem {
        var components = DateComponents()
        components.weekday = 1
        components.hour = 18
        components.minute = 0
        let next = AlarmCalendar.vienna.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
        return AlarmItem(id: AlarmIdentifier.weeklySummary, kind: .weeklySummary, title: "Wochenrückblick",
                         detail: "Wie viel du diese Woche gespart hast – und ob alle Fahrten erfasst sind.",
                         nextDate: enabled ? next : nil, scheduleText: "So · 18:00", isOn: enabled)
    }

    // MARK: Actions

    /// Switches an alarm on or off. Off removes its notification and keeps what is needed to schedule it again.
    func setOn(_ item: AlarmItem, _ on: Bool, app: AppState, routes: [FavoriteRouteEntity]) async {
        if demoScene != nil {
            items = AlarmSorting.sorted(items.map { row in
                var row = row
                if row.id == item.id { row.isOn = on }
                return row
            })
            return
        }
        switch item.kind {
        case .liveFollow:
            if !on { LiveFollowTracker.shared.stop() }
        case .weeklySummary:
            app.settings.weeklySummaryEnabled = on
            await NotificationService().setWeeklySummary(enabled: on)
        default:
            if on {
                let resumed = await resume(group: item.id)
                if !resumed {
                    app.showToast("bell.slash.fill", "Alarm bleibt aus", "Erlaube Mitteilungen in den iOS-Einstellungen, dann schaltest du ihn wieder ein.")
                }
            } else {
                await pause(group: item.id)
            }
        }
        await reload(app: app, routes: routes)
    }

    /// Removes an alarm for good. A route's reminders belong to its schedule, so they go together with it.
    func remove(_ item: AlarmItem, app: AppState, routes: [FavoriteRouteEntity], repository: Repository) async {
        guard demoScene == nil else {
            items = AlarmSorting.sorted(items.filter { $0.id != item.id })
            return
        }
        switch item.kind {
        case .liveFollow:
            LiveFollowTracker.shared.stop()
        case .weeklySummary:
            app.settings.weeklySummaryEnabled = false
            await NotificationService().setWeeklySummary(enabled: false)
        case .routeReminder:
            let routeID = String(item.id.dropFirst(AlarmIdentifier.routePrefix.count))
            if let route = routes.first(where: { $0.id.uuidString == routeID }) {
                route.schedule = nil
                route.touch()
                repository.commit()
            }
            await SavedRouteReminders.removeReminders(routeID: routeID)
        default:
            await dropPending(group: item.id)
            PausedAlarmStore.removeGroup(item.id)
        }
        await reload(app: app, routes: routes)
    }

    /// Empties the history on the device.
    func clearHistory() {
        NoticeHistoryStore.clear()
        history = []
    }

    private func pause(group key: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().filter { request in
            AlarmIdentifier.groupKey(of: request.identifier) == key && AlarmIdentifier.kind(of: request.identifier) != .other
        }
        guard !pending.isEmpty else { return }
        var paused = PausedAlarmStore.load()
        let now = Date()
        for request in pending {
            guard let trigger = AlarmTriggers.trigger(of: request.trigger) else { continue }
            paused.removeAll { $0.id == request.identifier }
            paused.append(PausedAlarm(id: request.identifier, kind: AlarmIdentifier.kind(of: request.identifier),
                                      title: request.content.title, body: request.content.body, trigger: trigger, pausedAt: now))
        }
        PausedAlarmStore.save(paused)
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
    }

    /// Schedules the paused alarms of one row again. Asks for the system permission when it was never asked. Without the
    /// permission nothing is scheduled and the alarm stays paused. An alarm leaves the paused list only once iOS accepted
    /// it; a moment that has passed is dropped. Returns false when an alarm could not be scheduled.
    private func resume(group key: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
        let now = Date()
        var paused = PausedAlarmStore.load()
        var allResumed = true
        for record in paused where AlarmIdentifier.groupKey(of: record.id) == key {
            guard let trigger = AlarmTriggers.notificationTrigger(for: record.trigger, now: now) else {
                paused.removeAll { $0.id == record.id }
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = record.title
            content.body = record.body
            content.sound = .default
            content.threadIdentifier = record.kind == .routeReminder ? AlarmIdentifier.routePrefix + (AlarmIdentifier.routeID(of: record.id) ?? "") : "alarms"
            do {
                try await center.add(UNNotificationRequest(identifier: record.id, content: content, trigger: trigger))
                paused.removeAll { $0.id == record.id }
            } catch {
                allResumed = false
            }
        }
        PausedAlarmStore.save(paused)
        return allResumed
    }

    private func dropPending(group key: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { AlarmIdentifier.groupKey(of: $0) == key }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
