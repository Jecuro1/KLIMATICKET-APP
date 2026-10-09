import Foundation
import SwiftData
import KlimaCore
import KlimaCloud

/// Two-way cloud sync with the KlimaBilanz Cloudflare Worker + D1 (contract: docs/CLOUDFLARE_BACKEND.md §3.5–3.8).
///
/// • Push: rows whose `updatedAt` is newer than the last successful push of this account (device clock compared with
///   the same device clock only), in chunks of ≤ 500 rows and ≤ 1 MB (`POST /v1/sync/push`).
/// • Pull: pages on the server-assigned `server_rev` (`GET /v1/sync/pull`, following `next`), cursor per table and
///   account – never the device clock. D1 runs write batches one at a time, so the cursor needs no overlap window.
/// • Conflicts: the server decides (last writer wins on `updated_at`, stale writes skipped, far-future clocks clamped).
///   Locally only edits that were not pushed yet are protected; everything else follows the server.
/// • Deletes are soft (`deleted_at`).
/// • Owner guard: local data is linked to the account it was synced with. When another account signs in, sync pauses
///   (`pendingAccountSwitch`) until the user decides between `discardLocalDataAndSync` and `mergeLocalDataIntoAccount`.
///   Data synced with the retired Supabase backend is adopted by the first Cloudflare account without asking.
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
    /// The server rejected this app version (`426`); an app update is needed before sync works again.
    private(set) var requiresAppUpdate = false
    /// True while every local row is replaced wholesale ("Durch Daten des Kontos ersetzen", "Alles löschen" on this
    /// iPhone). RootView shows a placeholder meanwhile, so no screen still holds a model that is about to be deleted.
    private(set) var isReplacingLocalData = false

    private let client: CloudAPIClient?
    private let defaults = UserDefaults.standard
    private var isRunning = false
    private var rerunRequested = false

    static let pageSize = CloudAPIClient.pullMaxLimit
    static let maxPages = 4000

    init(config: AppConfig) {
        if let client = config.cloudClient {
            self.client = client
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
    /// download (cursor reset after sign-out, a new device). So every row first becomes a tombstone (`deleted_at`),
    /// the tombstones are uploaded, and only then are the tombstones removed from this device. Returns false when the
    /// upload failed – the rows then stay on the device as (hidden) tombstones and the next sync uploads them.
    /// Signed out, paused for an account switch or without cloud: deletes locally only.
    @discardableResult
    func deleteAllDataEverywhere(context: ModelContext, auth: AuthService) async -> Bool {
        do {
            guard client != nil, let uid = auth.session?.user.id.lowercased(), pendingAccountSwitch == nil,
                  SyncOwnerStore.owner(defaults)?.userID == uid else {
                try await performLocalDataReplacement {
                    try deleteAllLocalData(context)
                    try context.save()
                }
                Analytics.invalidateCache()
                return true
            }
            let now = Date()
            for e in try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            for e in try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            for e in try context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            for e in try context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil })) { e.deletedAt = now; e.updatedAt = now }
            try context.save()
            Analytics.invalidateCache()
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
            Analytics.invalidateCache()
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    /// Runs `replace` (synchronous: delete, insert, save) only after the UI dropped every screen that could still hold
    /// one of the rows about to be deleted – a pushed TripDetailView keeps its `TripEntity`, and SwiftData traps when a
    /// view reads a deleted model.
    func performLocalDataReplacement(_ replace: () throws -> Void) async rethrows {
        isReplacingLocalData = true
        defer { isReplacingLocalData = false }
        try? await Task.sleep(for: .milliseconds(350))   // RootView swaps MainTabView for a placeholder meanwhile
        try replace()
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
            state = auth.needsReauthentication ? .failed(CloudError.sessionExpired.message(providerName: nil)) : .idle
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

        let provider: SessionProvider = { [auth] rejected in
            let next: CloudSession?
            if let rejected {
                next = await auth.refreshedSession(after: rejected)
            } else {
                next = await auth.validSession()
            }
            guard let next, next.user.id.lowercased() == uid else { throw SyncAbort.accountChanged }
            return next
        }

        // MARK: via – `via` goes up only to a Worker that knows the column (else 422 unknown_field) and is taken from pulled
        // rows only then: a stale server value must not wipe vias this device could not upload (docs/VIA.md §3).
        await auth.refreshServerConfig()
        let syncsVia = auth.serverConfig?.supports(CloudFeature.tripVia) ?? false
        // MARK: trips – journeys (`journey_id`, `leg_index`, favourite `legs`) the same way (docs/JOURNEYS.md §3).
        let syncsJourney = auth.serverConfig?.supports(CloudFeature.tripJourney) ?? false

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
                let tripRows = trips.map { TripDTO($0, userID: uid, includesVia: syncsVia, includesJourney: syncsJourney) }
                let favoriteRows = favorites.map { FavoriteDTO($0, userID: uid, includesVia: syncsVia, includesJourney: syncsJourney) }
                let benefitRows = benefits.map { BenefitDTO($0, userID: uid) }
                _ = try await client.push(table: TicketDTO.table, rows: ticketRows, session: provider)
                _ = try await client.push(table: TripDTO.table, rows: tripRows, session: provider)
                _ = try await client.push(table: FavoriteDTO.table, rows: favoriteRows, session: provider)
                _ = try await client.push(table: BenefitDTO.table, rows: benefitRows, session: provider)
                SyncOwnerStore.setLastPush(pushStarted, userID: uid, defaults)
                pushWatermark = pushStarted
            }

            // 2) Pull every page of every table before touching local data.
            func cursor(_ table: String) -> Int64 {
                mode == .replaceLocal ? 0 : SyncOwnerStore.cursor(table: table, userID: uid, defaults)
            }
            let tickets: (rows: [TicketDTO], maxRev: Int64) = try await client.pullAll(
                table: TicketDTO.table, after: cursor(TicketDTO.table), pageSize: Self.pageSize, maxPages: Self.maxPages,
                session: provider)
            let trips: (rows: [TripDTO], maxRev: Int64) = try await client.pullAll(
                table: TripDTO.table, after: cursor(TripDTO.table), pageSize: Self.pageSize, maxPages: Self.maxPages,
                session: provider)
            let favorites: (rows: [FavoriteDTO], maxRev: Int64) = try await client.pullAll(
                table: FavoriteDTO.table, after: cursor(FavoriteDTO.table), pageSize: Self.pageSize, maxPages: Self.maxPages,
                session: provider)
            let benefits: (rows: [BenefitDTO], maxRev: Int64) = try await client.pullAll(
                table: BenefitDTO.table, after: cursor(BenefitDTO.table), pageSize: Self.pageSize, maxPages: Self.maxPages,
                session: provider)

            // The account may have changed while waiting for the network.
            guard auth.session?.user.id.lowercased() == uid else { throw SyncAbort.accountChanged }

            // 3) Merge and save; cursors only move after a successful save. Local rows are only fetched for tables
            //    that pulled something (most passes pull nothing – no main-thread fetch of every row then).
            let mergeAll = { (replacing: Bool) throws in
                func local<Entity: PersistentModel>(_ type: Entity.Type, pulled: Int) throws -> [Entity] {
                    replacing || pulled == 0 ? [] : try context.fetch(FetchDescriptor<Entity>())
                }
                self.merge(tickets.rows, into: try local(TicketEntity.self, pulled: tickets.rows.count), userID: uid,
                           dirtyAfter: pushWatermark, context: context,
                           id: { $0.id }, updatedAt: { $0.updatedAt }, snapshot: { TicketDTO($0, userID: uid) },
                           apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
                self.merge(trips.rows, into: try local(TripEntity.self, pulled: trips.rows.count), userID: uid,
                           dirtyAfter: pushWatermark, context: context,
                           id: { $0.id }, updatedAt: { $0.updatedAt },
                           snapshot: { TripDTO($0, userID: uid, includesVia: syncsVia, includesJourney: syncsJourney) },
                           apply: { $0.keepingVia(!syncsVia).keepingJourney(!syncsJourney).apply(to: $1) }, make: { $0.makeEntity() })
                self.merge(favorites.rows, into: try local(FavoriteRouteEntity.self, pulled: favorites.rows.count), userID: uid,
                           dirtyAfter: pushWatermark, context: context,
                           id: { $0.id }, updatedAt: { $0.updatedAt },
                           snapshot: { FavoriteDTO($0, userID: uid, includesVia: syncsVia, includesJourney: syncsJourney) },
                           apply: { $0.keepingVia(!syncsVia).keepingJourney(!syncsJourney).apply(to: $1) }, make: { $0.makeEntity() })
                self.merge(benefits.rows, into: try local(BenefitEntity.self, pulled: benefits.rows.count), userID: uid,
                           dirtyAfter: pushWatermark, context: context,
                           id: { $0.id }, updatedAt: { $0.updatedAt }, snapshot: { BenefitDTO($0, userID: uid) },
                           apply: { $0.apply(to: $1) }, make: { $0.makeEntity() })
                if context.hasChanges { try context.save() }
            }
            if mode == .replaceLocal {
                try await performLocalDataReplacement {
                    // The account may also change while the screens are reset.
                    guard auth.session?.user.id.lowercased() == uid else { throw SyncAbort.accountChanged }
                    try deleteAllLocalData(context)
                    try mergeAll(true)
                }
            } else {
                try mergeAll(false)
            }
            Analytics.invalidateCache()

            SyncOwnerStore.setCursor(tickets.maxRev, table: TicketDTO.table, userID: uid, defaults)
            SyncOwnerStore.setCursor(trips.maxRev, table: TripDTO.table, userID: uid, defaults)
            SyncOwnerStore.setCursor(favorites.maxRev, table: FavoriteDTO.table, userID: uid, defaults)
            SyncOwnerStore.setCursor(benefits.maxRev, table: BenefitDTO.table, userID: uid, defaults)
            if mode == .replaceLocal {
                SyncOwnerStore.claim(userID: uid, email: email, defaults)
                SyncOwnerStore.setLastPush(started, userID: uid, defaults)
            }
            defaults.set(Date(), forKey: "sync.lastSync")
            requiresAppUpdate = false
            state = .synced(Date())
        } catch SyncAbort.accountChanged {
            state = .idle
        } catch {
            if let cloud = error as? CloudError, case .upgradeRequired = cloud { requiresAppUpdate = true }
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
        if owner.isLegacy && owner.userID != uid {
            // The data was synced with the retired Supabase backend, whose account ids no longer exist: the first
            // Cloudflare account adopts it silently and uploads everything (like "Daten dieses iPhones übernehmen").
            SyncOwnerStore.claim(userID: uid, email: email, defaults)
            SyncOwnerStore.setLastPush(nil, userID: uid, defaults)
            return nil
        }
        if owner.userID == uid {
            if owner.isLegacy || (owner.email != email && email != nil) { SyncOwnerStore.claim(userID: uid, email: email, defaults) }
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
        CloudError.userMessage(for: error)
    }
}

// MARK: - DTO ↔ SwiftData entities (the DTOs live in KlimaCloud)

extension TicketDTO {
    init(_ e: TicketEntity, userID: String) {
        self.init(id: e.id, user_id: userID, product_id: e.productID, name: e.name, variant: e.variantRaw, family: e.familyRaw,
                  states: e.statesRaw, price: e.price, start_date: e.startDate, end_date: e.endDate, holder_name: e.holderName,
                  ticket_number: e.ticketNumber, theme: e.themeRaw, reminders: e.remindersRaw,
                  is_monthly_payment: e.isMonthlyPayment, auto_renews: e.autoRenews,
                  employer_contribution: e.employerContribution, add_on_price: e.addOnPrice, add_ons: e.addOnsRaw,
                  created_at: e.createdAt, updated_at: e.updatedAt, deleted_at: e.deletedAt)
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

extension TripDTO {
    /// `includesVia`: false for a server without `CloudFeature.tripVia` (the key is then left out; backups always carry it).
    /// `includesJourney`: the same for `CloudFeature.tripJourney` (`journey_id`, `leg_index`).  // MARK: trips
    init(_ e: TripEntity, userID: String, includesVia: Bool = true, includesJourney: Bool = true) {
        self.init(id: e.id, user_id: userID, date: e.date, from_name: e.fromName, to_name: e.toName,
                  from_station_id: e.fromStationID, to_station_id: e.toStationID, mode: e.modeRaw, distance_km: e.distanceKm,
                  fare_eur: e.fareEUR, is_fare_manual: e.isFareManual, is_round_trip: e.isRoundTrip,
                  travel_class: e.travelClassRaw, companions: e.companions, states: e.statesRaw, note: e.note,
                  category: e.categoryRaw, is_induced: e.isInduced, via: includesVia ? e.viaRaw : nil,
                  journey_id: includesJourney ? (e.journeyID?.uuidString.lowercased() ?? "") : nil,   // MARK: trips
                  leg_index: includesJourney ? e.legIndex : nil,
                  created_at: e.createdAt, updated_at: e.updatedAt, deleted_at: e.deletedAt)
    }

    /// nil `via` (older server or backup) keeps the entity's vias; nil `journey_id` / `leg_index` keep its journey.
    func apply(to e: TripEntity) {
        e.date = date; e.fromName = from_name; e.toName = to_name; e.fromStationID = from_station_id; e.toStationID = to_station_id
        e.modeRaw = mode; e.distanceKm = distance_km; e.fareEUR = fare_eur; e.isFareManual = is_fare_manual
        e.isRoundTrip = is_round_trip; e.travelClassRaw = travel_class; e.companions = companions; e.statesRaw = states
        e.note = note; e.categoryRaw = category ?? ""; e.isInduced = is_induced ?? false
        if let via { e.viaRaw = via }   // MARK: via
        if let journey_id { e.journeyID = UUID(uuidString: journey_id) }   // MARK: trips – '' = none
        if let leg_index { e.legIndex = max(0, leg_index) }
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }

    /// The row without its journey keys when `keep` (the entity's journey then stays as it is).  // MARK: trips
    func keepingJourney(_ keep: Bool) -> TripDTO {
        guard keep else { return self }
        var copy = self
        copy.journey_id = nil
        copy.leg_index = nil
        return copy
    }

    /// The row without its `via` when `keep` (the entity's vias then stay as they are).
    func keepingVia(_ keep: Bool) -> TripDTO {
        guard keep else { return self }
        var copy = self
        copy.via = nil
        return copy
    }

    func makeEntity() -> TripEntity {
        let e = TripEntity(date: date, fromName: from_name, toName: to_name, mode: .train, distanceKm: distance_km, fareEUR: fare_eur)
        e.id = id
        apply(to: e)
        return e
    }
}

extension FavoriteDTO {
    /// `includesVia` / `includesJourney`: as on `TripDTO.init(_:userID:includesVia:includesJourney:)`.
    init(_ e: FavoriteRouteEntity, userID: String, includesVia: Bool = true, includesJourney: Bool = true) {
        self.init(id: e.id, user_id: userID, title: e.title, from_name: e.fromName, to_name: e.toName,
                  from_station_id: e.fromStationID, to_station_id: e.toStationID, mode: e.modeRaw, distance_km: e.distanceKm,
                  fare_eur: e.fareEUR, is_round_trip: e.isRoundTrip, states: e.statesRaw, sort_index: e.sortIndex,
                  usage_count: e.usageCount, category: e.categoryRaw, via: includesVia ? e.viaRaw : nil,
                  legs: includesJourney ? e.legsRaw : nil,   // MARK: trips
                  created_at: e.createdAt, updated_at: e.updatedAt, deleted_at: e.deletedAt)
    }

    /// nil `via` keeps the entity's vias, nil `legs` its legs.
    func apply(to e: FavoriteRouteEntity) {
        e.title = title; e.fromName = from_name; e.toName = to_name; e.fromStationID = from_station_id; e.toStationID = to_station_id
        e.modeRaw = mode; e.distanceKm = distance_km; e.fareEUR = fare_eur; e.isRoundTrip = is_round_trip; e.statesRaw = states
        e.sortIndex = sort_index; e.usageCount = usage_count; e.categoryRaw = category ?? ""
        if let via { e.viaRaw = via }   // MARK: via
        if let legs { e.legsRaw = legs }   // MARK: trips
        e.createdAt = created_at; e.updatedAt = updated_at; e.deletedAt = deleted_at
    }

    // MARK: trips
    func keepingJourney(_ keep: Bool) -> FavoriteDTO {
        guard keep else { return self }
        var copy = self
        copy.legs = nil
        return copy
    }

    func keepingVia(_ keep: Bool) -> FavoriteDTO {
        guard keep else { return self }
        var copy = self
        copy.via = nil
        return copy
    }

    func makeEntity() -> FavoriteRouteEntity {
        let e = FavoriteRouteEntity(fromName: from_name, toName: to_name, mode: .train, distanceKm: distance_km, fareEUR: fare_eur)
        e.id = id
        apply(to: e)
        return e
    }
}

extension BenefitDTO {
    init(_ e: BenefitEntity, userID: String) {
        self.init(id: e.id, user_id: userID, date: e.date, partner_id: e.partnerID, title: e.title, saved_eur: e.savedEUR,
                  note: e.note, created_at: e.createdAt, updated_at: e.updatedAt, deleted_at: e.deletedAt)
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
