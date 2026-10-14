import Foundation
import UserNotifications
import KlimaCore

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): what the app keeps on the device for the Alarms screen. Small JSON values in
// UserDefaults. Nothing here is sent anywhere, and nothing is in the cloud. A value that cannot be read counts as empty.

enum AlarmCalendar {
    /// The app's calendar for schedules: Vienna time, as the other notifications use.
    static let vienna: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }()
}

/// The last 30 delivered notices, and the moment the user last cleared them (older system notices do not come back).
enum NoticeHistoryStore {
    static let key = "alarms.history"
    static let clearedKey = "alarms.historyClearedAt"

    static func load(_ defaults: UserDefaults = .standard) -> NoticeHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(NoticeHistory.self, from: data) else { return NoticeHistory() }
        return history
    }

    static func save(_ history: NoticeHistory, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    static func clearedAt(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: clearedKey) as? Date
    }

    /// Empties the history. Notices the system still lists as delivered and that arrived before this moment stay out.
    static func clear(now: Date = Date(), defaults: UserDefaults = .standard) {
        save(NoticeHistory(), defaults: defaults)
        defaults.set(now, forKey: clearedKey)
    }

    /// Records one notice that was shown or delivered (the first record of an identifier wins).
    static func record(_ notice: DeliveredNotice, defaults: UserDefaults = .standard) {
        if let cleared = clearedAt(defaults), notice.deliveredAt <= cleared { return }
        var history = load(defaults)
        guard history.record(notice) else { return }
        save(history, defaults: defaults)
    }

    /// Merges the notices the system still lists as delivered. Returns the history afterwards.
    @discardableResult
    static func merge(_ notices: [DeliveredNotice], defaults: UserDefaults = .standard) -> NoticeHistory {
        let cleared = clearedAt(defaults)
        let fresh = notices.filter { notice in cleared.map { notice.deliveredAt > $0 } ?? true }
        var history = load(defaults)
        history.merge(fresh)
        save(history, defaults: defaults)
        return history
    }

    static func notice(from notification: UNNotification) -> DeliveredNotice {
        notice(identifier: notification.request.identifier, title: notification.request.content.title,
               body: notification.request.content.body, date: notification.date)
    }

    static func notice(identifier: String, title: String, body: String, date: Date) -> DeliveredNotice {
        DeliveredNotice(id: identifier, kind: AlarmIdentifier.kind(of: identifier), title: title, body: body, deliveredAt: date)
    }
}

/// The alarms that are switched off. Each one keeps what is needed to schedule it again.
enum PausedAlarmStore {
    static let key = "alarms.paused"

    static func load(_ defaults: UserDefaults = .standard) -> [PausedAlarm] {
        guard let data = defaults.data(forKey: key),
              let alarms = try? JSONDecoder().decode([PausedAlarm].self, from: data) else { return [] }
        return alarms
    }

    static func save(_ alarms: [PausedAlarm], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets the paused alarms of one row (a route or a ticket); used when the row is deleted or re-scheduled.
    static func removeGroup(_ groupKey: String, defaults: UserDefaults = .standard) {
        let kept = load(defaults).filter { AlarmIdentifier.groupKey(of: $0.id) != groupKey }
        save(kept, defaults: defaults)
    }
}

/// Maps the system's triggers to the values the app stores, and back.
enum AlarmTriggers {
    /// The next moment a pending notification fires; nil when it will not fire again.
    static func nextDate(of notificationTrigger: UNNotificationTrigger?) -> Date? {
        if let calendar = notificationTrigger as? UNCalendarNotificationTrigger { return calendar.nextTriggerDate() }
        if let interval = notificationTrigger as? UNTimeIntervalNotificationTrigger { return interval.nextTriggerDate() }
        return nil
    }

    static func trigger(of notificationTrigger: UNNotificationTrigger?) -> AlarmTrigger? {
        if let calendar = notificationTrigger as? UNCalendarNotificationTrigger {
            return .calendar(calendar.dateComponents, repeats: calendar.repeats)
        }
        if let interval = notificationTrigger as? UNTimeIntervalNotificationTrigger, let date = interval.nextTriggerDate() {
            return .once(date)
        }
        return nil
    }

    /// "Mo–Fr · 07:20" for repeating weekday triggers that share one clock time; nil for single moments and mixed patterns.
    static func scheduleText(of triggers: [AlarmTrigger]) -> String? {
        var weekdays = Set<RouteWeekday>()
        var clock: (hour: Int, minute: Int)?
        for trigger in triggers {
            guard trigger.repeats, let parts = trigger.components, let number = parts.weekday,
                  let day = RouteWeekday(calendarWeekday: number), let hour = parts.hour, let minute = parts.minute else { return nil }
            weekdays.insert(day)
            clock = (hour, minute)
        }
        guard !weekdays.isEmpty, let clock else { return nil }
        return RouteSchedule(weekdays: weekdays, hour: clock.hour, minute: clock.minute).summary
    }

    /// The system trigger for a stored one; nil when a single moment has passed. Calendar triggers carry Vienna's time zone,
    /// as the schedules do: the moment the Alarms screen shows is the moment the notification fires.
    static func notificationTrigger(for trigger: AlarmTrigger, now: Date) -> UNNotificationTrigger? {
        if var components = trigger.components {
            components.timeZone = AlarmCalendar.vienna.timeZone
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: trigger.repeats)
        }
        guard let date = trigger.date, date > now else { return nil }
        var parts = AlarmCalendar.vienna.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        parts.timeZone = AlarmCalendar.vienna.timeZone
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}
