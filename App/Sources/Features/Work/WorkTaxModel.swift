import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

/// Everything the "Arbeit & Steuer" screen shows for one ticket period (rules in KlimaCore.WorkTax).
@MainActor
struct WorkTaxData {
    let ticket: TicketEntity
    let period: TicketPeriod
    /// All trips of the period, valued with the 2nd-class single ticket.
    let trips: [WorkTaxTrip]
    let business: WorkTaxBusinessTrips
    let job: WorkTaxJobticket
    let selfEmployed: WorkTaxSelfEmployed
    let commuteCount: Int
    let commuteValue: Double
    /// Business trips logged in 1st class (valued at the 2nd-class fare).
    let firstClassBusinessTrips: Int
    /// Extras other than the 1st-class upgrade make the add-on price impossible to split.
    let hasMixedExtras: Bool
    let isFamilyTicket: Bool
    let uncategorisedCount: Int

    static func make(ticket: TicketEntity, trips allTrips: [TripEntity], catalog: TariffCatalog, countsCommute: Bool) -> WorkTaxData {
        let period = ticket.period
        let entities = allTrips.filter { $0.deletedAt == nil && period.contains($0.date) }.sorted { $0.date < $1.date }
        let factor = catalog.fareModel.firstClassFactor
        let items = entities.map { trip in
            WorkTaxTrip(record: trip.record,
                        singleFare: WorkTax.secondClassFare(trip.fareEUR, travelClass: trip.travelClass, firstClassFactor: factor),
                        note: trip.note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Only the trip value is needed – the summary alone (not the whole Analytics snapshot with charts and achievements).
        let summary = SavingsCalculator.summary(ticket: period, trips: entities.map(\.record),
                                                kilometergeld: catalog.kilometergeldEUR, emissions: catalog.emissions)

        let addOns = ticket.addOns
        let hasFirstClass = addOns.contains("firstClass")
        let onlyFirstClass = hasFirstClass && addOns.allSatisfy { $0 == "firstClass" }
        let upgrade = onlyFirstClass ? ticket.addOnPrice : 0
        let surcharge = WorkTax.familySurcharge(productID: ticket.productID, start: ticket.startDate, products: catalog.products)

        let commute = items.filter { $0.category == .commute }
        return WorkTaxData(
            ticket: ticket,
            period: period,
            trips: items,
            business: WorkTax.businessTrips(items, cap: ticket.ownShare),
            job: WorkTax.jobticket(price: ticket.price, addOnPrice: ticket.addOnPrice,
                                   employerContribution: ticket.employerContribution, tripValue: summary.totalValue),
            selfEmployed: WorkTax.selfEmployed(ticketPrice: ticket.price, firstClassUpgrade: upgrade, familySurcharge: surcharge,
                                               trips: items, countsCommute: countsCommute),
            commuteCount: commute.count,
            commuteValue: commute.reduce(0) { $0 + $1.totalValue },
            firstClassBusinessTrips: entities.filter { $0.category == .business && $0.travelClass == .first }.count,
            hasMixedExtras: hasFirstClass && !onlyFirstClass,
            isFamilyTicket: ticket.variant == .familie,
            uncategorisedCount: entities.filter { $0.category == nil }.count
        )
    }

    var ticketYear: String { StatsCalc.ticketYearLabel(period) }

    /// Business-use trips for the self-employed logbook.
    func businessUse(countsCommute: Bool) -> [WorkTaxTrip] {
        trips.filter { WorkTax.isBusinessUse($0.category, role: .selfEmployed, countsCommute: countsCommute) }
    }
}

/// The share-sheet exports of one ticket year. Only the documents (rows, totals, CSV text) are prepared up front –
/// the PDF pages are drawn and the files written when the share sheet asks for them. Writing both PDFs ran
/// ImageRenderer on the main actor shortly after the screen opened and after every assigned trip.
struct WorkTaxExports {
    /// Ticket the files were made for (a switched ticket year never shares the previous year's files).
    var ticketID: UUID?
    var businessPDF: WorkPDFExport?
    var businessCSV: WorkCSVExport?
    var logbookPDF: WorkPDFExport?
    var logbookCSV: WorkCSVExport?

    @MainActor
    static func make(_ data: WorkTaxData, countsCommute: Bool) -> WorkTaxExports {
        let year = WorkFormat.fileYear(data.period)
        let holder = data.ticket.holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        var exports = WorkTaxExports(ticketID: data.ticket.id)
        if !data.business.trips.isEmpty {
            let csv = WorkTaxExport.businessTripsCSV(data.business, holder: holder, ticketName: data.ticket.name)
            exports.businessCSV = WorkCSVExport(text: csv, fileName: "KlimaBilanz-Dienstreisen-\(year).csv")
            exports.businessPDF = WorkPDFExport(document: WorkPDF.businessDocument(data),
                                                fileName: "KlimaBilanz-Dienstreise-Nachweis-\(year).pdf")
        }
        if !data.trips.isEmpty {
            let csv = WorkTaxExport.logbookCSV(trips: data.trips, summary: data.selfEmployed, countsCommute: countsCommute,
                                               holder: holder, ticketName: data.ticket.name)
            exports.logbookCSV = WorkCSVExport(text: csv, fileName: "KlimaBilanz-Oeffi-Fahrtenbuch-\(year).csv")
            exports.logbookPDF = WorkPDFExport(document: WorkPDF.logbookDocument(data, countsCommute: countsCommute),
                                               fileName: "KlimaBilanz-Oeffi-Fahrtenbuch-\(year).pdf")
        }
        return exports
    }
}

/// A4 PDF ("Dienstreise-Nachweis", "Öffi-Fahrtenbuch"), drawn into a temporary file on export.
struct WorkPDFExport: Transferable {
    let document: WorkPDFDocument
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try await export.write())
        }
    }

    @MainActor
    func write() throws -> URL {
        guard let url = WorkPDF.write(document, named: fileName) else { throw TktShareError.renderFailed }
        return url
    }
}

/// CSV export (Excel AT), written into a temporary file on export.
struct WorkCSVExport: Transferable {
    let text: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.fileName)
            try Data(export.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
