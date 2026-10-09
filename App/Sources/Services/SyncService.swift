import Foundation
import SwiftData
import KlimaCore

/// Two-way cloud sync with Supabase/PostgREST (server contract: supabase/migrations/0002_sync_hardening.sql).
///
/// • Push: rows whose `updatedAt` is newer than the last successful push of this account (device clock compared with
///   the same device clock only), as bulk upserts with uniform keys.
/// • Pull: keyset pages on the server-assigned `server_rev`, cursor per table and account – never the device clock,
///   never truncated by the server's "Max rows" limit.
/// • Conflicts: the server decides (last writer wins on `updated_at`, stale writes skipped, far-future clocks clamped).
///   Locally only edits that were not pushed yet are protected; everything else follows the server.
/// • Deletes are soft (`deleted_at`).
/// • Owner guard: local data is linked to the account it was synced with. When another account signs in, sync pauses
///   (`pendingAccountSwitch`) until the user decides between `discardLocalDataAndSync` and `mergeLocalDataIntoAccount`.
@Observable
@MainActor
final class SyncService {
    enum State: Equatable {
        case disabled
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    /// Another account signed in than the one whose data is on this device. Nothing is uploaded or downloaded until
    /// the user picks `discardLocalDataAndSync`, `mergeLocalDataIntoAccount` or `cancelAccountSwitch`.
    struct AccountSwitch: Equatable, Sendable {
        var previousUserID: String
        var previousEmail: String?
        var newUserID: String
        var newEmail: String?
        /// Tickets, trips, favourites and benefits on this device (without deleted ones).
        var localItemCount: Int
        /// Entries (incl. deletions) changed after the last successful sync with the previous account –
        /// they exist only on this device and are lost when discarding.
        var unsyncedItemCount: Int
    }

    private(set) var state: State
    private(set) var pendingAccountSwitch: AccountSwitch?
    /// True while sync waits for the account-switch decision.
    var isPaused: Bool { pendingAccountSwitch != nil }

    private let client: SupabaseClient?
    private let defaults = UserDefaults.standard
    private var isRunning = false
    private var rerunRequested = false

    static let pageSize = 500
    static let pushChunkSize = 500
    /// Re-read window behind the pull cursor in µs (server_rev is server time in µs): covers transactions that
    /// committed after rows with a higher revision were already read. Re-read rows merge as no-ops.
    static let pullOverlap: Int64 = 120_000_000
    static let onConflict = "user_id,id"

    init(config: AppConfig) {
        if let url = config.supabase {
            client = SupabaseClient(baseURL: url, anonKey: config.supabaseAnonKey)
            state = .idle
        } else {
            client = nil
            state = .disabled
        }
    }

    /// Time of the last successful sync (display only – not used as a cursor).
    var lastSync: Date? { defaults.object(forKey: "sync.lastSync") as? Date }

    func sync(context: ModelContext, auth: AuthService) async {
        await run(.normal, context: context, auth: auth)
    }

    /// Account switch, option 1: replace everything on this device with the signed-in account's data.
    /// Local data (and changes not yet synced with the previous account) is deleted only after the new account's data
    /// was downloaded completely, so a failed download changes nothing.
    func discardLocalDataAndSync(context: ModelContext, auth: AuthService) async {
        await run(.replaceLocal, context: context, auth: auth)
    }

    /// Account switch, option 2: upload everything on this device into the signed-in account, then sync normally.
    func mergeLocalDataIntoAccount(context: ModelContext, auth: AuthService) async {
        await run(.mergeLocal, context: context, auth: auth)
    }

    /// Account switch, option 3: keep the device as it is and sign the new account out again.
    func cancelAccountSwitch(auth: AuthService) async {
        pendingAccountSwitch = nil
        await auth.signOut()
        if state != .disabled { state = .idle }
    }

    /// Forces a full download on the next sync (e.g. after sign-out). Keeps the owner, so another account signing in
    /// still triggers the account-switch decision.
    func resetSyncCursor() {
        defaults.removeObject(forKey: "sync.lastSync")
        if let owner = SyncOwnerStore.owner(defaults) {
            SyncOwnerStore.resetPullCursors(userID: owner.userID, defaults)
        }
        pendingAccountSwitch = nil
        if state != .disabled, state != .syncing { state = .idle }
    }

