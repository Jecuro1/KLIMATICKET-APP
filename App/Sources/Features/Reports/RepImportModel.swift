import Foundation
import SwiftData
import KlimaCore

/// One CSV row after station matching, fare estimation and the duplicate check – what the preview shows and the import writes.
struct RepImportCandidate: Identifiable, Hashable {
    enum Status: Hashable { case ready, duplicate, invalid }

    let line: Int
    var date: Date?
    var fromName: String
    var toName: String
    var fromStationID: String?
    var toStationID: String?
    var mode: TransportMode
    var isRoundTrip: Bool
    /// One direction, EUR.
    var fare: Double
    /// One direction, km.
    var distanceKm: Double
    var isFareEstimated: Bool
    var category: TripCategory?
    var note: String
    var isInduced: Bool
    var states: [String]
    var errors: [String]
    var warnings: [String]
    var duplicateNote: String?
    var status: Status

    var id: Int { line }
    var totalValue: Double { fare * (isRoundTrip ? 2 : 1) }
    var totalDistanceKm: Double { distanceKm * (isRoundTrip ? 2 : 1) }
    var isMatched: Bool { fromStationID != nil && toStationID != nil }
}

/// What happened during an import (result step).
struct RepImportSummary: Equatable {
    var imported: Int
    var value: Double
    var duplicatesSkipped: Int
    var invalidSkipped: Int
    var estimated: Int
    var outsideTicket: Int
    var before: Double?
    var after: Double?
    var ticketYear: String?
}

