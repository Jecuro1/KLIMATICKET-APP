import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

// MARK: data – „Exportieren“ (docs/DATA_HUB.md §2): every format is a lazy share item. Nothing is built while the page opens or
// scrolls; a file is written only when a share target asks for it, from a background context in a detached task. The preview line
// („123 Fahrten · 18 KB“) is computed once per range, off the main thread.

enum DataHubExportFormat: String, CaseIterable, Identifiable, Sendable {
    case backup, tripsCSV, monthlyCSV, tripsCalendar, deadlinesCalendar, yearText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backup: "Komplettsicherung"
        case .tripsCSV: "Fahrten als Tabelle"
        case .monthlyCSV: "Monatsübersicht"
        case .tripsCalendar: "Fahrten im Kalender"
        case .deadlinesCalendar: "Ticket-Fristen im Kalender"
        case .yearText: "Jahresbilanz als Text"
        }
    }

    var line: String {
        switch self {
        case .backup: "Alles mit Einstellungen, zum Wiederherstellen · JSON"
        case .tripsCSV: "Jede Fahrt eine Zeile, für Excel und Numbers · CSV"
        case .monthlyCSV: "Fahrten, Wert, km und CO₂ pro Monat · CSV"
        case .tripsCalendar: "Für Kalender-Apps · ICS"
        case .deadlinesCalendar: "Ticketende und Widerspruchsfrist ab heute · ICS"
        case .yearText: "Zum Teilen per Mail oder in Notizen · Text"
        }
    }

    var symbol: String {
        switch self {
        case .backup: "externaldrive.fill.badge.checkmark"
        case .tripsCSV: "tablecells.fill"
        case .monthlyCSV: "chart.bar.doc.horizontal.fill"
        case .tripsCalendar: "calendar"
        case .deadlinesCalendar: "calendar.badge.exclamationmark"
        case .yearText: "text.alignleft"
        }
    }

    /// The backup always holds everything (a restore needs every row); the other formats follow the range.
    var followsRange: Bool { self != .backup && self != .deadlinesCalendar }

    var fileExtension: String {
        switch self {
        case .backup: "json"
        case .tripsCSV, .monthlyCSV: "csv"
        case .tripsCalendar, .deadlinesCalendar: "ics"
        case .yearText: "md"
        }
    }
}

/// Everything a format needs, read from a background context. `Sendable`: it crosses into the detached tasks.
struct DataHubExportSource: Sendable {
    let container: ModelContainer
    let range: DataHubRange
    let selectedTicketID: UUID?
    let emissions: EmissionFactors
    /// CI scenes: a fixed clock.
    var now: Date = Date()

    struct Snapshot {
        var trips: [TripRecord]
        var notes: [UUID: String]
        var durations: [UUID: Int]
        var ticket: TicketPeriod?
        var deadlines: [DataHubDeadline]
        var interval: DateInterval?
    }