    /// "Alles löschen" for a signed-in cloud account: a plain local delete would come back with the next full
    /// download (cursor reset after sign-out, a new device, the overlap window). So every row first becomes a
    /// tombstone (`deleted_at`), the tombstones are uploaded, and only then are the tombstones removed from this
    /// device. Returns false when the upload failed – the rows then stay on the device as (hidden) tombstones and the
    /// next sync uploads them. Signed out, paused for an account switch or without cloud: deletes locally only.
    @discardableResult
    func deleteAllDataEverywhere(context: ModelContext, auth: AuthService) async -> Bool {
        do {
            guard client != nil, let uid = auth.session?.user.id.lowercased(), pendingAccountSwitch == nil,
                  SyncOwnerStore.owner(defaults)?.userID == uid else {
                try deleteAllLocalData(context)
                try context.save()
                return true
            }
            let now = Date()
            for e in try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            for e in try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            for e in try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            for e in try context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            try context.save()
            while isRunning { try? await Task.sleep(for: .milliseconds(100)) }   // a running pass may predate the tombstones
            await run(.normal, context: context, auth: auth)
            guard case .synced = state else { return false }
            // Only tombstones: a row another device changed later than `now` won on the server and came back – it
            // stays, so this device and the server do not drift apart.
            for e in try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt != nil })) { context.delete(e) }
            for e in try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt != nil })) { context.delete(e) }
            for e in try context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt != nil })) { context.delete(e) }
            for e in try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt != nil })) { context.delete(e) }
            try context.save()
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    // MARK: Run loop

    private enum Mode: Equatable {
        case normal, mergeLocal, replaceLocal
    }

    private enum SyncAbort: Error {
        /// Signed out or signed in with another account while a pass was waiting for the network.
        case accountChanged
    }

    /// One pass at a time. Calls while a pass runs are coalesced into one follow-up pass (edits made meanwhile get
    /// pushed promptly); account-switch decisions wait for the running pass.
    private func run(_ mode: Mode, context: ModelContext, auth: AuthService) async {
        guard client != nil else { state = .disabled; return }
        if isRunning {
            guard mode != .normal else { rerunRequested = true; return }
            while isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        }
        isRunning = true
        defer { isRunning = false }
        var mode = mode
        while true {
            rerunRequested = false
            await pass(mode, context: context, auth: auth)
            guard rerunRequested, case .synced = state else { break }
            mode = .normal
        }
    }

    private func pass(_ mode: Mode, context: ModelContext, auth: AuthService) async {
        guard let client else { state = .disabled; return }
        guard let session = await auth.validSession() else {
            pendingAccountSwitch = nil
            state = auth.needsReauthentication ? .failed(SupabaseError.sessionExpired.localizedDescription) : .idle
            return
        }
        let uid = session.user.id.lowercased()
        let email = session.user.email

        // Owner guard.
        do {
            switch mode {
            case .normal:
                if let conflict = try ownerConflict(userID: uid, email: email, context: context) {
                    pendingAccountSwitch = conflict
                    state = .idle
                    return
                }
            case .mergeLocal:
                SyncOwnerStore.claim(userID: uid, email: email, defaults)
                SyncOwnerStore.setLastPush(nil, userID: uid, defaults)   // upload everything on this device
            case .replaceLocal:
                break   // claimed after the download succeeded
            }
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        pendingAccountSwitch = nil
        state = .syncing

        let provider: SupabaseClient.SessionProvider = { [auth] rejected in
            let next: SupabaseSession?
            if let rejected {
                next = await auth.refreshedSession(after: rejected)
            } else {
                next = await auth.validSession()
            }
            guard let next, next.user.id.lowercased() == uid else { throw SyncAbort.accountChanged }
            return next
        }

        let started = Date()
        do {
            // 1) Push (not when replacing local data – it is about to be discarded).
            var pushWatermark: Date?
            if mode != .replaceLocal {
                let pushStarted = Date()
                let lastPush = SyncOwnerStore.lastPush(userID: uid, defaults) ?? .distantPast
                // Device clock went backwards since the last push: push everything (the server skips duplicates).
                let since = lastPush > pushStarted ? Date.distantPast : lastPush
                let tickets = try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.updatedAt > since }))
                let trips = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.updatedAt > since }))
                let favorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.updatedAt > since }))
                let benefits = try context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.updatedAt > since }))
                let ticketRows = tickets.map { TicketDTO($0, userID: uid) }
                let tripRows = trips.map { TripDTO($0, userID: uid) }
                let favoriteRows = favorites.map { FavoriteDTO($0, userID: uid) }
                let benefitRows = benefits.map { BenefitDTO($0, userID: uid) }
                try await client.upsertAll(TicketDTO.table, rows: ticketRows, onConflict: Self.onConflict,
                                           chunkSize: Self.pushChunkSize, session: provider)
                try await client.upsertAll(TripDTO.table, rows: tripRows, onConflict: Self.onConflict,
                                           chunkSize: Self.pushChunkSize, session: provider)
                try await client.upsertAll(FavoriteDTO.table, rows: favoriteRows, onConflict: Self.onConflict,
                                           chunkSize: Self.pushChunkSize, session: provider)
                try await client.upsertAll(BenefitDTO.table, rows: benefitRows, onConflict: Self.onConflict,
                                           chunkSize: Self.pushChunkSize, session: provider)
                SyncOwnerStore.setLastPush(pushStarted, userID: uid, defaults)
                pushWatermark = pushStarted
            }

            // 2) Pull every page of every table before touching local data.
            func cursor(_ table: String) -> Int64 {
                mode == .replaceLocal ? 0 : SyncOwnerStore.cursor(table: table, userID: uid, defaults)
            }
            let tickets: (rows: [TicketDTO], maxRev: Int64) = try await client.pullAll(
                TicketDTO.table, userID: uid, since: cursor(TicketDTO.table), overlap: Self.pullOverlap,
                pageSize: Self.pageSize, session: provider)
            let trips: (rows: [TripDTO], maxRev: Int64) = try await client.pullAll(
                TripDTO.table, userID: uid, since: cursor(TripDTO.table), overlap: Self.pullOverlap,
                pageSize: Self.pageSize, session: provider)
            let favorites: (rows: [FavoriteDTO], maxRev: Int64) = try await client.pullAll(
                FavoriteDTO.table, userID: uid, since: cursor(FavoriteDTO.table), overlap: Self.pullOverlap,
                pageSize: Self.pageSize, session: provider)
            let benefits: (rows: [BenefitDTO], maxRev: Int64) = try await client.pullAll(
                BenefitDTO.table, userID: uid, since: cursor(BenefitDTO.table), overlap: Self.pullOverlap,
                pageSize: Self.pageSize, session: provider)

            // The account may have changed while waiting for the network.
            guard auth.session?.user.id.lowercased() == uid else { throw SyncAbort.accountChanged }

            // 3) Merge and save; cursors only move after a successful save.
            var localTickets: [TicketEntity] = []
            var localTrips: [TripEntity] = []
            var localFavorites: [FavoriteRouteEntity] = []
            var localBenefits: [BenefitEntity] = []
            if mode == .replaceLocal {
                try deleteAllLocalData(context)
            } else {
                localTickets = try context.fetch(FetchDescriptor<TicketEntity>())
                localTrips = try context.fetch(FetchDescriptor<TripEntity>())
                localFavorites = try context.fetch(FetchDescriptor<FavoriteRouteEntity>())
                localBenefits = try context.fetch(FetchDescriptor<BenefitEntity>())
            }
            merge(tickets.rows, into: localTickets, userID: uid, dirtyAfter: pushWatermark, context: context,
                  id: { $0.id }, updatedAt: { $0.updatedAt }, snapshot: { TicketDTO($0, userID: uid) },
                  apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
            merge(trips.rows, into: localTrips, userID: uid, dirtyAfter: pushWatermark, context: context,
                  id: { $0.id }, updatedAt: { $0.updatedAt }, snapshot: { TripDTO($0, userID: uid) },
                  apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
            merge(favorites.rows, into: localFavorites, userID: uid, dirtyAfter: pushWatermark, context: context,
                  id: { $0.id }, updatedAt: { $0.updatedAt }, snapshot: { FavoriteDTO($0, userID: uid) },
                  apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
            merge(benefits.rows, into: localBenefits, userID: uid, dirtyAfter: pushWatermark, context: context,
                  id: { $0.id }, updatedAt: { $0.updatedAt }, snapshot: { BenefitDTO($0, userID: uid) },
                  apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
            try context.save()

            SyncOwnerStore.setCursor(tickets.maxRev, table: TicketDTO.table, userID: uid, defaults)
            SyncOwnerStore.setCursor(trips.maxRev, table: TripDTO.table, userID: uid, defaults)
            SyncOwnerStore.setCursor(favorites.maxRev, table: FavoriteDTO.table, userID: uid, defaults)
            SyncOwnerStore.setCursor(benefits.maxRev, table: BenefitDTO.table, userID: uid, defaults)
            if mode == .replaceLocal {
                SyncOwnerStore.claim(userID: uid, email: email, defaults)
                SyncOwnerStore.setLastPush(started, userID: uid, defaults)
            }
            defaults.set(Date(), forKey: "sync.lastSync")
            state = .synced(Date())
        } catch SyncAbort.accountChanged {
            state = .idle
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: Owner guard

    /// nil when this account may sync the local data (claiming it if nobody owns it yet).
    private func ownerConflict(userID uid: String, email: String?, context: ModelContext) throws -> AccountSwitch? {
        guard let owner = SyncOwnerStore.owner(defaults) else {
            // First account on this device (or first sync after updating the app): the local data belongs to it.
            SyncOwnerStore.claim(userID: uid, email: email, defaults)
            return nil
        }
        if owner.userID == uid {
            if owner.email != email, email != nil { SyncOwnerStore.claim(userID: uid, email: email, defaults) }
            return nil
        }
        let previousPush = SyncOwnerStore.lastPush(userID: owner.userID, defaults) ?? .distantPast
        let live = try liveItemCount(context)
        let unsynced = try changedItemCount(since: previousPush, context)
        if live == 0 && unsynced == 0 {
            // Nothing of the previous account is left on this device – adopt the new one silently.
            try deleteAllLocalData(context)
            try context.save()
            SyncOwnerStore.claim(userID: uid, email: email, defaults)
            return nil
        }
        return AccountSwitch(previousUserID: owner.userID, previousEmail: owner.email, newUserID: uid, newEmail: email,
                             localItemCount: live, unsyncedItemCount: unsynced)
    }

    private func liveItemCount(_ context: ModelContext) throws -> Int {
        let tickets = try context.fetchCount(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        let trips = try context.fetchCount(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        let favorites = try context.fetchCount(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        let benefits = try context.fetchCount(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        return tickets + trips + favorites + benefits
    }

    private func changedItemCount(since: Date, _ context: ModelContext) throws -> Int {
        let tickets = try context.fetchCount(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.updatedAt > since }))
        let trips = try context.fetchCount(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.updatedAt > since }))
        let favorites = try context.fetchCount(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.updatedAt > since }))
        let benefits = try context.fetchCount(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.updatedAt > since }))
        return tickets + trips + favorites + benefits
    }

    private func deleteAllLocalData(_ context: ModelContext) throws {
        for e in try context.fetch(FetchDescriptor<TripEntity>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<FavoriteRouteEntity>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<BenefitEntity>()) { context.delete(e) }
        for e in try context.fetch(FetchDescriptor<TicketEntity>()) { context.delete(e) }
    }

    // MARK: Merge

    /// Applies pulled rows (one in-memory index instead of one fetch per row).
    private func merge<Row: SyncRow, Entity: PersistentModel>(
        _ rows: [Row], into existing: [Entity], userID: String, dirtyAfter: Date?, context: ModelContext,
        id: (Entity) -> UUID, updatedAt: (Entity) -> Date, snapshot: (Entity) -> Row,
        apply: (Row, Entity) -> Void, make: (Row) -> Entity
    ) {
        guard !rows.isEmpty else { return }
        // An edit made during this pass is stamped between the push start and now. A stamp *after* now comes from a
        // clock that ran ahead when the row was edited (and was corrected since): that row was part of this push
        // (stamp > last push), the server clamped or skipped it, so its answer must win – otherwise the row would stay
        // "dirty", be re-pushed on every sync and overwrite newer edits from other devices.
        let now = Date()
        var byID: [UUID: Entity] = [:]
        for entity in existing where byID[id(entity)] == nil { byID[id(entity)] = entity }
        for var remote in rows {
            remote.server_rev = nil
            remote.user_id = userID
            let local = byID[remote.id]
            var localUpdatedAt: Date?
            var isDirty = false
            var isSame = false
            if let local {
                let stamp = updatedAt(local)
                localUpdatedAt = stamp
                if let dirtyAfter { isDirty = stamp > dirtyAfter && stamp <= now }
                isSame = snapshot(local) == remote
            }
            let action = SyncMergeRule.action(localUpdatedAt: localUpdatedAt, localIsDirty: isDirty,
                                              remoteUpdatedAt: remote.updated_at, remoteIsDeleted: remote.deleted_at != nil,
                                              sameContent: isSame)
            switch action {
            case .insert:
                let entity = make(remote)
                context.insert(entity)
                byID[remote.id] = entity
            case .apply:
                if let local { apply(remote, local) }
            case .keep:
                break
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? SupabaseError {
            // Foreign key to auth.users violated: the account was deleted on another device (this access token
            // stays valid for up to an hour).
            if error.code == "23503" { return "Dieses Konto wurde gelöscht. Melde dich ab oder mit einem anderen Konto an." }
            return error.localizedDescription
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "Keine Internetverbindung."
            case .timedOut, .cannotConnectToHost, .cannotFindHost: return "Der Server ist gerade nicht erreichbar."
            default: return error.localizedDescription
            }
        }
        if error is DecodingError { return "Unerwartete Daten vom Server." }
        return error.localizedDescription
    }
}

