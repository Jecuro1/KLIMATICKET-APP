import Foundation
import SwiftData
import KlimaCore

/// Builds `RideStart`s from the app's data: the trip editor's form, a favourite route, or – when the database is not
/// at hand (App Intent in a cold background launch) – the widget snapshot.
@MainActor
enum RidePlanner {
    /// The editor offers "Fahrt jetzt starten" for departures from 3 hours ago up to 1 hour ahead.
    static let pastWindow: TimeInterval = 3 * 60 * 60
    static let futureWindow: TimeInterval = 60 * 60

    static func canStart(at date: Date, now: Date = Date()) -> Bool {
        let offset = date.timeIntervalSince(now)
        return offset >= -pastWindow && offset <= futureWindow
    }

    /// The editor's departure time when it already lies in the past (boarded a few minutes ago), else now.
    static func startDate(for date: Date, now: Date = Date()) -> Date {
        canStart(at: date, now: now) && date < now ? date : now
    }

    // MARK: Sources

    /// From the trip editor (nil while the form cannot be saved).
    static func ride(from model: TripEditorModel, context: ModelContext, now: Date = Date()) -> RideStart? {
        guard model.canSave else { return nil }
        let trip = RideTrip(fromName: model.resolvedFromName, toName: model.resolvedToName,
                            fromStationID: model.fromStation?.id, toStationID: model.toStation?.id,
                            mode: model.mode, distanceKm: model.distanceKm, fareEUR: model.fare,
                            isFareManual: model.isFareManual, isRoundTrip: model.isRoundTrip, travelClass: model.travelClass,
                            companions: model.companions, states: model.states, note: model.note)
        guard trip.isValid else { return nil }
        return make(trip: trip, startedAt: startDate(for: model.date, now: now), context: context, app: model.app)
    }

    /// From a favourite route ("Fahrt starten" App Intent, previews).
    static func ride(favorite: FavoriteRouteEntity, context: ModelContext, app: AppState, startedAt: Date = Date()) -> RideStart {
        let trip = RideTrip(fromName: favorite.fromName, toName: favorite.toName, fromStationID: favorite.fromStationID,
                            toStationID: favorite.toStationID, mode: favorite.mode, distanceKm: favorite.distanceKm,
                            fareEUR: favorite.fareEUR, isFareManual: false, isRoundTrip: favorite.isRoundTrip,
                            travelClass: app.settings.defaultTravelClass, states: favorite.states,
                            category: TripCategory(rawValue: favorite.categoryRaw), favoriteID: favorite.id)
        return make(trip: trip, startedAt: startedAt, context: context, app: app)
    }

    /// From a favourite id: the database when the app is up, else the widget snapshot. Nil when the favourite is gone.
    static func ride(favoriteID: UUID, now: Date = Date()) -> RideStart? {
        if let app = AppDelegate.appState, let container = AppDelegate.container {
            let context = container.mainContext
            if let favorite = Repository(context: context, app: app).liveFavorites().first(where: { $0.id == favoriteID }) {
                return ride(favorite: favorite, context: context, app: app, startedAt: now)
            }
        }
        guard let snapshot = WidgetSnapshot.load(), let favorite = snapshot.favorites.first(where: { $0.id == favoriteID }) else {
            return nil
        }
        return ride(snapshotFavorite: favorite, snapshot: snapshot, now: now)
    }

    /// Widget-snapshot fallback: the favourite's value and the balance the widgets show.
    static func ride(snapshotFavorite favorite: WidgetSnapshot.Favorite, snapshot: WidgetSnapshot, now: Date) -> RideStart {
        let mode = WidMode.mode(forSymbol: favorite.modeSymbol) ?? .train
        // The snapshot stores the favourite's whole value (both directions); a single leg keeps the saved value identical.
        let trip = RideTrip(fromName: favorite.fromName.isEmpty ? favorite.title : favorite.fromName,
                            toName: favorite.toName.isEmpty ? favorite.title : favorite.toName,
                            mode: mode, distanceKm: favorite.distanceKm, fareEUR: favorite.value, favoriteID: favorite.id)
        var ride = RideStart(trip: trip, startedAt: now)
        // Price the payoff is measured against (own share): what the snapshot's fraction implies.
        let price = snapshot.amortizedFraction > 0.0001 ? snapshot.totalValue / snapshot.amortizedFraction : snapshot.ticketPrice
        if now <= snapshot.validUntil {
            ride.payoff = RidePayoff(currentValue: snapshot.totalValue, ticketPrice: price, rideValue: trip.totalValue)
            ride.climb = RideClimb.fractions(cumulative: snapshot.sparkline, ticketPrice: price)
        }
        ride.ticketName = snapshot.ticketName
        return ride
    }

    // MARK: Ticket context

    private static func make(trip: RideTrip, startedAt: Date, context: ModelContext, app: AppState) -> RideStart {
        var ride = RideStart(trip: trip, startedAt: startedAt)
        guard let balance = balance(context: context, app: app, at: startedAt) else { return ride }
        ride.ticketName = balance.ticketName
        ride.payoff = RidePayoff(currentValue: balance.value, ticketPrice: balance.price, rideValue: trip.totalValue)
        ride.climb = RideClimb.fractions(cumulative: balance.series, ticketPrice: balance.price)
        return ride
    }

    struct Balance {
        var ticketName: String
        /// Value of all trips in the ticket period so far, EUR.
        var value: Double
        /// What the payoff is measured against (own share), EUR.
        var price: Double
        /// Cumulative value per day.
        var series: [Double]
    }

    /// The active ticket's balance when it covers `date` and has a price.
    static func balance(context: ModelContext, app: AppState, at date: Date = Date()) -> Balance? {
        let repo = Repository(context: context, app: app)
        guard let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID),
              ticket.period.contains(date) else { return nil }
        let analytics = Analytics.make(ticket: ticket, trips: repo.liveTrips(), catalog: app.catalog)
        guard analytics.summary.ticketPrice > 0 else { return nil }
        return Balance(ticketName: ticket.name, value: analytics.summary.totalValue, price: analytics.summary.ticketPrice,
                       series: analytics.series.map(\.value))
    }
}
