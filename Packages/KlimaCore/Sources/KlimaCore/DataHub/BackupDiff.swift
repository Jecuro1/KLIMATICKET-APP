import Foundation

// MARK: data – „Das ändert sich“ before a restore (docs/DATA_HUB.md §5). The restore merges: a row of the file wins only when it is
// newer than the row on the iPhone (`updated_at`), unknown rows are added, nothing is deleted that the file does not delete itself.
// This counts exactly what that merge will do, per table, before anything is touched.

/// The four tables of a backup, in the order the app names them.
public enum BackupTable: String, CaseIterable, Codable, Sendable {
    case trips, tickets, favorites, benefits

    public var singular: String {
        switch self {
        case .trips: "Fahrt"
        case .tickets: "Ticket"
        case .favorites: "Favorit"
        case .benefits: "Vorteil"
        }
    }

    public var plural: String {
        switch self {
        case .trips: "Fahrten"
        case .tickets: "Tickets"
        case .favorites: "Favoriten"
        case .benefits: "Vorteile"
        }
    }

    public func count(_ n: Int) -> String { "\(n) \(n == 1 ? singular : plural)" }
}

/// What the merge needs to know about one row.
public struct BackupRowStamp: Hashable, Sendable {
    public var id: UUID
    public var updatedAt: Date
    public var isDeleted: Bool
    /// The journey a trip leg belongs to (`journey_id`): the preview counts Fahrten like the app, a journey of several legs once
    /// (docs/JOURNEYS.md). nil for a row of its own.
    public var group: String?

    public init(id: UUID, updatedAt: Date, isDeleted: Bool, group: String? = nil) {
        self.id = id
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.group = group
    }
}

public struct BackupTableDiff: Hashable, Sendable, Identifiable {
    public var table: BackupTable
    /// Rows the iPhone does not have yet.
    public var added = 0
    /// Rows the file has newer than the iPhone (both visible).
    public var changed = 0
    /// Rows the file deleted after the iPhone last changed them – they disappear.
    public var removed = 0
    /// Rows the file deleted that are gone here too, or that the iPhone never had: the merge stores the deletion, nothing shows.
    public var deletedInFile = 0
    /// Same state on both sides.
    public var unchanged = 0
    /// Rows the iPhone has newer than the file – the iPhone's version stays.
    public var newerHere = 0
    /// Rows deleted here after the file was written: the file's older copy does not bring them back.
    public var deletedHere = 0

    public var id: BackupTable { table }
    /// Visible changes.
    public var changes: Int { added + changed + removed }

    /// „Fahrten: 12 neu · 3 geändert · 140 unverändert“ – only the parts that are not zero (all zero: „nichts dabei“).
    public var line: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) neu") }
        if changed > 0 { parts.append("\(changed) geändert") }
        if removed > 0 { parts.append("\(removed) entfernt") }
        if unchanged > 0 { parts.append("\(unchanged) unverändert") }
        if newerHere > 0 { parts.append("\(newerHere) hier neuer") }
        if deletedHere > 0 { parts.append("\(deletedHere) hier gelöscht") }
        return parts.isEmpty ? "nichts dabei" : parts.joined(separator: " · ")
    }
}

public struct BackupDiff: Hashable, Sendable {
    public var tables: [BackupTableDiff]

    public func table(_ table: BackupTable) -> BackupTableDiff {
        tables.first { $0.table == table } ?? BackupTableDiff(table: table)
    }

    public var changes: Int { tables.reduce(0) { $0 + $1.changes } }
    public var newerHere: Int { tables.reduce(0) { $0 + $1.newerHere } }
    public var deletedHere: Int { tables.reduce(0) { $0 + $1.deletedHere } }