// MARK: - Sync owner & cursors (UserDefaults)

/// Which account the local data belongs to, plus per-account push time and per-table pull cursors.
enum SyncOwnerStore {
    struct Owner: Equatable {
        var userID: String
        var email: String?
    }

    static let tables = ["tickets", "trips", "favorite_routes", "benefits"]
    private static let ownerIDKey = "sync.owner.userID"
    private static let ownerEmailKey = "sync.owner.email"

    private static func lastPushKey(_ userID: String) -> String { "sync.user.\(userID.lowercased()).lastPush" }
    private static func cursorKey(_ table: String, _ userID: String) -> String { "sync.user.\(userID.lowercased()).rev.\(table)" }

    static func owner(_ defaults: UserDefaults = .standard) -> Owner? {
        guard let id = defaults.string(forKey: ownerIDKey), !id.isEmpty else { return nil }
        return Owner(userID: id, email: defaults.string(forKey: ownerEmailKey))
    }

    static func claim(userID: String, email: String?, _ defaults: UserDefaults = .standard) {
        defaults.set(userID.lowercased(), forKey: ownerIDKey)
        defaults.set(email, forKey: ownerEmailKey)
    }

    static func lastPush(userID: String, _ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastPushKey(userID)) as? Date
    }

    static func setLastPush(_ date: Date?, userID: String, _ defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastPushKey(userID))
    }

    static func cursor(table: String, userID: String, _ defaults: UserDefaults = .standard) -> Int64 {
        (defaults.object(forKey: cursorKey(table, userID)) as? NSNumber)?.int64Value ?? 0
    }

    static func setCursor(_ rev: Int64, table: String, userID: String, _ defaults: UserDefaults = .standard) {
        defaults.set(NSNumber(value: rev), forKey: cursorKey(table, userID))
    }

    static func resetPullCursors(userID: String, _ defaults: UserDefaults = .standard) {
        for table in tables { defaults.removeObject(forKey: cursorKey(table, userID)) }
    }

    /// Forgets an account entirely (after account deletion): ownership, push time and cursors.
    static func forget(userID: String, _ defaults: UserDefaults = .standard) {
        if owner(defaults)?.userID == userID.lowercased() {
            defaults.removeObject(forKey: ownerIDKey)
            defaults.removeObject(forKey: ownerEmailKey)
        }
        defaults.removeObject(forKey: lastPushKey(userID))
        resetPullCursors(userID: userID, defaults)
    }
}

