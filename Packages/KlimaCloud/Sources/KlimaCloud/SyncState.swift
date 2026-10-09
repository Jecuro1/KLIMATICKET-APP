import Foundation

// MARK: - Sync owner & cursors (UserDefaults)

/// Which account the local data belongs to, plus per-account push time and per-table pull cursors.
///
/// Backend marker (contract §6.4): `claim` writes `sync.owner.backend = "cf1"`. An owner without it is a *legacy
/// owner* whose data was synced with the retired Supabase project; the first Cloudflare account adopts that data
/// silently instead of asking (see `SyncService`).
public enum SyncOwnerStore {
    public struct Owner: Equatable, Sendable {
        public var userID: String
        public var email: String?
        /// Claimed in the Supabase era (no backend marker).
        public var isLegacy: Bool

        public init(userID: String, email: String?, isLegacy: Bool = false) {
            self.userID = userID
            self.email = email
            self.isLegacy = isLegacy
        }
    }

    public static let backend = "cf1"
    public static let tables = SyncTables.all
    private static let ownerIDKey = "sync.owner.userID"
    private static let ownerEmailKey = "sync.owner.email"
    private static let ownerBackendKey = "sync.owner.backend"

    private static func lastPushKey(_ userID: String) -> String { "sync.user.\(userID.lowercased()).lastPush" }
    private static func cursorKey(_ table: String, _ userID: String) -> String { "sync.user.\(userID.lowercased()).rev.\(table)" }

    public static func owner(_ defaults: UserDefaults = .standard) -> Owner? {
        guard let id = defaults.string(forKey: ownerIDKey), !id.isEmpty else { return nil }
        return Owner(userID: id, email: defaults.string(forKey: ownerEmailKey),
                     isLegacy: defaults.string(forKey: ownerBackendKey) != backend)
    }

    public static func claim(userID: String, email: String?, _ defaults: UserDefaults = .standard) {
        defaults.set(userID.lowercased(), forKey: ownerIDKey)
        if let email { defaults.set(email, forKey: ownerEmailKey) } else { defaults.removeObject(forKey: ownerEmailKey) }
        defaults.set(backend, forKey: ownerBackendKey)
    }

    public static func lastPush(userID: String, _ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastPushKey(userID)) as? Date
    }

    public static func setLastPush(_ date: Date?, userID: String, _ defaults: UserDefaults = .standard) {
        if let date { defaults.set(date, forKey: lastPushKey(userID)) } else { defaults.removeObject(forKey: lastPushKey(userID)) }
    }

    public static func cursor(table: String, userID: String, _ defaults: UserDefaults = .standard) -> Int64 {
        (defaults.object(forKey: cursorKey(table, userID)) as? NSNumber)?.int64Value ?? 0
    }

    public static func setCursor(_ rev: Int64, table: String, userID: String, _ defaults: UserDefaults = .standard) {
        defaults.set(NSNumber(value: rev), forKey: cursorKey(table, userID))
    }

    public static func resetPullCursors(userID: String, _ defaults: UserDefaults = .standard) {
        for table in tables { defaults.removeObject(forKey: cursorKey(table, userID)) }
    }

    /// Forgets an account entirely (after account deletion): ownership, push time and cursors.
    public static func forget(userID: String, _ defaults: UserDefaults = .standard) {
        if owner(defaults)?.userID == userID.lowercased() {
            defaults.removeObject(forKey: ownerIDKey)
            defaults.removeObject(forKey: ownerEmailKey)
            defaults.removeObject(forKey: ownerBackendKey)
        }
        defaults.removeObject(forKey: lastPushKey(userID))
        resetPullCursors(userID: userID, defaults)
    }
}

// MARK: - Merge rule

public enum SyncMergeRule {
    public enum Action: Equatable, Sendable {
        case insert, apply, keep
    }

    /// - localUpdatedAt: nil when the row does not exist on this device.
    /// - localIsDirty: the local row changed after this sync's push started (and not "in the future"), i.e. the server
    ///   has not seen it yet.
    /// - sameContent: local and remote rows are identical (incl. updated_at / deleted_at).
    public static func action(localUpdatedAt: Date?, localIsDirty: Bool, remoteUpdatedAt: Date, remoteIsDeleted: Bool,
                              sameContent: Bool) -> Action {
        guard let localUpdatedAt else { return remoteIsDeleted ? .keep : .insert }   // unknown tombstone: nothing to do
        if sameContent { return .keep }
        // Unpushed local edit: last writer wins, exactly like the server will decide when it gets pushed.
        if localIsDirty { return remoteUpdatedAt > localUpdatedAt ? .apply : .keep }
        // Already pushed: the server's row is authoritative (it rejected stale writes and clamped skewed clocks).
        return .apply
    }
}
