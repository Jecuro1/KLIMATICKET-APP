import Foundation

/// Everything the dashboard needs to answer "Hat sich mein Ticket schon rentiert?".
public struct SavingsSummary: Hashable, Sendable {
    public var ticketPrice: Double
    /// Sum of regular fares of all trips within the ticket period.
    public var totalValue: Double
    /// totalValue − ticketPrice (positive = profit).
    public var net: Double
    /// totalValue / ticketPrice (can exceed 1).
    public var amortizedFraction: Double
    public var tripCount: Int
    public var legCount: Int
    public var travelDays: Int
    public var distanceKm: Double
    public var co2SavedKg: Double
    /// What the same km would have cost by car (Kilometergeld).
    public var carCostEquivalent: Double
    public var daysElapsed: Int
    public var daysTotal: Int
    public var daysRemaining: Int
    /// Ticket cost per day so far and value per day so far.
    public var costPerDay: Double
    public var valuePerDay: Double
    public var averageValuePerTrip: Double
    /// Effective price per km actually paid (ticketPrice / km).
    public var effectivePricePerKm: Double?
    public var isPaidOff: Bool
    /// Day the cumulative value crossed the ticket price (if already paid off).
    public var paidOffDate: Date?
    /// Forecast of the break-even day (nil if already paid off or no pace yet).
    public var forecastBreakEvenDate: Date?
    /// Forecast of the total value at the end of the period at the current pace.
    public var forecastEndValue: Double
    /// Whether the break-even forecast lands within the validity period.
    public var forecastReachesBreakEven: Bool

    public var remainingToBreakEven: Double { max(0, ticketPrice - totalValue) }
    public var progressClamped: Double { min(max(amortizedFraction, 0), 1) }
}

public struct CumulativePoint: Hashable, Sendable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public enum SavingsCalculator {
    /// Computes the summary for one ticket period. Trips outside the period are ignored.
    public static func summary(ticket: TicketPeriod, trips allTrips: [TripRecord], now: Date = Date(),
                               kilometergeld: Double = 0.50, emissions: EmissionFactors = .fallback,
                               calendar: Calendar = .vienna) -> SavingsSummary {
        let trips = allTrips.filter { ticket.contains($0.date) }.sorted { $0.date < $1.date }
        let value = trips.reduce(0) { $0 + $1.totalValue }
        let km = trips.reduce(0) { $0 + $1.totalDistanceKm }
        let co2 = trips.reduce(0) { $0 + emissions.savedKg(km: $1.totalDistanceKm, mode: $1.mode) }
        let legs = trips.reduce(0) { $0 + $1.legs }
        // A journey (Bus → Zug → Bim) is one "Fahrt"; its legs add their values, km and CO₂ (docs/JOURNEYS.md).
        let tripCount = JourneySummary.tripCount(trips)
        var memo = DayMemo(calendar)
        let days = Set(trips.map { memo.startOfDay($0.date) }).count

        let startDay = calendar.startOfDay(for: ticket.start)
        let endDay = calendar.startOfDay(for: ticket.end)
        let today = calendar.startOfDay(for: min(max(now, ticket.start), ticket.end))
        let daysTotal = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 364) + 1)
        let daysElapsed = min(daysTotal, max(1, (calendar.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1))
        let daysRemaining = now > ticket.end ? 0 : max(0, daysTotal - daysElapsed)

        // An own share of € 0 (the employer pays the whole ticket) is paid off from the first day: 100 %, not
        // value / 1 cent (which read "4.500.000 %").
        let fraction = ticket.price > 0 ? value / ticket.price : 1

        var paidOff: Date?
        var running = 0.0
        for t in trips {
            running += t.totalValue
            if running >= ticket.price { paidOff = t.date; break }
        }

        let forecast = BreakEvenForecaster.forecast(ticket: ticket, trips: trips, now: now, calendar: calendar)

        return SavingsSummary(
            ticketPrice: ticket.price,
            totalValue: value,
            net: value - ticket.price,
            amortizedFraction: fraction,
            tripCount: tripCount,
            legCount: legs,
            travelDays: days,
            distanceKm: km,
            co2SavedKg: co2,
            carCostEquivalent: km * kilometergeld,
            daysElapsed: daysElapsed,
            daysTotal: daysTotal,
            daysRemaining: daysRemaining,
            costPerDay: ticket.price / Double(daysTotal),
            valuePerDay: value / Double(daysElapsed),
            averageValuePerTrip: tripCount == 0 ? 0 : value / Double(tripCount),
            effectivePricePerKm: km > 0 ? ticket.price / km : nil,
            isPaidOff: value >= ticket.price,
            paidOffDate: paidOff,
            forecastBreakEvenDate: paidOff == nil ? forecast.breakEvenDate : nil,
            forecastEndValue: forecast.projectedEndValue,
            forecastReachesBreakEven: paidOff != nil || (forecast.breakEvenDate.map { $0 <= ticket.end } ?? false)
        )
    }

    /// Daily cumulative value series from ticket start to `min(now, end)` (one point per day with activity,
    /// plus start and today) – ideal for a step/line chart against the ticket price rule mark.
    public static func cumulativeSeries(ticket: TicketPeriod, trips: [TripRecord], now: Date = Date(),
                                        calendar: Calendar = .vienna) -> [CumulativePoint] {
        let relevant = trips.filter { ticket.contains($0.date) }
        var perDay: [Date: Double] = [:]
        var memo = DayMemo(calendar)
        for t in relevant { perDay[memo.startOfDay(t.date), default: 0] += t.totalValue }
        let start = calendar.startOfDay(for: ticket.start)
        let last = calendar.startOfDay(for: min(now, ticket.end))
        var points = [CumulativePoint(date: start, value: 0)]
        var running = 0.0
        for day in perDay.keys.sorted() where day >= start {
            running += perDay[day] ?? 0
            points.append(CumulativePoint(date: day, value: running))
        }
        if let lastPoint = points.last, lastPoint.date < last {
            points.append(CumulativePoint(date: last, value: running))
        }
        return points
    }

    /// Forecast line from today to the end of the period at the current pace.
    public static func forecastSeries(ticket: TicketPeriod, trips: [TripRecord], now: Date = Date(),
                                      calendar: Calendar = .vienna) -> [CumulativePoint] {
        guard now < ticket.end else { return [] }
        let current = trips.filter { ticket.contains($0.date) && $0.date <= now }.reduce(0) { $0 + $1.totalValue }
        let pace = BreakEvenForecaster.dailyPace(ticket: ticket, trips: trips, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: max(now, ticket.start))
        let end = calendar.startOfDay(for: ticket.end)
        let remainingDays = Double(calendar.dateComponents([.day], from: today, to: end).day ?? 0)
        return [CumulativePoint(date: today, value: current),
                CumulativePoint(date: end, value: current + pace * remainingDays)]
    }
}

