import Foundation

/// „Raten-Übersicht“: the 12 monthly installments of a KlimaTicket Ö paid by SEPA direct debit, and what has been paid so far.
///
/// AGB 15.2 (Stand 1.1.2026): the first two installments are paid at once with the order, the rest of the validity months are
/// debited in ten equal installments within the first five working days of each calendar month. (For a contract renewed by
/// SEPA, 15.6 has all twelve debited in the first five working days of a month – the difference lies only in the first
/// validity month, so the plan does not tell them apart.)
///
/// The AGB do not say how a cent of rounding is split: eleven installments are rounded to the cent and the twelfth takes the
/// difference, so the twelve add up to the ticket price exactly. Public holidays are not considered (Mon–Fri count as working
/// days), the plan says „rund um den Monatsanfang“ – the real booking day depends on the bank.
public struct InstallmentPlan: Equatable, Sendable {
    public static let count = 12
    /// Paid with the order (AGB 15.2).
    public static let upfrontCount = 2
    /// The debit happens within the first N working days of the calendar month (AGB 15.2).
    public static let debitWorkingDays = 5

    public struct Item: Equatable, Sendable, Identifiable {
        public enum Timing: Equatable, Sendable {
            /// Paid with the order.
            case withOrder
            /// Debited „rund um den Monatsanfang“ (first five working days).
            case aroundMonthStart
        }

        public enum State: Equatable, Sendable {
            case paid
            /// The booking window of its month has begun but not ended: it may have been debited already, not counted as paid yet.
            case booking
            case upcoming
        }

        /// 1…12 – the installment pays for validity month `number`.
        public var number: Int
        public var amountCents: Int
        public var timing: Timing
        /// First day of the calendar month the booking belongs to (the month the validity month begins in).
        public var month: Date
        /// The moment after the fifth working day of that month (debits only).
        public var windowEnd: Date?
        public var state: State

        public var id: Int { number }
        public var amount: Double { Double(amountCents) / 100 }
    }

    public var priceCents: Int
    public var items: [Item]

    public var price: Double { Double(priceCents) / 100 }
    public var paidCount: Int { items.filter { $0.state == .paid }.count }
    public var paidCents: Int { items.filter { $0.state == .paid }.reduce(0) { $0 + $1.amountCents } }
    public var paidAmount: Double { Double(paidCents) / 100 }
    public var openCount: Int { Self.count - paidCount }
    public var openCents: Int { priceCents - paidCents }
    public var openAmount: Double { Double(openCents) / 100 }
    public var isComplete: Bool { openCount == 0 }
    /// The first installment that is not paid yet.
    public var next: Item? { items.first { $0.state != .paid } }
    /// The usual amount of one installment (the twelfth may differ by a few cents).
    public var typicalAmount: Double { Double(items.first?.amountCents ?? 0) / 100 }
    /// True when the last installment differs from the others by the rounding.
    public var lastDiffers: Bool { (items.last?.amountCents ?? 0) != (items.first?.amountCents ?? 0) }

    /// Builds the plan for a ticket price and the first day of validity; nil without a positive price.
    public static func make(price: Double, start: Date, now: Date = Date(), calendar: Calendar = .vienna) -> InstallmentPlan? {
        let priceCents = Int((price * 100).rounded())
        guard priceCents > 0 else { return nil }
        let base = Int((Double(priceCents) / Double(count)).rounded())
        let startDay = calendar.startOfDay(for: start)
        var items: [Item] = []
        var assigned = 0
        for number in 1...count {
            let cents = number == count ? priceCents - assigned : base
            assigned += cents
            let validityStart = calendar.date(byAdding: .month, value: number - 1, to: startDay) ?? startDay
            let month = firstOfMonth(validityStart, calendar: calendar)
            if number <= upfrontCount {
                items.append(Item(number: number, amountCents: cents, timing: .withOrder, month: firstOfMonth(startDay, calendar: calendar),
                                  windowEnd: nil, state: .paid))
            } else {
                let end = windowEnd(inMonthOf: month, calendar: calendar)
                let state: Item.State = now >= end ? .paid : (now >= month ? .booking : .upcoming)
                items.append(Item(number: number, amountCents: cents, timing: .aroundMonthStart, month: month, windowEnd: end, state: state))
            }
        }
        return InstallmentPlan(priceCents: priceCents, items: items)
    }

    // MARK: Calendar helpers

    static func firstOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// The moment right after the fifth working day (Monday to Friday) of the month that begins at `monthStart`.
    static func windowEnd(inMonthOf monthStart: Date, calendar: Calendar) -> Date {
        var day = monthStart
        var counted = 0
        for _ in 0..<14 {
            let weekday = calendar.component(.weekday, from: day)   // 1 = Sunday … 7 = Saturday
            if (2...6).contains(weekday) { counted += 1 }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            if counted == debitWorkingDays { return next }
            day = next
        }
        return day
    }
}

// MARK: - Paid versus received

extension InstallmentPlan {
    /// Cash paid so far next to the value of the trips so far – the honest comparison of the screen.
    public struct Balance: Equatable, Sendable {
        public var paid: Double
        public var value: Double

        /// The trips are already worth what has been paid (to the cent).
        public var coversPayments: Bool { value + 0.005 >= paid }
        /// How far apart the two are (always ≥ 0).
        public var difference: Double { abs(value - paid) }
    }

    /// Paid so far against `tripValue` (the value of the trips of this ticket year so far, from `Analytics`).
    public func balance(tripValue: Double) -> Balance {
        Balance(paid: paidAmount, value: max(0, tripValue))
    }
}
