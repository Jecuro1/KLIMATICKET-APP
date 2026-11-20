import Foundation

// MARK: - „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md) – the rows of „Nachweis als PDF“

/// One late Fahrt in the PDF.
public struct DelayReportRow: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var fromName: String
    public var toName: String
    public var isRoundTrip: Bool
    public var legCount: Int
    /// The Fahrplan's line summary („RJX 662“), "" when unknown.
    public var train: String
    public var minutes: Int
    public var source: TripDelaySource

    /// „St. Anton am Arlberg → Innsbruck Hbf“, „… (Hin & Retour)“, „… (3 Etappen)“.
    public var route: String { DelayDiaryText.route(from: fromName, to: toName, roundTrip: isRoundTrip, legs: legCount) }
}

/// One validity month in the PDF: its counts and its late Fahrten.
public struct DelayReportMonth: Hashable, Sendable, Identifiable {
    public var index: Int
    public var start: Date
    public var end: Date
    public var tripCount: Int
    public var recordedCount: Int
    public var lateCount: Int
    public var onTimeShare: Double?
    /// Late Fahrten, oldest first.
    public var rows: [DelayReportRow]

    public var id: Int { index }
}

/// „Nachweis als PDF“: the chosen months, oldest first, with their late Fahrten. No amount of money, no claim – the intro and
/// the caveat (`DelayDiaryText`) say what the list is and what it is not.
public struct DelayReport: Hashable, Sendable {
    public var months: [DelayReportMonth]
    public var threshold: Int
    public var scope: DelayDiaryScope

    public var rows: [DelayReportRow] { months.flatMap(\.rows) }
    public var tripCount: Int { months.reduce(0) { $0 + $1.tripCount } }
    public var recordedCount: Int { months.reduce(0) { $0 + $1.recordedCount } }
    public var lateCount: Int { months.reduce(0) { $0 + $1.lateCount } }
    public var onTimeShare: Double? { DelayDiaryRules.onTimeShare(recorded: recordedCount, late: lateCount) }
    public var isEmpty: Bool { months.isEmpty }
}

public enum DelayReportBuilder {
    /// The report of `selection` (validity month indices; nil = every month of the year). Months are oldest first, the rows of
    /// a month by departure (the same moment: by route, then id). Months not in the year are ignored.
    public static func make(_ year: DelayDiaryYear, months selection: Set<Int>? = nil) -> DelayReport {
        let months = year.months
            .filter { selection?.contains($0.index) ?? true }
            .sorted { $0.index < $1.index }
            .map { month in
                DelayReportMonth(index: month.index, start: month.start, end: month.end, tripCount: month.tripCount,
                                 recordedCount: month.recordedCount, lateCount: month.lateCount, onTimeShare: month.onTimeShare,
                                 rows: month.lateEntries.compactMap(row))
            }
        return DelayReport(months: months, threshold: year.threshold, scope: year.options.scope)
    }

    /// What the export sheet ticks at first: the months with a late Fahrt, or every month with a recorded one when none was late.
    public static func defaultSelection(_ year: DelayDiaryYear) -> Set<Int> {
        let late = Set(year.months.filter { $0.lateCount > 0 }.map(\.index))
        return late.isEmpty ? Set(year.months.filter { $0.recordedCount > 0 }.map(\.index)) : late
    }

    static func row(_ entry: DelayDiaryEntry) -> DelayReportRow? {
        guard let minutes = entry.minutes, let source = entry.source else { return nil }
        return DelayReportRow(id: entry.id, date: entry.date, fromName: entry.fromName, toName: entry.toName,
                              isRoundTrip: entry.isRoundTrip, legCount: entry.legCount, train: entry.lines, minutes: minutes,
                              source: source)
    }
}