    func snapshot(context: ModelContext) throws -> Snapshot {
        let entities = try context.fetch(FetchDescriptor<TripEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        var notes: [UUID: String] = [:]
        var durations: [UUID: Int] = [:]
        for trip in entities {
            if !trip.note.isEmpty { notes[trip.id] = trip.note }
            if trip.durationMinutes > 0 { durations[trip.id] = trip.durationMinutes }
        }
        let tickets = try context.fetch(FetchDescriptor<TicketEntity>(predicate: #Predicate { $0.deletedAt == nil }))
        let active = Analytics.activeTicket(in: tickets, selectedID: selectedTicketID)
        let interval = range.interval(ticket: active?.period, now: now)
        return Snapshot(trips: DataHubRange.filter(entities.map(\.record), interval: interval), notes: notes, durations: durations,
                        ticket: active?.period, deadlines: Self.deadlines(tickets, now: now), interval: interval)
    }

    /// The end of every ticket that has not ended yet, and the objection deadline you entered from a renewal letter.
    static func deadlines(_ tickets: [TicketEntity], now: Date) -> [DataHubDeadline] {
        let today = Calendar.vienna.startOfDay(for: now)
        var result: [DataHubDeadline] = []
        for ticket in tickets {
            if ticket.endDate >= today {
                result.append(DataHubDeadline(id: "ticket-end-\(ticket.id.uuidString.lowercased())", day: ticket.endDate,
                                              title: "\(ticket.name) endet",
                                              note: "Letzter gültiger Tag laut deinem Ticket in KlimaBilanz."
                                                + (ticket.autoRenews ? " Es verlängert sich automatisch, wenn du nicht widersprichst." : "")))
            }
            if let deadline = LetterStore.deadline(for: ticket.id), deadline >= today {
                result.append(DataHubDeadline(id: "objection-\(ticket.id.uuidString.lowercased())", day: deadline,
                                              title: "Widerspruchsfrist für \(ticket.name) endet",
                                              note: "Laut deinem Verlängerungsbrief. Schick den Widerspruch eingeschrieben ab und heb den Beleg auf."))
            }
        }
        return result
    }

    /// The file's content.
    func content(_ format: DataHubExportFormat) throws -> Data {
        let context = ModelContext(container)
        if format == .backup { return try Backup.export(context: context) }
        let snap = try snapshot(context: context)
        switch format {
        case .backup:
            return Data()
        case .tripsCSV:
            return Data(TripCSVExport.trips(snap.trips, notes: snap.notes).utf8)
        case .monthlyCSV:
            let rows = DataHubMonthlyCSV.rows(snap.trips, interval: snap.interval, emissions: emissions)
            return Data(DataHubMonthlyCSV.csv(rows, totalTrips: JourneySummary.tripCount(snap.trips)).utf8)
        case .tripsCalendar:
            return Data(DataHubICS.trips(snap.trips, durations: snap.durations, stamp: now).utf8)
        case .deadlinesCalendar:
            return Data(DataHubICS.deadlines(snap.deadlines, stamp: now).utf8)
        case .yearText:
            return Data(DataHubYearText.markdown(trips: snap.trips, range: range, ticket: snap.ticket, now: now, emissions: emissions).utf8)
        }
    }

    /// „KlimaBilanz-2026-11-19-Monate-Ticketjahr-2026-27.csv“.
    func fileName(_ format: DataHubExportFormat, ticket: TicketPeriod?) -> String {
        let base = Backup.timestampedName
        let tag = range.fileTag(ticket: ticket, now: now)
        switch format {
        case .backup: return "\(base)-Backup.json"
        case .tripsCSV: return "\(base)-Fahrten-\(tag).csv"
        case .monthlyCSV: return "\(base)-Monate-\(tag).csv"
        case .tripsCalendar: return "\(base)-Fahrten-\(tag).ics"
        case .deadlinesCalendar: return "\(base)-Fristen.ics"
        case .yearText: return "\(base)-Jahresbilanz-\(tag).md"
        }
    }

    func writeFile(_ format: DataHubExportFormat) throws -> URL {
        let data = try content(format)
        let ticket = format.followsRange ? try snapshot(context: ModelContext(container)).ticket : nil
        return try Backup.temporaryFile(named: fileName(format, ticket: ticket), data: data)
    }

    /// The preview line per format: what is in it and how big the file is.
    func previews() -> [DataHubExportFormat: String] {
        let context = ModelContext(container)
        guard let snap = try? snapshot(context: context) else { return [:] }
        var lines: [DataHubExportFormat: String] = [:]
        for format in DataHubExportFormat.allCases {
            guard let size = try? content(format).count else { continue }
            let what: String
            switch format {
            case .backup: what = Backup.counts(context: context).line
            case .tripsCSV, .tripsCalendar: what = DataHubFormat.count(snap.trips.count, "Eintrag", "Einträge")
            case .monthlyCSV: what = DataHubFormat.count(DataHubMonthlyCSV.rows(snap.trips, interval: snap.interval).count, "Monat", "Monate")
            case .deadlinesCalendar: what = DataHubFormat.count(snap.deadlines.count, "Frist", "Fristen")
            case .yearText: what = DataHubFormat.count(JourneySummary.tripCount(snap.trips), "Fahrt", "Fahrten")
            }
            lines[format] = "\(what) · \(DataHubFormat.bytes(size))"
        }
        return lines
    }

    /// How many entries a format has (an empty one is shown, but cannot be shared).
    func isEmpty(_ format: DataHubExportFormat, previews: [DataHubExportFormat: String]) -> Bool {
        guard let line = previews[format] else { return false }
        return line.hasPrefix("0 ")
    }
}

// MARK: - Share items (one type per content type: a share target picks by type)

struct DataHubJSONItem: Transferable {
    let source: DataHubExportSource
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            SentTransferredFile(try await Task.detached(priority: .userInitiated) { try item.source.writeFile(.backup) }.value)
        }
    }
}

struct DataHubCSVItem: Transferable {
    let source: DataHubExportSource
    let format: DataHubExportFormat
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            SentTransferredFile(try await Task.detached(priority: .userInitiated) { try item.source.writeFile(item.format) }.value)
        }
    }
}

struct DataHubCalendarItem: Transferable {
    let source: DataHubExportSource
    let format: DataHubExportFormat
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .calendarEvent) { item in
            SentTransferredFile(try await Task.detached(priority: .userInitiated) { try item.source.writeFile(item.format) }.value)
        }
    }
}

/// The Jahresbilanz: as text for Mail and Notizen (they insert it), as a `.md` file for Dateien.
struct DataHubTextItem: Transferable {
    let source: DataHubExportSource
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .utf8PlainText) { item in
            try await Task.detached(priority: .userInitiated) { try item.source.content(.yearText) }.value
        }
        .suggestedFileName("KlimaBilanz-Jahresbilanz.md")
    }
}
