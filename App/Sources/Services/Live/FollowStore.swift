import Foundation
import KlimaCore

// Live verfolgen: what the app keeps on this device about the follow and the notice switches (docs/OEBB_LIVE.md §R8).
// UserDefaults only, never sent anywhere. The notice switches live here and not only in `AppSettings`, so the background
// refresh reads the same values the Settings screen wrote.

/// Einstellungen › Live-Mitteilungen. Off until the user switches it on.
enum FollowNoticeStore {
    static let key = "followNotices"

    static func load(_ defaults: UserDefaults = .standard) -> FollowNoticeSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(FollowNoticeSettings.self, from: data) else {
            return FollowNoticeSettings()
        }
        return settings
    }

    static func save(_ settings: FollowNoticeSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// The active follow as it survives a relaunch or a background refresh.
struct FollowRecord: Codable {
    var target: LiveFollowTarget
    var snapshot: LiveFollowSnapshot?
    var ledger: FollowNoticeLedger
    var activityID: String?
    var startedAt: Date
}

enum FollowRecordStore {
    static let key = "liveFollow.active"

    static func load(_ defaults: UserDefaults = .standard) -> FollowRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FollowRecord.self, from: data)
    }

    /// `nil` removes the record.
    static func save(_ record: FollowRecord?, defaults: UserDefaults = .standard) {
        guard let record else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: key) }
    }
}
