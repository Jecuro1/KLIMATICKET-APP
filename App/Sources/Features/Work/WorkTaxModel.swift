import Foundation
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
        let summary = Analytics.make(ticket: ticket, trips: entities, catalog: catalog).summary

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

/// Prepared export files (temporary directory) for the share sheet.
struct WorkTaxExports: Equatable {
    var businessPDF: URL?
    var businessCSV: URL?
    var logbookPDF: URL?
    var logbookCSV: URL?

    @MainActor
    static func make(_ data: WorkTaxData, countsCommute: Bool) -> WorkTaxExports {
        let year = WorkFormat.fileYear(data.period)
        let holder = data.ticket.holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        var exports = WorkTaxExports()
        if !data.business.trips.isEmpty {
            let csv = WorkTaxExport.businessTripsCSV(data.business, holder: holder, ticketName: data.ticket.name)
            exports.businessCSV = try? Backup.temporaryFile(named: "KlimaBilanz-Dienstreisen-\(year).csv", data: Data(csv.utf8))
            exports.businessPDF = WorkPDF.write(WorkPDF.businessDocument(data), named: "KlimaBilanz-Dienstreise-Nachweis-\(year).pdf")
        }
        if !data.trips.isEmpty {
            let csv = WorkTaxExport.logbookCSV(trips: data.trips, summary: data.selfEmployed, countsCommute: countsCommute,
                                               holder: holder, ticketName: data.ticket.name)
            exports.logbookCSV = try? Backup.temporaryFile(named: "KlimaBilanz-Oeffi-Fahrtenbuch-\(year).csv", data: Data(csv.utf8))
            exports.logbookPDF = WorkPDF.write(WorkPDF.logbookDocument(data, countsCommute: countsCommute),
                                               named: "KlimaBilanz-Oeffi-Fahrtenbuch-\(year).pdf")
        }
        return exports
    }
}