    /// One rule per row, the merge's rule: unknown → added (or a stored deletion), file newer → changed / removed, equal →
    /// unchanged, iPhone newer → stays. A row that appears twice in the file counts once, with its newest state. The legs of one
    /// journey (`group`) count once, like „Fahrten“ everywhere in the app: all new → new, all removed → removed, any other visible
    /// change → changed (also a leg added to or taken from a journey that stays), else unchanged or newer here.
    public static func make(file: [BackupTable: [BackupRowStamp]], current: [BackupTable: [BackupRowStamp]]) -> BackupDiff {
        BackupDiff(tables: BackupTable.allCases.map { table in
            var local: [UUID: BackupRowStamp] = [:]
            for row in current[table] ?? [] where local[row.id] == nil { local[row.id] = row }
            var localVisibleLegs: [String: Int] = [:]
            for row in local.values where !row.isDeleted {
                if let key = groupKey(row.group) { localVisibleLegs[key, default: 0] += 1 }
            }
            var incoming: [UUID: BackupRowStamp] = [:]
            var order: [UUID] = []
            for row in file[table] ?? [] {
                if let seen = incoming[row.id] {
                    if row.updatedAt > seen.updatedAt { incoming[row.id] = row }
                } else {
                    incoming[row.id] = row
                    order.append(row.id)
                }
            }
            var groupOrder: [String] = []
            var outcomes: [String: [RowOutcome]] = [:]
            for id in order {
                guard let row = incoming[id] else { continue }
                let key = groupKey(row.group) ?? groupKey(local[id]?.group) ?? "row:" + id.uuidString
                if outcomes[key] == nil { groupOrder.append(key) }
                outcomes[key, default: []].append(outcome(row, here: local[id]))
            }
            var diff = BackupTableDiff(table: table)
            for key in groupOrder {
                let legs = outcomes[key] ?? []
                switch combine(legs, localVisibleLegs: localVisibleLegs[key] ?? 0) {
                case .added: diff.added += 1
                case .changed: diff.changed += 1
                case .removed: diff.removed += 1
                case .deletedInFile: diff.deletedInFile += 1
                case .unchanged: diff.unchanged += 1
                case .newerHere: diff.newerHere += 1
                case .deletedHere: diff.deletedHere += 1
                case .none: break
                }
            }
            return diff
        })
    }

    /// What the merge does with one row.
    enum RowOutcome: Equatable {
        case added, changed, removed, deletedInFile, unchanged, newerHere, deletedHere
        /// Deleted on both sides at the same time, or deleted here after a deletion in the file: nothing to tell.
        case none
    }

    static func outcome(_ row: BackupRowStamp, here: BackupRowStamp?) -> RowOutcome {
        guard let here else { return row.isDeleted ? .deletedInFile : .added }
        if row.updatedAt > here.updatedAt {
            switch (here.isDeleted, row.isDeleted) {
            case (false, true): return .removed
            case (true, true): return .deletedInFile
            case (true, false): return .added      // deleted here, alive in the newer file: it comes back
            case (false, false): return .changed
            }
        } else if sameSecond(row.updatedAt, here.updatedAt) {
            // A file stores whole seconds (ISO 8601): the iPhone's 12:00:05.7 and the file's 12:00:05 are the same version.
            return !row.isDeleted || !here.isDeleted ? .unchanged : .none
        } else if here.isDeleted && !row.isDeleted {
            return .deletedHere
        } else if !here.isDeleted {
            return .newerHere
        }
        return .none
    }

    /// One journey from the outcomes of its legs in the file. `localVisibleLegs`: its legs visible on the iPhone now.
    static func combine(_ legs: [RowOutcome], localVisibleLegs: Int) -> RowOutcome {
        let visible = legs.filter { $0 != .deletedInFile && $0 != .none }
        guard !visible.isEmpty else { return legs.contains(.deletedInFile) ? .deletedInFile : .none }
        let here = legs.filter { [.changed, .removed, .unchanged, .newerHere].contains($0) }.count
        if visible.allSatisfy({ $0 == .added }) {
            return localVisibleLegs > 0 ? .changed : .added      // a leg joins a journey the iPhone shows
        }
        if visible.allSatisfy({ $0 == .removed }) {
            return localVisibleLegs > here ? .changed : .removed  // legs only on the iPhone keep the journey
        }
        if visible.contains(where: { $0 == .added || $0 == .changed || $0 == .removed }) { return .changed }
        if visible.allSatisfy({ $0 == .deletedHere }) { return .deletedHere }
        if visible.contains(where: { $0 == .newerHere || $0 == .deletedHere }) { return .newerHere }
        return .unchanged
    }

