import Foundation
import SwiftData
import WidgetKit
import OSLog
import KlimaCore

/// All writes go through here so that saving, widget refresh, reminders and cloud sync stay consistent.
@MainActor
struct Repository {
    let context: ModelContext
    let app: AppState

    static let log = Logger(subsystem: "com.knitelarlberg.klimabilanz", category: "store")

    // MARK: Trips

    @discardableResult
    func addTrip(_ trip: TripEntity) -> TripEntity {
        context.insert(trip)
        commit()
        return trip
    }

    func updateTrip(_ trip: TripEntity) {
        trip.touch()
        commit()
    }

    /// Soft delete (kept as tombstone for sync); `restoreTrip` undoes it.
    func deleteTrip(_ trip: TripEntity) {
        trip.deletedAt = Date()
        trip.touch()
        commit()
    }

    func restoreTrip(_ trip: TripEntity) {
        trip.deletedAt = nil
        trip.touch()
        commit()
    }

    /// Logs a favourite route right now ("Schnellerfassung").
    @discardableResult
    func logFavorite(_ favorite: FavoriteRouteEntity, on date: Date = Date()) -> TripEntity {
        let trip = favorite.makeTrip(on: date)
        favorite.usageCount += 1
        favorite.touch()
        context.insert(trip)
        commit()
        return trip
    }

    /// Duplicates a past trip for today ("Nochmal fahren"). `note` lets "Duplizieren" keep it in the same commit.  // MARK: trips
    @discardableResult
    func repeatTrip(_ trip: TripEntity, on date: Date = Date(), note: String = "") -> TripEntity {
        let copy = TripEntity(date: date, fromName: trip.fromName, toName: trip.toName, fromStationID: trip.fromStationID,
                              toStationID: trip.toStationID, mode: trip.mode, distanceKm: trip.distanceKm, fareEUR: trip.fareEUR,
                              isFareManual: trip.isFareManual, isRoundTrip: trip.isRoundTrip, travelClass: trip.travelClass,
                              companions: trip.companions, states: trip.states, note: note)
        copy.categoryRaw = trip.categoryRaw
        copy.isInduced = trip.isInduced
        context.insert(copy)
        commit()
        return copy
    }

    /// Ingests quick logs queued by widgets / Siri / Control Center. Returns the number of trips added.
    /// The queue entries are removed only after the trips were saved; when saving fails, this attempt is undone and
    /// the entries stay queued for the next ingest (foreground, launch).
    @discardableResult
    func ingestQuickLogs() -> Int {
        let items = QuickLogQueue.pending()
        guard !items.isEmpty else { return 0 }
        // Deleted favourites count as well: the tap happened and the widget/Siri already said "erfasst". Only a
        // favourite that is gone completely (e.g. after "Alle Daten löschen") cannot be logged.
        var favorites: [UUID: FavoriteRouteEntity] = [:]
        for fav in (try? context.fetch(FetchDescriptor<FavoriteRouteEntity>())) ?? []
        where favorites[fav.id] == nil || fav.deletedAt == nil {
            favorites[fav.id] = fav
        }
        var inserted: [TripEntity] = []
        var touched: [(favorite: FavoriteRouteEntity, usageCount: Int, updatedAt: Date)] = []
        var skipped = 0
        for item in items {
            guard let fav = favorites[item.favoriteID] else {
                skipped += 1
                continue
            }
            let trip = fav.makeTrip(on: item.date)
            context.insert(trip)
            inserted.append(trip)
            if fav.deletedAt == nil {
                if !touched.contains(where: { $0.favorite === fav }) { touched.append((fav, fav.usageCount, fav.updatedAt)) }
                fav.usageCount += 1
                fav.touch()
            }
        }
        // Commit even when nothing was added: the widget refresh replaces the widget's optimistic value.
        guard commit(sync: !inserted.isEmpty) else {
            for trip in inserted { context.delete(trip) }
            for entry in touched {
                entry.favorite.usageCount = entry.usageCount
                entry.favorite.updatedAt = entry.updatedAt
            }
            return 0
        }
        QuickLogQueue.remove(items)
        if inserted.isEmpty {
            app.showToast("exclamationmark.triangle.fill",
                          skipped == 1 ? "Schnellerfassung verworfen" : "\(skipped) Schnellerfassungen verworfen",
                          "Der Favorit existiert nicht mehr")
        }
        return inserted.count
    }

