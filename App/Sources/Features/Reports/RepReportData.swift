import Foundation
import KlimaCore

/// Everything the annual report ("Dein KlimaTicket-Jahr") prints, derived once from one ticket period.
struct RepReportData {
    struct ModeLine: Identifiable {
        var mode: TransportMode
        var trips: Int
        var value: Double
        var share: Double
        var id: String { mode.rawValue }
    }

    struct MonthLine: Identifiable {
        var id: String
        var month: Date
        var value: Double
        var trips: Int
        var isBest: Bool
        var isFuture: Bool
        var label: String { StatsNames.shortMonth(month) }
    }

    struct CategoryLine: Identifiable {
        var category: TripCategory
        var trips: Int
        var value: Double
        var id: String { category.rawValue }
    }

    let ticketName: String
    let holderName: String
    let yearLabel: String
    let period: TicketPeriod
    /// List price, add-ons and employer share (the payoff is measured against `ownShare` = `period.price`).
    let listPrice: Double
    let addOnPrice: Double
    let employerContribution: Double
    let isMonthlyPayment: Bool
    let snapshot: AnalyticsSnapshot
    let months: [MonthLine]
    let modes: [ModeLine]
    let categories: [CategoryLine]
    let inducedTrips: Int
    let inducedValue: Double
    let benefitsCount: Int
    let benefitsValue: Double
    let notes: [UUID: String]
    let generatedAt: Date

    var summary: SavingsSummary { snapshot.summary }
    var ownShare: Double { period.price }
    var hasTrips: Bool { !snapshot.trips.isEmpty }
    var isRunning: Bool { generatedAt >= period.start && generatedAt <= period.end }
    /// Ticket price ÷ 12 – the monthly "Soll" to break even.
    var monthlyTarget: Double { ownShare / 12 }
    var fileName: String { "KlimaBilanz-Jahresbericht-\(yearLabel.replacingOccurrences(of: "/", with: "-")).pdf" }
    var title: String { "Dein KlimaTicket-Jahr \(yearLabel)" }

    @MainActor
    static func make(ticket: TicketEntity, trips: [TripEntity], benefits: [BenefitEntity], catalog: TariffCatalog,
                     now: Date = Date()) -> RepReportData {
        let snapshot = Analytics.make(ticket: ticket, trips: trips, catalog: catalog, now: now)
        let period = snapshot.ticket
        let records = snapshot.trips

        // Months of the whole ticket year (empty future months stay visible as the year's frame).
        let cal = Calendar.vienna
        let values = Dictionary(snapshot.months.map { (cal.dateComponents([.year, .month], from: $0.month), $0) }, uniquingKeysWith: { a, _ in a })
        var monthLines: [MonthLine] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: period.start)) ?? period.start
        let lastMonth = cal.date(from: cal.dateComponents([.year, .month], from: period.end)) ?? period.end
        let currentMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        while cursor <= lastMonth && monthLines.count < 14 {
            let key = cal.dateComponents([.year, .month], from: cursor)
            let bucket = values[key]
            let c = cal.dateComponents([.year, .month], from: cursor)
            monthLines.append(MonthLine(id: String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0), month: cursor,
                                        value: bucket?.value ?? 0, trips: bucket?.trips ?? 0, isBest: false,
                                        isFuture: cursor > currentMonth))
            cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? lastMonth.addingTimeInterval(86_400 * 40)
        }
        if let best = monthLines.indices.max(by: { monthLines[$0].value < monthLines[$1].value }), monthLines[best].value > 0 {
            monthLines[best].isBest = true
        }

        let totalValue = max(snapshot.summary.totalValue, 0.0001)
        let modeLines = snapshot.modes
            .filter { $0.trips > 0 }
            .sorted { $0.value > $1.value }
            .map { ModeLine(mode: $0.mode, trips: $0.trips, value: $0.value, share: $0.value / totalValue) }

        var categoryMap: [TripCategory: (Int, Double)] = [:]
        for r in records {
            guard let category = r.category else { continue }
            let current = categoryMap[category] ?? (0, 0)
            categoryMap[category] = (current.0 + 1, current.1 + r.totalValue)
        }
        let categoryLines = categoryMap.map { CategoryLine(category: $0.key, trips: $0.value.0, value: $0.value.1) }
            .sorted { $0.value > $1.value }

        let induced = records.filter(\.isInduced)
        let periodBenefits = benefits.filter { $0.deletedAt == nil && period.contains($0.date) }
        var notes: [UUID: String] = [:]
        for trip in trips where trip.deletedAt == nil && !trip.note.isEmpty { notes[trip.id] = trip.note }

        return RepReportData(
            ticketName: ticket.name,
            holderName: ticket.holderName,
            yearLabel: StatsCalc.ticketYearLabel(period),
            period: period,
            listPrice: ticket.price,
            addOnPrice: ticket.addOnPrice,
            employerContribution: ticket.employerContribution,
            isMonthlyPayment: ticket.isMonthlyPayment,
            snapshot: snapshot,
            months: monthLines,
            modes: modeLines,
            categories: categoryLines,
            inducedTrips: induced.count,
            inducedValue: induced.reduce(0) { $0 + $1.totalValue },
            benefitsCount: periodBenefits.count,
            benefitsValue: periodBenefits.reduce(0) { $0 + $1.savedEUR },
            notes: notes,
            generatedAt: now)
    }

    // MARK: Wording

    /// "Noch € 350 bis zum Break-even" / "Rentiert seit 14. Dez. · + € 412".
    var verdict: String {
        if summary.isPaidOff {
            if let date = summary.paidOffDate {
                return "Rentiert seit \(Format.dayMonth(date)) · + \(Format.euro(summary.net, decimals: 0)) gespart"
            }
            return "Rentiert · + \(Format.euro(summary.net, decimals: 0)) gespart"
        }
        if isRunning, summary.forecastReachesBreakEven, let date = summary.forecastBreakEvenDate {
            return "Noch \(Format.euro(summary.remainingToBreakEven, decimals: 0)) · Break-even voraussichtlich \(Format.dayMonth(date))"
        }
        return "Noch \(Format.euro(summary.remainingToBreakEven, decimals: 0)) bis zum Break-even"
    }

    /// "1. März 2026 – 28. Februar 2027"
    var validityText: String { "\(RepText.longDate(period.start)) – \(RepText.longDate(period.end))" }

    /// Effective cost per trip (own share ÷ trips).
    var costPerTrip: Double? { summary.tripCount > 0 ? ownShare / Double(summary.tripCount) : nil }
}