// MARK: - Merge rule

enum SyncMergeRule {
    enum Action: Equatable {
        case insert, apply, keep
    }

    /// - localUpdatedAt: nil when the row does not exist on this device.
    /// - localIsDirty: the local row changed after this sync's push started (and not "in the future"), i.e. the server
    ///   has not seen it yet.
    /// - sameContent: local and remote rows are identical (incl. updated_at / deleted_at).
    static func action(localUpdatedAt: Date?, localIsDirty: Bool, remoteUpdatedAt: Date, remoteIsDeleted: Bool,
                       sameContent: Bool) -> Action {
        guard let localUpdatedAt else { return remoteIsDeleted ? .keep : .insert }   // unknown tombstone: nothing to do
        if sameContent { return .keep }
        // Unpushed local edit: last writer wins, exactly like the server will decide when it gets pushed.
        if localIsDirty { return remoteUpdatedAt > localUpdatedAt ? .apply : .keep }
        // Already pushed: the server's row is authoritative (it rejected stale writes and clamped skewed clocks).
        return .apply
    }
}

// MARK: - DTOs (snake_case = Postgres columns, see supabase/migrations)

protocol SyncRow: Codable, Equatable, Sendable, ServerRevisioned {
    static var table: String { get }
    var id: UUID { get }
    var user_id: String { get set }
    var updated_at: Date { get }
    var deleted_at: Date? { get }
    var server_rev: Int64? { get set }
}