    // MARK: Favourites

    @discardableResult
    func addFavorite(from trip: TripEntity, title: String = "") -> FavoriteRouteEntity {
        let count = (try? context.fetchCount(FetchDescriptor<FavoriteRouteEntity>())) ?? 0
        let fav = FavoriteRouteEntity(title: title, fromName: trip.fromName, toName: trip.toName, fromStationID: trip.fromStationID,
                                      toStationID: trip.toStationID, mode: trip.mode, distanceKm: trip.distanceKm,
                                      fareEUR: trip.fareEUR, isRoundTrip: trip.isRoundTrip, states: trip.states, sortIndex: count)
        context.insert(fav)
        commit()
        return fav
    }

    func addFavorite(_ favorite: FavoriteRouteEntity) {
        context.insert(favorite)
        commit()
    }

    func deleteFavorite(_ favorite: FavoriteRouteEntity) {
        favorite.deletedAt = Date()
        favorite.touch()
        commit()
    }

    // MARK: Tickets

    func addTicket(_ ticket: TicketEntity) {
        context.insert(ticket)
        app.settings.selectedTicketID = ticket.id
        commit()
        scheduleReminders(for: ticket)
    }

    func updateTicket(_ ticket: TicketEntity) {
        ticket.touch()
        commit()
        scheduleReminders(for: ticket)
    }

    func deleteTicket(_ ticket: TicketEntity) {
        ticket.deletedAt = Date()
        ticket.touch()
        if app.settings.selectedTicketID == ticket.id { app.settings.selectedTicketID = nil }
        commit()
        let id = ticket.id
        Task { await app.notifications.cancelRenewalReminders(ticketID: id) }
    }

