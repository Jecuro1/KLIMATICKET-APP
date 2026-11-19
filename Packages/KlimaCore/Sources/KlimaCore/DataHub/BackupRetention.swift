import Foundation

// MARK: data – which automatic backups stay (docs/DATA_HUB.md §4). Pure: the app lists the folder, asks for a plan and deletes
// what the plan names. Files the app did not name (a copy the person put there) are never part of a plan.

/// The kind of a backup file in Documents/Sicherungen.
public enum BackupKind: String, Codable, CaseIterable, Sendable {
    /// Written by the app once a day when it goes to the background, or by „Jetzt sichern“.
    case daily
    /// Taken before „Alle Daten löschen“ (and the other destructive paths).
    case beforeDelete
    /// Taken before a restore merges a backup into the data.
    case beforeRestore

    /// Safety backups stay at least this long, whatever the daily rhythm says.
    public static let safetyDays = 30

    public var isSafety: Bool { self != .daily }

    public var title: String {
        switch self {
        case .daily: "Sicherung"
        case .beforeDelete: "Vor dem Löschen"
        case .beforeRestore: "Vor dem Wiederherstellen"
        }
    }

    /// File-name suffix – ASCII, so zip tools and cloud drives keep the name as it is.
    var suffix: String? {
        switch self {
        case .daily: nil
        case .beforeDelete: "vor-dem-Loeschen"
        case .beforeRestore: "vor-dem-Wiederherstellen"
        }
    }
}

/// `KlimaBilanz-2026-11-19-1803.json`, `KlimaBilanz-2026-11-19-1432-vor-dem-Loeschen.json` – date and minute in Vienna time, so the
/// Files app sorts them by name. A second file in the same minute gets `~2`.
public enum BackupFileName {
    public static let stem = "KlimaBilanz-"
    public static let fileExtension = "json"

    public static func make(date: Date, kind: BackupKind, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var name = stem + "\(pad(c.year ?? 0, 4))-\(pad(c.month ?? 0, 2))-\(pad(c.day ?? 0, 2))-\(pad(c.hour ?? 0, 2))\(pad(c.minute ?? 0, 2))"
        if let suffix = kind.suffix { name += "-" + suffix }
        return name + "." + fileExtension
    }

    /// A free name: `base`, else `base~2`, `base~3` … (`exists` asks the file system).
    public static func unique(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let base = String(name.dropLast(fileExtension.count + 1))
        var counter = 2
        while exists("\(base)~\(counter).\(fileExtension)") { counter += 1 }
        return "\(base)~\(counter).\(fileExtension)"
    }

    public struct Parsed: Equatable, Sendable {
        public var date: Date
        public var kind: BackupKind
    }

    /// The date and kind of a name the app wrote; nil for any other file.
    public static func parse(_ name: String, calendar: Calendar = .vienna) -> Parsed? {
        guard name.hasPrefix(stem), name.hasSuffix("." + fileExtension) else { return nil }
        var body = String(name.dropFirst(stem.count).dropLast(fileExtension.count + 1))
        if let tilde = body.firstIndex(of: "~") {
            guard Int(body[body.index(after: tilde)...]) != nil else { return nil }
            body = String(body[..<tilde])
        }
        var kind = BackupKind.daily
        for candidate in BackupKind.allCases {
            if let suffix = candidate.suffix, body.hasSuffix("-" + suffix) {
                kind = candidate
                body = String(body.dropLast(suffix.count + 1))
            }
        }
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2, parts[3].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), let hhmm = Int(parts[3]),
              (1...12).contains(month), (1...31).contains(day), hhmm / 100 < 24, hhmm % 100 < 60 else { return nil }
        var components = DateComponents(year: year, month: month, day: day, hour: hhmm / 100, minute: hhmm % 100)
        components.timeZone = calendar.timeZone
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }   // 31 February does not exist
        return Parsed(date: date, kind: kind)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

/// Keep 7 daily, 4 weekly, 3 monthly backups – each rule on its own, newest first: for the last 7 days that have a backup the
/// newest of each day, for the last 4 weeks the newest of each week, for the last 3 months the newest of each month; a file kept
/// by any rule stays (the rules of restic and Time Machine). Safety backups stay 30 days. The newest backup always stays, and a
/// file dated in the future (a clock that was wrong) is never deleted.
public enum BackupRetention {
    public static let dailyCount = 7
    public static let weeklyCount = 4
    public static let monthlyCount = 3

    public struct Entry: Hashable, Sendable {
        public var id: String
        public var date: Date
        public var kind: BackupKind

        public init(id: String, date: Date, kind: BackupKind) {
            self.id = id
            self.date = date
            self.kind = kind
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Newest first.
        public var keep: [String]
        public var delete: [String]
    }

    public static func plan(_ entries: [Entry], now: Date, calendar: Calendar = .vienna) -> Plan {
        let sorted = entries.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        var keep = Set<String>()
        if let newest = sorted.first { keep.insert(newest.id) }
        for entry in sorted where entry.date > now { keep.insert(entry.id) }
        for entry in sorted where entry.kind.isSafety {
            if let limit = calendar.date(byAdding: .day, value: BackupKind.safetyDays, to: entry.date), now < limit {
                keep.insert(entry.id)
            }
        }
        let daily = sorted.filter { $0.kind == .daily }
        var calendar = calendar
        calendar.firstWeekday = 2              // ISO weeks: Monday first, the week of 4 January is week 1
        calendar.minimumDaysInFirstWeek = 4
        keep.formUnion(newestPerBucket(daily, limit: dailyCount) { entry in
            let c = calendar.dateComponents([.year, .month, .day], from: entry.date)
            return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        })
        keep.formUnion(newestPerBucket(daily, limit: weeklyCount) { entry in
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
            return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
        })
        keep.formUnion(newestPerBucket(daily, limit: monthlyCount) { entry in
            let c = calendar.dateComponents([.year, .month], from: entry.date)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        })
        return Plan(keep: sorted.map(\.id).filter(keep.contains), delete: sorted.map(\.id).filter { !keep.contains($0) })
    }

    /// Walks newest first and keeps the first entry of each new bucket until `limit` buckets are taken.
    private static func newestPerBucket(_ sorted: [Entry], limit: Int, bucket: (Entry) -> String) -> Set<String> {
        var seen = Set<String>()
        var kept = Set<String>()
        for entry in sorted {
            let key = bucket(entry)
            guard !seen.contains(key) else { continue }
            guard seen.count < limit else { break }
            seen.insert(key)
            kept.insert(entry.id)
        }
        return kept
    }
}