struct TicketDTO: SyncRow {
    static let table = "tickets"

    var id: UUID
    var user_id: String
    var product_id: String
    var name: String
    var variant: String
    var family: String
    var states: String
    var price: Double
    var start_date: Date
    var end_date: Date
    var holder_name: String
    var ticket_number: String
    var theme: String
    var reminders: String
    var is_monthly_payment: Bool?
    var auto_renews: Bool?
    var employer_contribution: Double?
    var add_on_price: Double?
    var add_ons: String?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
    /// Assigned by the server; never sent.
    var server_rev: Int64? = nil

    init(_ e: TicketEntity, userID: String) {
        id = e.id; user_id = userID; product_id = e.productID; name = e.name; variant = e.variantRaw; family = e.familyRaw
        states = e.statesRaw; price = e.price; start_date = e.startDate; end_date = e.endDate; holder_name = e.holderName
        ticket_number = e.ticketNumber; theme = e.themeRaw; reminders = e.remindersRaw; is_monthly_payment = e.isMonthlyPayment
        auto_renews = e.autoRenews; employer_contribution = e.employerContribution; add_on_price = e.addOnPrice; add_ons = e.addOnsRaw
        created_at = e.createdAt
        updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: TicketEntity) {
        e.productID = product_id; e.name = name; e.variantRaw = variant; e.familyRaw = family; e.statesRaw = states
        e.price = price; e.startDate = start_date; e.endDate = end_date; e.holderName = holder_name; e.ticketNumber = ticket_number
        e.themeRaw = theme; e.remindersRaw = reminders; e.isMonthlyPayment = is_monthly_payment ?? false
        e.autoRenews = auto_renews ?? false; e.employerContribution = employer_contribution ?? 0
        e.addOnPrice = add_on_price ?? 0; e.addOnsRaw = add_ons ?? ""
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }

