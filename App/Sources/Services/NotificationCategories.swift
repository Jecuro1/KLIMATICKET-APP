import UserNotifications

/// Every notification category of the app, registered in one place. `setNotificationCategories` replaces the whole set,
/// so two callers registering their own would drop each other's actions.
enum NotificationCategories {
    /// "Live verfolgen" notices (docs/OEBB_LIVE.md §R8). Actions: details, log the ride, stop following.
    static let followNotice = "live.follow"
    static let followDetails = "live.follow.details"
    static let followLog = "live.follow.log"
    static let followStop = "live.follow.stop"
    /// MARK: exitalarm – the Aussteige-Wecker notifications (docs/EXIT_ALARM.md §3). Actions: acknowledge, snooze.
    static let exitAlarm = "exitalarm"
    static let exitAlarmAcknowledge = "exitalarm.ack"
    static let exitAlarmSnooze = "exitalarm.snooze"

    static func registerAll() {
        // The location suggestion of TripDetectionService keeps its "Erfassen" action.
        let suggestion = UNNotificationCategory(
            identifier: TripDetectionService.notificationCategory,
            actions: [UNNotificationAction(identifier: TripDetectionService.confirmAction, title: "Erfassen", options: [])],
            intentIdentifiers: [])
        let follow = UNNotificationCategory(
            identifier: followNotice,
            actions: [
                UNNotificationAction(identifier: followDetails, title: "Details öffnen", options: [.foreground]),
                UNNotificationAction(identifier: followLog, title: "Fahrt erfassen", options: [.foreground]),
                UNNotificationAction(identifier: followStop, title: "Nicht mehr verfolgen", options: [.destructive]),
            ],
            intentIdentifiers: [])
        // MARK: exitalarm – "Quittieren" works without opening the app; "5 Min später" too (no .foreground option).
        let exitAlarmCategory = UNNotificationCategory(
            identifier: exitAlarm,
            actions: [
                UNNotificationAction(identifier: exitAlarmAcknowledge, title: "Quittieren", options: []),
                UNNotificationAction(identifier: exitAlarmSnooze, title: "5 Min später", options: []),
            ],
            intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([suggestion, follow, exitAlarmCategory])
    }
}