    /// Creates the follow-up ticket (starts the day after `ticket` ends) with the catalog price for that start date.
    @discardableResult
    func renewTicket(_ ticket: TicketEntity) -> TicketEntity {
        let cal = Calendar.vienna
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: ticket.endDate) ?? ticket.endDate)
        let price = app.catalog.product(id: ticket.productID)?.price(forStart: start) ?? ticket.price
        let next = TicketEntity(productID: ticket.productID, name: ticket.name, variant: ticket.variant, family: ticket.family,
                                states: ticket.states, price: price, startDate: start, holderName: ticket.holderName,
                                ticketNumber: "")
        next.themeRaw = ticket.themeRaw
        next.remindersRaw = ticket.remindersRaw
        // How the holder pays carries over to the follow-up year (the edit sheet can change it).
        next.isMonthlyPayment = ticket.isMonthlyPayment
        next.autoRenews = ticket.autoRenews
        next.employerContribution = ticket.employerContribution
        next.addOnsRaw = ticket.addOnsRaw
        next.addOnPrice = ticket.addOnPrice
        addTicket(next)
        return next
    }

    func scheduleReminders(for ticket: TicketEntity) {
        guard app.settings.renewalRemindersEnabled else { return }
        let id = ticket.id, name = ticket.name, end = ticket.endDate, offsets = ticket.reminderOffsets
        Task { await app.notifications.scheduleRenewalReminders(ticketID: id, ticketName: name, end: end, offsets: offsets) }
    }

    // MARK: Bulk

    /// Local-only wipe (no cloud account, or sync not configured). Object by object (not the batch delete, which
    /// bypasses the registered models that live views hold); call it inside `SyncService.performLocalDataReplacement`
    /// so no screen still shows one of them.
    func deleteAllData() {
        for e in (try? context.fetch(FetchDescriptor<TripEntity>())) ?? [] { context.delete(e) }
        for e in (try? context.fetch(FetchDescriptor<FavoriteRouteEntity>())) ?? [] { context.delete(e) }
        for e in (try? context.fetch(FetchDescriptor<BenefitEntity>())) ?? [] { context.delete(e) }
        for e in (try? context.fetch(FetchDescriptor<TicketEntity>())) ?? [] { context.delete(e) }
        app.settings.selectedTicketID = nil
        commit(sync: false)
    }

    /// "Alles löschen" that also reaches the cloud: with a signed-in account every row is tombstoned and uploaded
    /// first, otherwise the data would come back with the next full download. Returns false when the upload failed
    /// (the tombstones stay hidden on the device and the next sync uploads them).
    @discardableResult
    func deleteAllDataEverywhere() async -> Bool {
        guard app.auth.isSignedIn, app.auth.isCloudAvailable else {
            await app.sync.performLocalDataReplacement { deleteAllData() }
            return true
        }
        let ok = await app.sync.deleteAllDataEverywhere(context: context, auth: app.auth)
        app.settings.selectedTicketID = nil
        refreshWidgets()
        return ok
    }

    // MARK: settings – "Demo-Daten entfernen"
    /// Tombstones the rows "Demo ansehen" inserted (`DemoDataStore.ids`) in one save: soft deletes, so the removal
    /// also reaches the cloud when the sample rows were synced. The user's own rows stay. Returns the removed count.
    @discardableResult
    func deleteDemoData(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        let now = Date()
        var removed = 0
        var ticketIDs: [UUID] = []
        for trip in liveTrips() where ids.contains(trip.id) {
            trip.deletedAt = now
            trip.touch()
            removed += 1
        }
        for favorite in liveFavorites() where ids.contains(favorite.id) {
            favorite.deletedAt = now
            favorite.touch()
            removed += 1
        }
        let benefits = (try? context.fetch(FetchDescriptor<BenefitEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        for benefit in benefits where ids.contains(benefit.id) {
            benefit.deletedAt = now
            benefit.touch()
            removed += 1
        }
        for ticket in liveTickets() where ids.contains(ticket.id) {
            ticket.deletedAt = now
            ticket.touch()
            ticketIDs.append(ticket.id)
            removed += 1
        }
        guard removed > 0 else { return 0 }
        if let selected = app.settings.selectedTicketID, ticketIDs.contains(selected) { app.settings.selectedTicketID = nil }
        commit()
        let notifications = app.notifications
        Task { for id in ticketIDs { await notifications.cancelRenewalReminders(ticketID: id) } }
        return removed
    }

    func liveTrips() -> [TripEntity] {
        (try? context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                        sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    func liveTickets() -> [TicketEntity] {
        (try? context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                          sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
    }

    func liveFavorites() -> [FavoriteRouteEntity] {
        (try? context.fetch(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                                 sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    /// Live trips inside `ticket`'s validity period (newest first) – what its analytics need, not every ticket year.
    func periodTrips(_ ticket: TicketEntity) -> [TripEntity] {
        let start = ticket.startDate, end = ticket.endDate
        let predicate = #Predicate<TripEntity> { $0.deletedAt == nil && $0.date >= start && $0.date <= end }
        return (try? context.fetch(FetchDescriptor<TripEntity>(predicate: predicate,
                                                               sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    /// The newest live trip of any ticket year (one row).
    func lastTrip() -> TripEntity? {
        var descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil },
                                                     sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Most used stations (favourites first, then by trip frequency) – used for trip detection regions.
    func frequentStationIDs(limit: Int = 20) -> [String] {
        var counts: [String: Int] = [:]
        for fav in liveFavorites() {
            for id in [fav.fromStationID, fav.toStationID].compactMap({ $0 }) { counts[id, default: 0] += 1000 }
        }
        for trip in liveTrips().prefix(400) {
            for id in [trip.fromStationID, trip.toStationID].compactMap({ $0 }) { counts[id, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    func configureTripDetection() {
        app.detection.configure(stations: app.stations, frequentStationIDs: frequentStationIDs(), estimator: app.estimator)
    }

    // MARK: Commit

    /// Saves, then schedules the follow-up work (widget snapshot, cloud sync – see CommitEffects) instead of doing it
    /// inside the tap. Returns false when SwiftData could not save: the user is told ("Speichern fehlgeschlagen"; the
    /// caller's success toast is suppressed), the changes stay pending and are retried (CommitEffects, every later
    /// commit, autosave), and neither the widgets nor the cloud see them before they are saved.
    @discardableResult
    func commit(sync: Bool = true, caller: String = #function) -> Bool {
        Diagnostics.action("save", detail: caller) // MARK: Diagnostics
        do {
            try Diagnostics.measure("Repository.save") { try context.save() }
        } catch {
            Self.log.error("save failed: \(String(describing: error), privacy: .public)")
            app.reportSaveFailure()
            CommitEffects.scheduleSaveRetry(context: context, app: app)
            return false
        }
        CommitEffects.saveDidSucceed()
        Analytics.invalidateCache()
        CommitEffects.scheduleWidgetRefresh(context: context, app: app)
        if sync { CommitEffects.scheduleSync(context: context, app: app) }
        return true
    }

    /// Writes the widget snapshot and reloads the widget timelines – only when the snapshot really changed.
    func refreshWidgets() {
        Diagnostics.measure("Widgets.refresh") { writeWidgetSnapshot() } // MARK: Diagnostics
    }

    private func writeWidgetSnapshot() {
        CommitEffects.widgetRefreshDidRun()
        guard let ticket = Analytics.activeTicket(in: liveTickets(), selectedID: app.settings.selectedTicketID) else {
            guard WidgetSnapshot.store.data(forKey: WidgetSnapshot.defaultsKey) != nil else { return }
            WidgetSnapshot.store.removeObject(forKey: WidgetSnapshot.defaultsKey)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let snapshot = WidgetSnapshotBuilder.make(ticket: ticket, trips: periodTrips(ticket), lastTrip: lastTrip(),
                                                  favorites: liveFavorites(), catalog: app.catalog)
        // Compared with what is stored – the widget's optimistic quick log may have changed it. A snapshot from
        // another day is always rewritten: the widgets count the remaining days from `generatedAt`.
        if var stored = WidgetSnapshot.load(),
           AnalyticsMemo.calendar.isDate(stored.generatedAt, inSameDayAs: snapshot.generatedAt) {
            stored.generatedAt = snapshot.generatedAt
            if stored == snapshot { return }
        }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()   // amortisation and quick-log widgets both read the snapshot
    }
}

enum WidgetSnapshotBuilder {
    @MainActor
    static func make(ticket: TicketEntity, trips: [TripEntity], favorites: [FavoriteRouteEntity], catalog: TariffCatalog) -> WidgetSnapshot {
        make(ticket: ticket, trips: trips, lastTrip: trips.filter { $0.deletedAt == nil }.max { $0.date < $1.date },
             favorites: favorites, catalog: catalog)
    }

    /// `trips` only needs the ticket period's trips; `last` is the newest live trip of any ticket year.
    @MainActor
    static func make(ticket: TicketEntity, trips: [TripEntity], lastTrip last: TripEntity?, favorites: [FavoriteRouteEntity],
                     catalog: TariffCatalog) -> WidgetSnapshot {
        let a = Analytics.make(ticket: ticket, trips: trips, catalog: catalog)
        let values = a.series.map(\.value)
        let step = max(1, values.count / 40)
        let sparkline = stride(from: 0, to: values.count, by: step).map { values[$0] } + (values.last.map { [$0] } ?? [])
        return WidgetSnapshot(
            generatedAt: Date(),
            ticketName: ticket.name,
            // The own share (price + add-ons − employer contribution) – what totalValue, amortizedFraction and
            // isPaidOff are measured against, here and in the widgets' optimistic quick-log update.
            ticketPrice: a.summary.ticketPrice,
            totalValue: a.summary.totalValue,
            amortizedFraction: a.summary.amortizedFraction,
            tripCount: a.summary.tripCount,
            distanceKm: a.summary.distanceKm,
            co2SavedKg: a.summary.co2SavedKg,
            daysRemaining: a.summary.daysRemaining,
            validUntil: ticket.endDate,
            isPaidOff: a.summary.isPaidOff,
            forecastBreakEvenDate: a.summary.forecastBreakEvenDate,
            lastTrip: last.map { .init(fromName: $0.fromName, toName: $0.toName, modeSymbol: $0.mode.symbolName, value: $0.totalValue, date: $0.date) },
            favorites: favorites.prefix(6).map { fav in
                WidgetSnapshot.Favorite(id: fav.id, title: fav.displayTitle, modeSymbol: fav.mode.symbolName,
                                        value: fav.fareEUR * (fav.isRoundTrip ? 2 : 1),
                                        distanceKm: fav.distanceKm * (fav.isRoundTrip ? 2 : 1),
                                        fromName: fav.fromName, toName: fav.toName)
            },
            sparkline: sparkline
        )
    }
}