    func makeEntity() -> TicketEntity {
        let e = TicketEntity(productID: product_id, name: name, variant: .klassik, family: .oe, price: price, startDate: start_date)
        e.id = id
        apply(to: e)
        return e
    }
}

struct TripDTO: SyncRow {
    static let table = "trips"

    var id: UUID
    var user_id: String
    var date: Date
    var from_name: String
    var to_name: String
    var from_station_id: String?
    var to_station_id: String?
    var mode: String
    var distance_km: Double
    var fare_eur: Double
    var is_fare_manual: Bool
    var is_round_trip: Bool
    var travel_class: String
    var companions: Int
    var states: String
    var note: String
    var category: String?
    var is_induced: Bool?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
    /// Assigned by the server; never sent.
    var server_rev: Int64? = nil

    init(_ e: TripEntity, userID: String) {
        id = e.id; user_id = userID; date = e.date; from_name = e.fromName; to_name = e.toName
        from_station_id = e.fromStationID; to_station_id = e.toStationID; mode = e.modeRaw; distance_km = e.distanceKm
        fare_eur = e.fareEUR; is_fare_manual = e.isFareManual; is_round_trip = e.isRoundTrip; travel_class = e.travelClassRaw
        companions = e.companions; states = e.statesRaw; note = e.note; category = e.categoryRaw; is_induced = e.isInduced
        created_at = e.createdAt; updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: TripEntity) {
        e.date = date; e.fromName = from_name; e.toName = to_name; e.fromStationID = from_station_id; e.toStationID = to_station_id
        e.modeRaw = mode; e.distanceKm = distance_km; e.fareEUR = fare_eur; e.isFareManual = is_fare_manual
        e.isRoundTrip = is_round_trip; e.travelClassRaw = travel_class; e.companions = companions; e.statesRaw = states
        e.note = note; e.categoryRaw = category ?? ""; e.isInduced = is_induced ?? false
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }

