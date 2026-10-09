import Foundation
import SwiftData
import WidgetKit
import KlimaCore

/// All writes go through here so that saving, widget refresh, reminders and cloud sync stay consistent.
@MainActor
struct Repository {
    let context: ModelContext
    let app: AppState

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

    /// Soft delete (kept as tombstone for sync), returns an undo closure.
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

    /// Duplicates a past trip for today ("Nochmal fahren").
    @discardableResult
    func repeatTrip(_ trip: TripEntity, on date: Date = Date()) -> TripEntity {
        let copy = TripEntity(date: date, fromName: trip.fromName, toName: trip.toName, fromStationID: trip.fromStationID,
                              toStationID: trip.toStationID, mode: trip.mode, distanceKm: trip.distanceKm, fareEUR: trip.fareEUR,
                              isFareManual: trip.isFareManual, isRoundTrip: trip.isRoundTrip, travelClass: trip.travelClass,
                              companions: trip.companions, states: trip.states)
        copy.categoryRaw = trip.categoryRaw
        copy.isInduced = trip.isInduced
        context.insert(copy)
        commit()
        return copy
    }

    /// Ingests quick logs queued by widgets / Siri / Control Center. Returns the number of trips added.
    @discardableResult
    func ingestQuickLogs() -> Int {
        let items = QuickLogQueue.drain()
        guard !items.isEmpty else { return 0 }
        let favorites = liveFavorites()
        var added = 0
        for item in items {
            guard let fav = favorites.first(where: { $0.id == item.favoriteID }) else { continue }
            context.insert(fav.makeTrip(on: item.date))
            fav.usageCount += 1
            fav.touch()
            added += 1
        }
        commit()
        return added
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
        addTicket(next)
        return next
    }

    func scheduleReminders(for ticket: TicketEntity) {
        guard app.settings.renewalRemindersEnabled else { return }
        let id = ticket.id, name = ticket.name, end = ticket.endDate, offsets = ticket.reminderOffsets
        Task { await app.notifications.scheduleRenewalReminders(ticketID: id, ticketName: name, end: end, offsets: offsets) }
    }

    // MARK: Bulk

    /// Local-only wipe (no cloud account, or sync not configured).
    func deleteAllData() {
        try? context.delete(model: TripEntity.self)
        try? context.delete(model: FavoriteRouteEntity.self)
        try? context.delete(model: TicketEntity.self)
        try? context.delete(model: BenefitEntity.self)
        app.settings.selectedTicketID = nil
        commit(sync: false)
    }

    /// "Alles löschen" that also reaches the cloud: with a signed-in account every row is tombstoned and uploaded
    /// first, otherwise the data would come back with the next full download. Returns false when the upload failed
    /// (the tombstones stay hidden on the device and the next sync uploads them).
    @discardableResult
    func deleteAllDataEverywhere() async -> Bool {
        guard app.auth.isSignedIn, app.auth.isCloudAvailable else {
            deleteAllData()
            return true
        }
        let ok = await app.sync.deleteAllDataEverywhere(context: context, auth: app.auth)
        app.settings.selectedTicketID = nil
        refreshWidgets()
        return ok
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

    func commit(sync: Bool = true, caller: String = #function) {
        Diagnostics.action("save", detail: caller) // MARK: Diagnostics
        Diagnostics.measure("Repository.save") {
            do { try context.save() } catch { print("⚠️ save failed: \(error)") }
        }
        refreshWidgets()
        if sync {
            let context = context, app = app
            Task { await app.sync.sync(context: context, auth: app.auth) }
        }
    }

    /// Writes the widget snapshot and reloads widget timelines.
    func refreshWidgets() {
        Diagnostics.measure("Widgets.refresh") { writeWidgetSnapshot() } // MARK: Diagnostics
    }

    private func writeWidgetSnapshot() {
        let tickets = liveTickets()
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else {
            WidgetSnapshot.store.removeObject(forKey: WidgetSnapshot.defaultsKey)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let trips = liveTrips()
        let snapshot = WidgetSnapshotBuilder.make(ticket: ticket, trips: trips, favorites: liveFavorites(), catalog: app.catalog)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum WidgetSnapshotBuilder {
    @MainActor
    static func make(ticket: TicketEntity, trips: [TripEntity], favorites: [FavoriteRouteEntity], catalog: TariffCatalog) -> WidgetSnapshot {
        let a = Analytics.make(ticket: ticket, trips: trips, catalog: catalog)
        let last = trips.filter { $0.deletedAt == nil }.max { $0.date < $1.date }
        let values = a.series.map(\.value)
        let step = max(1, values.count / 40)
        let sparkline = stride(from: 0, to: values.count, by: step).map { values[$0] } + (values.last.map { [$0] } ?? [])
        return WidgetSnapshot(
            generatedAt: Date(),
            ticketName: ticket.name,
            ticketPrice: ticket.price,
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
