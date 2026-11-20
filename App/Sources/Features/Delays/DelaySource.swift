import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md): the app's side of the data – entity → KlimaCore input,
// the holder's diary settings, the memoised year.

/// The diary's entry points (the „Verspätung“ row in a trip, the Statistik card, the link in Fahrgastrechte and
/// klimabilanz://delays). They show only in screenshot runs until the screens are looked at; `false` hides all four again.
enum DelayDiaryRelease {
    static let isLive = false
}

extension TripEntity {
    /// The trip as the diary reads it.
    var delayDiaryTrip: DelayDiaryTrip {
        DelayDiaryTrip(id: id, date: date, fromName: fromName, toName: toName, mode: mode, lineSummary: lineSummary,
                       journeyID: journeyID, legIndex: legIndex, isRoundTrip: isRoundTrip, delayMinutes: delayMinutes,
                       delaySource: TripDelaySource(storedValue: delaySourceRaw))
    }

    /// The recorded arrival (0…240 minutes and its source), nil when „nicht erfasst“.
    var recordedDelay: (minutes: Int, source: TripDelaySource)? {
        guard let source = TripDelaySource(storedValue: delaySourceRaw) else { return nil }
        return (DelayDiaryRules.clamp(delayMinutes), source)
    }
}

/// The holder's diary settings: the personal late mark and which Fahrten count. UserDefaults JSON `delaydiary.options.v1`
/// (a preference, no trip data; not in the backup).
@Observable
@MainActor
final class DelayDiarySettings {
    static let shared = DelayDiarySettings()
    static let key = "delaydiary.options.v1"

    private let defaults: UserDefaults

    var options: DelayDiaryOptions {
        didSet {
            guard options != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(options), forKey: Self.key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Screenshot and demo runs always start from the defaults (no leftovers from an earlier scene).
        options = LaunchMode.isSandboxed ? DelayDiaryOptions() : DelayDiaryOptions.decode(defaults.data(forKey: Self.key))
    }
}

/// The diary of one ticket year, memoised on its inputs: the screen re-renders while a row expands or a number rolls, the
/// Statistik card while the list scrolls – the trips are mapped and grouped once per change of the stored data.
@MainActor
enum DelayDiaryMemo {
    struct Key: Hashable {
        var tripsStamp: Int
        var start: Date
        var end: Date
        var options: DelayDiaryOptions
        /// `now` in quarter hours: only trips up to now count.
        var quarter: Int
    }

    private static var entries: [(key: Key, value: DelayDiaryYear)] = []
    private static let capacity = 4

    static func year(trips: [TripEntity], start: Date, end: Date, now: Date, options: DelayDiaryOptions) -> DelayDiaryYear {
        let key = Key(tripsStamp: TimeBalanceMemo.stamp(trips), start: start, end: end, options: options,
                      quarter: Int(now.timeIntervalSinceReferenceDate / 900))
        if let hit = entries.first(where: { $0.key == key }) { return hit.value }
        let value = DelayDiaryCalculator.compute(trips: trips.filter { $0.deletedAt == nil }.map(\.delayDiaryTrip),
                                                 ticketStart: start, ticketEnd: end, now: now, options: options)
        entries.insert((key, value), at: 0)
        if entries.count > capacity { entries.removeLast() }
        return value
    }

    /// CI screenshots: fixed inputs instead of the stored trips (no memo).
    static func year(fixture: [DelayDiaryTrip], start: Date, end: Date, now: Date, options: DelayDiaryOptions) -> DelayDiaryYear {
        DelayDiaryCalculator.compute(trips: fixture, ticketStart: start, ticketEnd: end, now: now, options: options)
    }
}

/// Dates and labels of the diary in the app's format.
@MainActor
enum DelayDiaryFormat {
    /// „November 2026“ for a month that starts on the 1st, else „15. Nov. – 14. Dez.“.
    static func monthTitle(_ month: DelayMonth) -> String { monthTitle(start: month.start, end: month.end) }

    static func monthTitle(start: Date, end: Date) -> String {
        if Calendar.vienna.component(.day, from: start) == 1 { return Format.monthYear(start) }
        return "\(Format.dayMonth(start)) – \(Format.dayMonth(end))"
    }

    /// „Gültigkeitsmonat 3“ – the AGB's word, under a month's title.
    static func monthKicker(_ month: DelayMonth) -> String { "Gültigkeitsmonat \(month.index + 1)" }

    /// The chart's short label: „Nov“ (the month the validity month starts in).
    static func shortMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(Format.locale)).replacingOccurrences(of: ".", with: "")
    }

    /// „Mo., 9. Nov. · 07:12“
    static func when(_ date: Date) -> String { "\(Format.weekdayDayMonth(date)) · \(Format.time(date))" }

    /// „St. Anton am Arlberg → Innsbruck Hbf“ (with ⇄ for Hin & Retour, like the trip list).
    static func route(_ entry: DelayDiaryEntry) -> String {
        TripListFormat.routeTitle(entry.fromName, entry.toName, roundTrip: entry.isRoundTrip)
    }

    /// „RJX 662“ or the mode's name when no line is known.
    static func train(_ entry: DelayDiaryEntry) -> String {
        if !entry.lines.isEmpty { return entry.lines }
        return entry.modes.map(\.displayName).joined(separator: " · ")
    }
}
