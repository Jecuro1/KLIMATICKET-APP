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

    public init(id: UUID, updatedAt: Date, isDeleted: Bool) {
        self.id = id
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
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
    /// unchanged, iPhone newer → stays. A row that appears twice in the file counts once, with its newest state.
    public static func make(file: [BackupTable: [BackupRowStamp]], current: [BackupTable: [BackupRowStamp]]) -> BackupDiff {
        BackupDiff(tables: BackupTable.allCases.map { table in
            var local: [UUID: BackupRowStamp] = [:]
            for row in current[table] ?? [] where local[row.id] == nil { local[row.id] = row }
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
            var diff = BackupTableDiff(table: table)
            for id in order {
                guard let row = incoming[id] else { continue }
                guard let here = local[id] else {
                    if row.isDeleted { diff.deletedInFile += 1 } else { diff.added += 1 }
                    continue
                }
                if row.updatedAt > here.updatedAt {
                    switch (here.isDeleted, row.isDeleted) {
                    case (false, true): diff.removed += 1
                    case (true, true): diff.deletedInFile += 1
                    case (true, false): diff.added += 1      // deleted here, alive in the newer file: it comes back
                    case (false, false): diff.changed += 1
                    }
                } else if row.updatedAt == here.updatedAt {
                    if !row.isDeleted || !here.isDeleted { diff.unchanged += 1 }
                } else if here.isDeleted && !row.isDeleted {
                    diff.deletedHere += 1
                } else if !here.isDeleted {
                    diff.newerHere += 1
                }
            }
            return diff
        })
    }

    /// „Das ändert sich: 12 neue Fahrten, 3 geänderte, 140 unverändert“ plus the other tables and what stays.
    public var headline: String {
        guard changes > 0 else {
            return "Nichts ändert sich: Dein iPhone hat schon alles aus dieser Sicherung – oder eine neuere Fassung davon."
        }
        let trips = table(.trips)
        var parts: [String] = []
        if trips.added > 0 { parts.append("\(trips.added) \(trips.added == 1 ? "neue Fahrt" : "neue Fahrten")") }
        if trips.changed > 0 { parts.append("\(trips.changed) geänderte") }
        if trips.removed > 0 { parts.append("\(trips.removed) entfernte") }
        if trips.changes > 0 && trips.unchanged > 0 { parts.append("\(trips.unchanged) unverändert") }
        let others = BackupTable.allCases.filter { $0 != .trips }.map(table).filter { $0.changes > 0 }
            .map { $0.table.count($0.changes) }
        var text = "Das ändert sich: "
        if parts.isEmpty {
            text += others.joined(separator: ", ")
        } else {
            text += parts.joined(separator: ", ")
            if !others.isEmpty { text += "; dazu " + others.joined(separator: ", ") }
        }
        return text + "."
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
