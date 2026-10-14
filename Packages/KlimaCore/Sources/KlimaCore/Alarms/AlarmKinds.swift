import Foundation

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): what a notification of the app is about. The identifier prefixes are written by
// the app's schedulers and read back by the Alarms screen, so they are a contract: changing one orphans the alarms already
// scheduled on the device.

public enum AlarmKind: String, CaseIterable, Codable, Sendable, Hashable {
    /// „Live verfolgen“: the active follow of a train (the follow itself, not a pending notification).
    case liveFollow
    /// „Abfahrt in N Min“ of a planned connection.
    case departure
    /// The reminder of a saved route with a weekday/time pattern.
    case routeReminder
    /// „Dein Ticket läuft ab“ (the expiry reminders of the ticket).
    case ticketRenewal
    /// The reminder before the renewal letter that carries the objection deadline.
    case objectionLetter
    /// „Fahrgastrechte: Entschädigung prüfen“.
    case passengerRights
    /// Sunday's week review.
    case weeklySummary
    /// Notices that have no alarm of their own (break-even, trip suggestion, …): history only.
    case other

    /// The order of the sections on the Alarms screen.
    public var sortRank: Int {
        switch self {
        case .liveFollow: 0
        case .departure: 1
        case .routeReminder: 2
        case .ticketRenewal: 3
        case .objectionLetter: 4
        case .passengerRights: 5
        case .weeklySummary: 6
        case .other: 7
        }
    }
}

public enum AlarmIdentifier {
    public static let liveFollowPrefix = "livefollow-"
    public static let departurePrefix = "planner.reminder."
    public static let routePrefix = "route."
    public static let renewalPrefix = "renewal."
    public static let objectionPrefix = "advisor.renewal."
    public static let passengerRightsPrefix = "perk.passengerRights."
    public static let weeklySummary = "weekly.summary"

    /// The kind an identifier belongs to. `.other` for anything the Alarms screen does not manage on its own.
    public static func kind(of identifier: String) -> AlarmKind {
        if identifier.hasPrefix(liveFollowPrefix) { return .liveFollow }
        if identifier.hasPrefix(departurePrefix) { return .departure }
        if identifier.hasPrefix(routePrefix) { return .routeReminder }
        if identifier.hasPrefix(objectionPrefix) { return .objectionLetter }
        if identifier.hasPrefix(renewalPrefix) { return .ticketRenewal }
        if identifier.hasPrefix(passengerRightsPrefix) { return .passengerRights }
        if identifier == weeklySummary { return .weeklySummary }
        return .other
    }

    /// Identifier of the reminder of one weekday of a saved route: "route.<route id>.<weekday number>".
    public static func routeReminder(routeID: String, weekday: RouteWeekday) -> String {
        "\(routeReminderPrefix(routeID: routeID))\(weekday.rawValue)"
    }

    /// Prefix shared by all reminders of one saved route ("route.<route id>.").
    public static func routeReminderPrefix(routeID: String) -> String {
        "\(routePrefix)\(routeID)."
    }

    /// The row an identifier belongs to on the Alarms screen: all weekday reminders of one saved route ("route.<id>"), all
    /// expiry reminders of one ticket ("renewal.<uuid>"), anything else on its own.
    public static func groupKey(of identifier: String) -> String {
        switch kind(of: identifier) {
        case .routeReminder:
            return routeID(of: identifier).map { routePrefix + $0 } ?? identifier
        case .ticketRenewal:
            guard let dot = identifier.lastIndex(of: ".") else { return identifier }
            return String(identifier[..<dot])
        default:
            return identifier
        }
    }

    /// The saved route a route reminder belongs to; nil for any other identifier.
    public static func routeID(of identifier: String) -> String? {
        guard kind(of: identifier) == .routeReminder else { return nil }
        let parts = identifier.dropFirst(routePrefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return String(parts[0])
    }
}