    static func groupKey(_ group: String?) -> String? {
        guard let group, !group.isEmpty else { return nil }
        return "journey:" + group.lowercased()
    }

    static func sameSecond(_ a: Date, _ b: Date) -> Bool {
        a.timeIntervalSince1970.rounded(.down) == b.timeIntervalSince1970.rounded(.down)
    }

    /// „Das ändert sich: 12 neue Fahrten, 3 geänderte, 140 unverändert“ plus the other tables and what stays.
    public var headline: String {
        guard changes > 0 else {
            return "Nichts ändert sich: Dein iPhone hat schon alles aus dieser Sicherung – oder eine neuere Fassung davon."
        }
        let trips = table(.trips)
        var parts = tripParts()
        if trips.changes > 0 && trips.unchanged > 0 { parts.append("\(trips.unchanged) unverändert") }
        let others = otherChanges
        var text = "Das ändert sich: "
        if parts.isEmpty {
            text += others.joined(separator: ", ")
        } else {
            text += parts.joined(separator: ", ")
            if !others.isEmpty { text += "; dazu " + others.joined(separator: ", ") }
        }
        return text + "."
    }

    /// The toast after the merge: „12 neue Fahrten, 3 geänderte · 1 Ticket“ – what the preview promised, a journey once. nil when no
    /// row changed (only settings).
    public var appliedLine: String? {
        guard changes > 0 else { return nil }
        let trips = tripParts()
        return ([trips.joined(separator: ", ")].filter { !$0.isEmpty } + otherChanges).joined(separator: " · ")
    }

    /// The trips' visible changes; the first part carries the noun („3 geänderte Fahrten“, „12 neue Fahrten, 3 geänderte“).
    private func tripParts() -> [String] {
        let trips = table(.trips)
        var parts: [String] = []
        for (count, adjective) in [(trips.added, "neue"), (trips.changed, "geänderte"), (trips.removed, "entfernte")] where count > 0 {
            parts.append(parts.isEmpty ? "\(count) \(adjective) \(count == 1 ? "Fahrt" : "Fahrten")" : "\(count) \(adjective)")
        }
        return parts
    }

    /// „1 Ticket“, „2 Favoriten“ – the other tables with changes.
    private var otherChanges: [String] {
        BackupTable.allCases.filter { $0 != .trips }.map(table).filter { $0.changes > 0 }.map { $0.table.count($0.changes) }
    }

    /// „2 Einträge sind auf diesem iPhone neuer und bleiben, wie sie sind.“ and „1 Eintrag, den du hier gelöscht hast, bleibt
    /// gelöscht.“ – nil when there are none. The merge never undoes a newer change, a deletion included.
    public var keepsLine: String? {
        var sentences: [String] = []
        if newerHere > 0 {
            sentences.append(newerHere == 1 ? "1 Eintrag ist auf diesem iPhone neuer und bleibt, wie er ist."
                             : "\(newerHere) Einträge sind auf diesem iPhone neuer und bleiben, wie sie sind.")
        }
        if deletedHere > 0 {
            sentences.append(deletedHere == 1 ? "1 Eintrag, den du hier nach dieser Sicherung gelöscht hast, bleibt gelöscht."
                             : "\(deletedHere) Einträge, die du hier nach dieser Sicherung gelöscht hast, bleiben gelöscht.")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// The merge rule in one sentence (under the preview).
    public static let rule = "Wiederherstellen ergänzt nur: Neuere Einträge gewinnen, nichts wird doppelt, und was nur auf diesem iPhone ist, bleibt."
}
