import Foundation

/// Quick logs from widgets, Control Center and Siri are queued in the App Group and ingested by the app.
/// (Writing to SwiftData from another process would not refresh the app's live queries.)
struct PendingQuickLog: Codable, Hashable, Sendable {
    var favoriteID: UUID
    var date: Date
}

enum QuickLogQueue {
    static let key = "quicklog.pending.v1"
    static let didEnqueue = Notification.Name("KBQuickLogDidEnqueue")

    static func enqueue(favoriteID: UUID, date: Date = Date()) {
        var items = pending()
        items.append(PendingQuickLog(favoriteID: favoriteID, date: date))
        if let data = try? JSONEncoder().encode(items) { AppGroup.defaults.set(data, forKey: key) }
        // Optimistic widget update.
        if var snapshot = WidgetSnapshot.load(), let fav = snapshot.favorites.first(where: { $0.id == favoriteID }) {
            snapshot.apply(favorite: fav, date: date)
            snapshot.save()
        }
        NotificationCenter.default.post(name: didEnqueue, object: nil)
    }

    static func pending() -> [PendingQuickLog] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingQuickLog].self, from: data)) ?? []
    }

    /// Returns and clears all pending logs.
    static func drain() -> [PendingQuickLog] {
        let items = pending()
        remove(items)
        return items
    }

    /// Removes exactly `items` (once each), keeping logs another process queued in the meantime.
    static func remove(_ items: [PendingQuickLog]) {
        guard !items.isEmpty else { return }
        var toRemove: [PendingQuickLog: Int] = [:]
        for item in items { toRemove[item, default: 0] += 1 }
        var remaining: [PendingQuickLog] = []
        for item in pending() {
            if let count = toRemove[item], count > 0 {
                toRemove[item] = count - 1
            } else {
                remaining.append(item)
            }
        }
        if remaining.isEmpty {
            AppGroup.defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(remaining) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }
}
