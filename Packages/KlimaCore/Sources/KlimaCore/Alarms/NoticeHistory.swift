import Foundation

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): the history of delivered notices, kept on the device only. The app records a
// notice when it is shown in the app and merges the notices the system still lists as delivered.

/// A notice that reached the device.
public struct DeliveredNotice: Codable, Hashable, Sendable, Identifiable {
    /// The notification request identifier: unique per notice.
    public var id: String
    public var kind: AlarmKind
    public var title: String
    public var body: String
    public var deliveredAt: Date

    public init(id: String, kind: AlarmKind, title: String, body: String, deliveredAt: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.deliveredAt = deliveredAt
    }
}

/// The newest `limit` delivered notices, newest first, each identifier once.
public struct NoticeHistory: Codable, Hashable, Sendable {
    public static let limit = 30

    public private(set) var entries: [DeliveredNotice]

    public init(entries: [DeliveredNotice] = []) {
        self.entries = NoticeHistory.normalized(entries)
    }

    /// Adds a notice unless its identifier is known already (the first record wins). Returns whether it was added.
    @discardableResult
    public mutating func record(_ notice: DeliveredNotice) -> Bool {
        guard !entries.contains(where: { $0.id == notice.id }) else { return false }
        entries = NoticeHistory.normalized(entries + [notice])
        return true
    }

    /// Records several notices, in any order.
    public mutating func merge(_ notices: [DeliveredNotice]) {
        entries = NoticeHistory.normalized(entries + notices)
    }

    public mutating func clear() {
        entries = []
    }

    /// Newest first, one entry per identifier, at most `limit`.
    static func normalized(_ entries: [DeliveredNotice]) -> [DeliveredNotice] {
        var seen = Set<String>()
        let newestFirst = entries.sorted { a, b in
            a.deliveredAt != b.deliveredAt ? a.deliveredAt > b.deliveredAt : a.id < b.id
        }
        var unique: [DeliveredNotice] = []
        for entry in newestFirst where seen.insert(entry.id).inserted {
            unique.append(entry)
            if unique.count == limit { break }
        }
        return unique
    }
}
