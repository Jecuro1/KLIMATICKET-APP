import Foundation

// MARK: - „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md) – the validity months of a ticket year with their counts

/// One validity month of the ticket („Gültigkeitsmonat“, AGB Punkt 24.2): from the ticket's start day number to the day before
/// the same number of the next month, in Vienna time (`PerkPassengerRights.validityMonths` – the months the Fahrgastrechte
/// screen marks). For a ticket that starts on the 1st these are the calendar months.
public struct DelayMonth: Hashable, Sendable, Identifiable {
    /// 0-based: the ticket's first validity month is 0.
    public var index: Int
    /// First moment of the month.
    public var start: Date
    /// Last second of the month (the ticket's end in its last month).
    public var end: Date
    /// The month's Fahrten up to now, oldest first.
    public var entries: [DelayDiaryEntry]
    /// `now` lies inside this month.
    public var isCurrent: Bool

    public var id: Int { index }
    public var tripCount: Int { entries.count }
    public var recordedCount: Int { entries.filter(\.isRecorded).count }
    public var lateCount: Int { entries.filter(\.isLate).count }
    /// Recorded below the mark („pünktlich“ marked or a small delay).
    public var onTimeCount: Int { recordedCount - lateCount }
    /// Fahrten without a recorded arrival: counted, but neither punctual nor late – they stay out of the share.
    public var notRecordedCount: Int { tripCount - recordedCount }
    /// Late Fahrten, oldest first.
    public var lateEntries: [DelayDiaryEntry] { entries.filter(\.isLate) }
    /// Fahrten without a recorded arrival, oldest first.
    public var unrecordedEntries: [DelayDiaryEntry] { entries.filter { !$0.isRecorded } }
    /// The personal on-time share, nil with fewer than `DelayDiaryRules.minimumRecordedForShare` recorded Fahrten.
    public var onTimeShare: Double? { DelayDiaryRules.onTimeShare(recorded: recordedCount, late: lateCount) }
    /// Minutes of the late Fahrten together.
    public var lateMinutes: Int { lateEntries.reduce(0) { $0 + ($1.minutes ?? 0) } }
    public var longestMinutes: Int { entries.compactMap(\.minutes).max() ?? 0 }
}

/// The diary of one ticket year: the validity months begun by `now`, oldest first, and the year's totals.
public struct DelayDiaryYear: Hashable, Sendable {
    public var months: [DelayMonth]
    public var options: DelayDiaryOptions

    public init(months: [DelayMonth], options: DelayDiaryOptions) {
        self.months = months
        self.options = options
    }

    public var entries: [DelayDiaryEntry] { months.flatMap(\.entries) }
    public var tripCount: Int { months.reduce(0) { $0 + $1.tripCount } }
    public var recordedCount: Int { months.reduce(0) { $0 + $1.recordedCount } }
    public var lateCount: Int { months.reduce(0) { $0 + $1.lateCount } }
    public var onTimeCount: Int { recordedCount - lateCount }
    public var notRecordedCount: Int { tripCount - recordedCount }
    public var lateMinutes: Int { months.reduce(0) { $0 + $1.lateMinutes } }
    /// The year's personal share – nil below `DelayDiaryRules.minimumRecordedForShare` recorded Fahrten.
    public var onTimeShare: Double? { DelayDiaryRules.onTimeShare(recorded: recordedCount, late: lateCount) }
    /// Nothing recorded yet (the empty state).
    public var isEmpty: Bool { recordedCount == 0 }
    /// The latest late Fahrt with the most minutes (ties: the later one).
    public var longest: DelayDiaryEntry? {
        entries.filter(\.isLate).max { lhs, rhs in
            let l = lhs.minutes ?? 0, r = rhs.minutes ?? 0
            return l != r ? l < r : lhs.date < rhs.date
        }
    }
    public var currentMonth: DelayMonth? { months.first(where: \.isCurrent) }
    public var threshold: Int { DelayDiaryRules.normalizedThreshold(options.thresholdMinutes) }
}

public enum DelayDiaryCalculator {
    /// The diary for the ticket valid from `ticketStart` to `ticketEnd` (both included, like `TicketPeriod.contains`).
    /// Only trips inside the ticket and up to `now` count; months that have not begun by `now` are left out (an unstarted
    /// ticket has none). A Fahrt belongs to the month of its departure; the months are half-open, so 23:59:59 on the last day
    /// is the old month and 00:00 the new one.
    public static func compute(trips: [DelayDiaryTrip], ticketStart: Date, ticketEnd: Date, now: Date,
                               options: DelayDiaryOptions = DelayDiaryOptions(), calendar: Calendar = .vienna) -> DelayDiaryYear {
        let intervals = PerkPassengerRights.validityMonths(start: ticketStart, end: ticketEnd, calendar: calendar)
        let begun = intervals.enumerated().filter { $0.element.start <= now }
        guard !begun.isEmpty else { return DelayDiaryYear(months: [], options: options) }
        let starts = intervals.map(\.start)
        let inTicket = trips.filter { $0.date >= ticketStart && $0.date <= ticketEnd }
        let entries = DelayDiaryEntries.make(inTicket, options: options, now: now)
        var buckets: [Int: [DelayDiaryEntry]] = [:]
        for entry in entries {
            guard let index = monthIndex(of: entry.date, starts: starts) else { continue }
            buckets[index, default: []].append(entry)
        }
        let months = begun.map { index, interval in
            let next = index + 1 < starts.count ? starts[index + 1] : nil
            let isCurrent = interval.start <= now && (next.map { now < $0 } ?? (now <= ticketEnd))
            return DelayMonth(index: index, start: interval.start, end: interval.end, entries: buckets[index] ?? [], isCurrent: isCurrent)
        }
        return DelayDiaryYear(months: months, options: options)
    }

    /// The month whose start is the last one at or before `date` (half-open months; nil before the first).
    static func monthIndex(of date: Date, starts: [Date]) -> Int? {
        guard let first = starts.first, date >= first else { return nil }
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= date { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
