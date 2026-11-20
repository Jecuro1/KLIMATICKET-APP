import Foundation

// MARK: siri – builds the table Siri answers from (docs/SIRI_QUESTIONS.md §2). The ticket year is the app's SavingsSummary as it is
// (Statistik's numbers, never computed again); the days use the summary's own per-trip terms – `totalValue`, `totalDistanceKm`,
// `EmissionFactors.savedKg` and „a journey counts once“ – so the days of the ticket period add up to the summary (SiriKpiTableTests).

public enum KpiTableBuilder {
    /// - Parameters:
    ///   - ticket: the active ticket's period and its summary (from `SavingsCalculator.summary`, the one Statistik shows); nil
    ///     without a ticket.
    ///   - trips: live trips; any superset of the window works (older and later ones are left out).
    public static func make(ticket: (period: TicketPeriod, summary: SavingsSummary)?, trips: [TripRecord], now: Date,
                            emissions: EmissionFactors, format: FormatPrefs = .standard, calendar: Calendar = .vienna) -> KpiDailyTable {
        KpiDailyTable(generatedAt: now, format: format, ticket: ticket.map(figures), days: days(trips, now: now, emissions: emissions, calendar: calendar))
    }

    static func figures(_ ticket: (period: TicketPeriod, summary: SavingsSummary)) -> KpiDailyTable.Ticket {
        let s = ticket.summary
        return KpiDailyTable.Ticket(name: ticket.period.name, start: ticket.period.start, end: ticket.period.end, price: s.ticketPrice,
                                    tripCount: s.tripCount, totalValue: s.totalValue, distanceKm: s.distanceKm, co2SavedKg: s.co2SavedKg,
                                    paidOffDate: s.paidOffDate, forecastBreakEvenDate: s.forecastBreakEvenDate,
                                    forecastReachesBreakEven: s.forecastReachesBreakEven)
    }

    /// Day rows of the `KpiDailyTable.dayWindow` days up to today (and trips logged ahead, up to as many days on): one row per
    /// Vienna day with trips. A journey counts on the day of its first leg, its legs' values, km and CO₂ on their own days.
    public static func days(_ trips: [TripRecord], now: Date, emissions: EmissionFactors, calendar: Calendar = .vienna) -> [KpiDailyTable.Day] {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(KpiDailyTable.dayWindow - 1), to: today) ?? today
        let after = calendar.date(byAdding: .day, value: KpiDailyTable.dayWindow + 1, to: today) ?? today

        // The first leg of every journey among all given trips (earliest date, then leg index, then id: always the same one).
        var firstLeg: [UUID: TripRecord] = [:]
        for trip in trips {
            guard let journey = trip.journeyID else { continue }
            if let known = firstLeg[journey], (known.date, known.legIndex, known.id.uuidString) <= (trip.date, trip.legIndex, trip.id.uuidString) {
                continue
            }
            firstLeg[journey] = trip
        }

        var rows: [String: KpiDailyTable.Day] = [:]
        var memo = DayMemo(calendar)
        var keys: [Date: String] = [:]
        for trip in trips where trip.date >= first && trip.date < after {
            let start = memo.startOfDay(trip.date)
            let key = keys[start] ?? KpiDailyTable.dayKey(start, calendar: calendar)
            keys[start] = key
            var row = rows[key] ?? KpiDailyTable.Day(day: key, journeys: 0, value: 0, km: 0, co2: 0)
            if let journey = trip.journeyID {
                if firstLeg[journey]?.id == trip.id { row.journeys += 1 }
            } else {
                row.journeys += 1
            }
            row.value += trip.totalValue
            row.km += trip.totalDistanceKm
            row.co2 += emissions.savedKg(km: trip.totalDistanceKm, mode: trip.mode)
            rows[key] = row
        }
        return rows.values.sorted { $0.day < $1.day }
    }
}