    func makeEntity() -> TripEntity {
        let e = TripEntity(date: date, fromName: from_name, toName: to_name, mode: .train, distanceKm: distance_km, fareEUR: fare_eur)
        e.id = id
        apply(to: e)
        return e
    }
}

struct FavoriteDTO: SyncRow {
    static let table = "favorite_routes"

    var id: UUID
    var user_id: String
    var title: String
    var from_name: String
    var to_name: String
    var from_station_id: String?
    var to_station_id: String?
    var mode: String
    var distance_km: Double
    var fare_eur: Double
    var is_round_trip: Bool
    var states: String
    var sort_index: Int
    var usage_count: Int
    var category: String?
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
    /// Assigned by the server; never sent.
    var server_rev: Int64? = nil

    init(_ e: FavoriteRouteEntity, userID: String) {
        id = e.id; user_id = userID; title = e.title; from_name = e.fromName; to_name = e.toName
        from_station_id = e.fromStationID; to_station_id = e.toStationID; mode = e.modeRaw; distance_km = e.distanceKm
        fare_eur = e.fareEUR; is_round_trip = e.isRoundTrip; states = e.statesRaw; sort_index = e.sortIndex
        usage_count = e.usageCount; category = e.categoryRaw; created_at = e.createdAt; updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: FavoriteRouteEntity) {
        e.title = title; e.fromName = from_name; e.toName = to_name; e.fromStationID = from_station_id; e.toStationID = to_station_id
        e.modeRaw = mode; e.distanceKm = distance_km; e.fareEUR = fare_eur; e.isRoundTrip = is_round_trip; e.statesRaw = states
        e.sortIndex = sort_index; e.usageCount = usage_count; e.categoryRaw = category ?? ""
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }

    func makeEntity() -> FavoriteRouteEntity {
        let e = FavoriteRouteEntity(fromName: from_name, toName: to_name, mode: .train, distanceKm: distance_km, fareEUR: fare_eur)
        e.id = id
        apply(to: e)
        return e
    }
}

struct BenefitDTO: SyncRow {
    static let table = "benefits"

    var id: UUID
    var user_id: String
    var date: Date
    var partner_id: String
    var title: String
    var saved_eur: Double
    var note: String
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?
    /// Assigned by the server; never sent.
    var server_rev: Int64? = nil

    init(_ e: BenefitEntity, userID: String) {
        id = e.id; user_id = userID; date = e.date; partner_id = e.partnerID; title = e.title; saved_eur = e.savedEUR
        note = e.note; created_at = e.createdAt; updated_at = e.updatedAt; deleted_at = e.deletedAt
    }

    func apply(to e: BenefitEntity) {
        e.date = date; e.partnerID = partner_id; e.title = title; e.savedEUR = saved_eur; e.note = note
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }

    func makeEntity() -> BenefitEntity {
        let e = BenefitEntity(date: date, partnerID: partner_id, title: title, savedEUR: saved_eur, note: note)
        e.id = id
        apply(to: e)
        return e
    }
}