public enum BreakEvenForecaster {
    public struct Forecast: Hashable, Sendable {
        public var dailyPace: Double
        public var breakEvenDate: Date?
        public var projectedEndValue: Double
    }

    /// Value per day, blending the long-run average with the recent 42-day pace (recent weighted 60 %).
    public static func dailyPace(ticket: TicketPeriod, trips: [TripRecord], now: Date, calendar: Calendar = .vienna) -> Double {
        let start = calendar.startOfDay(for: ticket.start)
        let today = calendar.startOfDay(for: min(max(now, ticket.start), ticket.end))
        let elapsed = Double(max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1))
        let inPeriod = trips.filter { ticket.contains($0.date) && $0.date <= now }
        let total = inPeriod.reduce(0) { $0 + $1.totalValue }
        // In the first weeks a handful of trips would extrapolate wildly (2 trips on day 3 → €6.000/year).
        // Spread the value over at least three weeks so early forecasts stay conservative; converges once real data exists.
        let periodDays = Double(max(1, (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: ticket.end)).day ?? 0) + 1))
        let longRun = total / max(elapsed, min(21, periodDays))
        guard elapsed > 14 else { return longRun }
        let window = min(42.0, elapsed)
        let windowStart = calendar.date(byAdding: .day, value: -Int(window) + 1, to: today) ?? start
        let recent = inPeriod.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.totalValue } / window
        return 0.4 * longRun + 0.6 * recent
    }

    public static func forecast(ticket: TicketPeriod, trips: [TripRecord], now: Date, calendar: Calendar = .vienna) -> Forecast {
        let pace = dailyPace(ticket: ticket, trips: trips, now: now, calendar: calendar)
        let current = trips.filter { ticket.contains($0.date) && $0.date <= now }.reduce(0) { $0 + $1.totalValue }
        let today = calendar.startOfDay(for: min(max(now, ticket.start), ticket.end))
        let end = calendar.startOfDay(for: ticket.end)
        let remainingDays = Double(max(0, calendar.dateComponents([.day], from: today, to: end).day ?? 0))
        let projected = current + pace * remainingDays
        var date: Date?
        if current < ticket.price, pace > 0.0001 {
            let daysNeeded = ((ticket.price - current) / pace).rounded(.up)
            if daysNeeded < 3650 {
                date = calendar.date(byAdding: .day, value: Int(daysNeeded), to: today)
            }
        }
        return Forecast(dailyPace: pace, breakEvenDate: date, projectedEndValue: projected)
    }
}