/// State + logic of the CSV import flow (Datei → Spalten → Vorschau → Fertig). UI-agnostic: `RepImportFlow` binds to it.
@Observable
@MainActor
final class RepImportModel {
    enum Step: Int, CaseIterable, Comparable {
        case pick, mapping, preview, result
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .pick: "Datei wählen"
            case .mapping: "Spalten zuordnen"
            case .preview: "Vorschau prüfen"
            case .result: "Fertig"
            }
        }
    }

    enum PreviewFilter: String, CaseIterable, Identifiable {
        case all, ready, problems
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .ready: "Bereit"
            case .problems: "Probleme"
            }
        }
    }

    struct LoadedFile: Equatable {
        var name: String
        var text: String
        var encoding: CSVImport.TextEncoding
        var byteCount: Int
    }

    let app: AppState

    var step: Step = .pick
    private(set) var file: LoadedFile?
    private(set) var loadError: String?

    // Mapping
    private(set) var detectedDelimiter: CSVImport.Delimiter = .semicolon
    /// nil = automatic.
    private(set) var delimiterOverride: CSVImport.Delimiter?
    private(set) var records: [[String]] = []
    private(set) var hasHeader = true
    private(set) var fields: [CSVImport.Field?] = []
    private(set) var format: CSVImport.SourceFormat = .generic
    /// Bumped on every mapping change (haptics).
    private(set) var mappingRevision = 0

    // Preview
    private(set) var candidates: [RepImportCandidate] = []
    var skipDuplicates = true
    var filter: PreviewFilter = .all

    // Result
    private(set) var importedTrips: [TripEntity] = []
    private(set) var summary: RepImportSummary?
    private(set) var isUndone = false
    private(set) var importRevision = 0
    private(set) var undoRevision = 0

    @ObservationIgnored private var stationCache: [String: Station?] = [:]

    init(app: AppState) {
        self.app = app
    }

    // MARK: Loading

    /// Reads a file picked with `.fileImporter` (security-scoped URL).
    func load(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            load(data: data, name: url.lastPathComponent)
        } catch {
            loadError = "Die Datei „\(url.lastPathComponent)“ lässt sich nicht öffnen. Liegt sie vielleicht nur in der Cloud? Lade sie zuerst in der Dateien-App herunter."
        }
    }

    func load(data: Data, name: String) {
        loadError = nil
        guard !data.isEmpty else {
            loadError = "„\(name)“ ist leer."
            return
        }
        guard data.count <= 20_000_000 else {
            loadError = "„\(name)“ ist mit \(Format.number(Double(data.count) / 1_000_000, decimals: 1)) MB zu groß für einen Fahrten-Import."
            return
        }
        let decoded = CSVImport.decode(data)
        let text = decoded.text
        if text.contains("\u{0}") || text.hasPrefix("%PDF") || text.hasPrefix("PK") {
            loadError = "„\(name)“ ist keine Text-Datei. Exportiere deine Tabelle als CSV (Trennzeichen getrennt) und versuch es noch einmal."
            return
        }
        file = LoadedFile(name: name, text: text, encoding: decoded.encoding, byteCount: data.count)
        detectedDelimiter = CSVImport.sniffDelimiter(text)
        delimiterOverride = nil
        reparse(guessHeader: true)
        guard !records.isEmpty else {
            loadError = "In „\(name)“ stehen keine Zeilen."
            file = nil
            return
        }
        step = .mapping
    }

    var delimiter: CSVImport.Delimiter { delimiterOverride ?? detectedDelimiter }

    func setDelimiter(_ value: CSVImport.Delimiter?) {
        delimiterOverride = value
        reparse(guessHeader: true)
        mappingRevision += 1
    }

    func setHeader(_ value: Bool) {
        guard value != hasHeader else { return }
        let guess = CSVImport.guessMapping(rows: records, hasHeader: value)
        hasHeader = value
        fields = guess.fields
        format = guess.format
        mappingRevision += 1
    }

    private func reparse(guessHeader: Bool) {
        guard let file else { return }
        records = CSVImport.parse(file.text, delimiter: delimiter)
        let guess = CSVImport.guessMapping(rows: records, hasHeader: guessHeader ? nil : hasHeader)
        hasHeader = guess.hasHeader
        fields = guess.fields
        format = guess.format
    }

    // MARK: Mapping

    var columnCount: Int { fields.count }
    var dataRowCount: Int { max(0, records.count - (hasHeader ? 1 : 0)) }

    func headerTitle(column: Int) -> String {
        if hasHeader, let header = records.first, column < header.count {
            let title = header[column].trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return "Spalte \(column + 1)"
    }

    /// First non-empty values of a column ("12.03.2026", "13.03.2026", …).
    func samples(column: Int, limit: Int = 3) -> [String] {
        records.dropFirst(hasHeader ? 1 : 0)
            .compactMap { column < $0.count ? $0[column].trimmingCharacters(in: .whitespacesAndNewlines) : nil }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .map { $0.count > 28 ? String($0.prefix(26)) + "…" : $0 }
    }

    func field(for column: Int) -> CSVImport.Field? { column < fields.count ? fields[column] : nil }

    /// Assigns a meaning to a column; a field can belong to one column only (the previous owner is cleared).
    func setField(_ field: CSVImport.Field?, for column: Int) {
        guard column < fields.count else { return }
        if let field, let previous = fields.firstIndex(of: field), previous != column { fields[previous] = nil }
        fields[column] = field
        mappingRevision += 1
    }

    var hasDate: Bool { fields.contains(.date) }
    var hasRoute: Bool { (fields.contains(.from) && fields.contains(.to)) || fields.contains(.route) }
    var hasPrice: Bool { fields.contains(.price) || fields.contains(.totalValue) }
    var canPreview: Bool { hasDate && hasRoute && dataRowCount > 0 }

    // MARK: Preview

    func buildPreview(existing: [TripEntity]) {
        let rows = CSVImport.parseRows(records, fields: fields, hasHeader: hasHeader)
        var existingKeys: [String: Date] = [:]
        for trip in existing where trip.deletedAt == nil {
            existingKeys[CSVImport.duplicateKey(date: trip.date, fromName: trip.fromName, toName: trip.toName, fare: trip.fareEUR)] = trip.date
        }
        var seen: [String: Int] = [:]
        candidates = rows.map { row in
            var c = candidate(for: row)
            if c.errors.isEmpty, let date = c.date {
                let key = CSVImport.duplicateKey(date: date, fromName: c.fromName, toName: c.toName, fare: c.fare)
                if let when = existingKeys[key] {
                    c.duplicateNote = "Schon erfasst am \(Format.dayMonth(when)) – gleiche Strecke, gleicher Preis"
                    c.status = .duplicate
                } else if let first = seen[key] {
                    c.duplicateNote = "Doppelt in der Datei (wie Zeile \(first))"
                    c.status = .duplicate
                } else {
                    seen[key] = row.line
                }
            }
            return c
        }
        filter = .all
        step = .preview
    }

    private func candidate(for row: CSVImport.Row) -> RepImportCandidate {
        var errors = row.errors.map(\.message)
        var warnings = row.warnings.map(\.message)
        let from = matchStation(row.fromName)
        let to = matchStation(row.toName)
        var mode = row.mode ?? .train
        if row.mode == nil, from?.kind == .metro, to?.kind == .metro { mode = .metro }

        var estimate: FareEstimate?
        if let from, let to, from.id != to.id {
            estimate = app.estimator.estimate(from: from, to: to, mode: mode, travelClass: app.settings.defaultTravelClass,
                                              discount: app.settings.defaultDiscount, date: row.date ?? Date())
        }
        var fare = row.fare ?? 0
        var isEstimated = false
        if row.fare == nil {
            if let estimate, estimate.fareEUR > 0 {
                fare = estimate.fareEUR
                isEstimated = true
            } else if row.isValid {
                let unknown = [from == nil ? row.fromName : nil, to == nil ? row.toName : nil].compactMap { $0 }
                if unknown.isEmpty {
                    errors.append("Preis fehlt und lässt sich nicht schätzen")
                } else {
                    errors.append("Preis fehlt – „\(unknown.joined(separator: "“, „"))“ kennen wir nicht, bitte Preis ergänzen")
                }
            }
        } else if let given = row.fare, let estimate, estimate.fareEUR > 0, given > 20, given / estimate.fareEUR > 8,
                  !row.warnings.contains(where: \.isImplausiblePrice) {
            warnings.append("\(Format.euroPrecise(given)) ist viel mehr als der Normalpreis (≈ \(Format.euroPrecise(estimate.fareEUR))) – Komma prüfen?")
        }
        let distance = row.distanceKm ?? estimate?.distanceKm ?? 0
        let states = Array(Set([from?.state, to?.state].compactMap { $0 })).sorted()
        return RepImportCandidate(
            line: row.line, date: row.date,
            fromName: from?.name ?? row.fromName, toName: to?.name ?? row.toName,
            fromStationID: from?.id, toStationID: to?.id,
            mode: mode, isRoundTrip: row.isRoundTrip, fare: fare, distanceKm: distance, isFareEstimated: isEstimated,
            category: row.category, note: row.note, isInduced: row.isInduced, states: states,
            errors: errors, warnings: warnings, duplicateNote: nil, status: errors.isEmpty ? .ready : .invalid)
    }

    /// Bundled station for a free-text name: exact name/alias first, then the best search hit that starts with the typed words
    /// ("Salzburg" → "Salzburg Hbf"). Fuzzy hits are never accepted, so unknown stops keep their own name.
    private func matchStation(_ name: String) -> Station? {
        let key = StationIndex.normalize(name)
        guard !key.isEmpty else { return nil }
        if let cached = stationCache[key] { return cached }
        var result = app.stations.station(named: name)
        if result == nil {
            result = app.stations.search(name, limit: 5).first { station in
                let names = [station.name] + (station.aliases ?? [])
                return names.contains { candidate in
                    let n = StationIndex.normalize(candidate)
                    return n == key || n.hasPrefix(key + " ")
                }
            }
        }
        stationCache[key] = result
        return result
    }

    var readyCandidates: [RepImportCandidate] { candidates.filter { $0.status == .ready } }
    var duplicateCount: Int { candidates.filter { $0.status == .duplicate }.count }
    var invalidCount: Int { candidates.filter { $0.status == .invalid }.count }
    var toImport: [RepImportCandidate] {
        candidates.filter { $0.status == .ready || (!skipDuplicates && $0.status == .duplicate) }
    }
    var importValue: Double { toImport.reduce(0) { $0 + $1.totalValue } }
    var estimatedCount: Int { toImport.filter(\.isFareEstimated).count }
    var warningCount: Int { toImport.filter { !$0.warnings.isEmpty }.count }

    var filteredCandidates: [RepImportCandidate] {
        switch filter {
        case .all: candidates
        case .ready: candidates.filter { $0.status == .ready }
        case .problems: candidates.filter { $0.status != .ready || !$0.warnings.isEmpty }
        }
    }

    // MARK: Import & undo

    func performImport(context: ModelContext) {
        let rows = toImport
        guard !rows.isEmpty else { return }
        let repo = Repository(context: context, app: app)
        let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID)
        let before = ticket.map { Analytics.make(ticket: $0, trips: repo.liveTrips(), catalog: app.catalog).summary.amortizedFraction }

        let travelClass = app.settings.defaultTravelClass
        let trips: [TripEntity] = rows.compactMap { c in
            guard let date = c.date else { return nil }
            let trip = TripEntity(date: date, fromName: c.fromName, toName: c.toName, fromStationID: c.fromStationID,
                                  toStationID: c.toStationID, mode: c.mode, distanceKm: c.distanceKm, fareEUR: c.fare,
                                  isFareManual: !c.isFareEstimated, isRoundTrip: c.isRoundTrip, travelClass: travelClass,
                                  states: c.states, note: c.note)
            trip.category = c.category
            trip.isInduced = c.isInduced
            return trip
        }
        importedTrips = repo.importTrips(trips)

        let after = ticket.map { Analytics.make(ticket: $0, trips: repo.liveTrips(), catalog: app.catalog).summary.amortizedFraction }
        let outside = ticket.map { t in trips.filter { !t.period.contains($0.date) }.count } ?? 0
        summary = RepImportSummary(
            imported: trips.count,
            value: trips.reduce(0) { $0 + $1.totalValue },
            duplicatesSkipped: skipDuplicates ? duplicateCount : 0,
            invalidSkipped: invalidCount,
            estimated: rows.filter(\.isFareEstimated).count,
            outsideTicket: outside,
            before: before, after: after,
            ticketYear: ticket.map { StatsCalc.ticketYearLabel($0.period) })
        isUndone = false
        importRevision += 1
        step = .result
    }

    /// Soft-deletes the whole imported batch (tombstones keep sync consistent).
    func undo(context: ModelContext) {
        guard !importedTrips.isEmpty, !isUndone else { return }
        Repository(context: context, app: app).undoImport(importedTrips)
        isUndone = true
        undoRevision += 1
    }

    // MARK: Navigation

    func back() {
        switch step {
        case .mapping:
            step = .pick
        case .preview:
            step = .mapping
        case .pick, .result:
            break
        }
    }

    func reset() {
        file = nil
        records = []
        fields = []
        candidates = []
        importedTrips = []
        summary = nil
        isUndone = false
        loadError = nil
        step = .pick
    }
}

private extension CSVImport.Issue {
    var isImplausiblePrice: Bool {
        if case .implausiblePrice = self { return true }
        return false
    }
}
