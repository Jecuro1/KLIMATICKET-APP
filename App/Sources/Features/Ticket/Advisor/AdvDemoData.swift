import Foundation
import SwiftData
import KlimaCore

/// Extra demo content for the Ratgeber screenshots, layered on top of `DemoData` (Lena, Arlberg commuter):
/// SEPA renewal, kids on the weekend trips, trip purposes, optional employer contribution and add-ons.
@MainActor
enum AdvDemoData {
    static func enrich(context: ModelContext, employerContribution: Double = 0, addOns: [TicketAddOn] = []) {
        guard let ticket = (try? context.fetch(FetchDescriptor<TicketEntity>()))?.first else { return }
        ticket.autoRenews = true
        ticket.employerContribution = employerContribution
        ticket.addOns = addOns.map(\.rawValue)
        ticket.addOnPrice = TicketAddOn.listTotal(Set(addOns), productID: ticket.productID, variant: ticket.variant)

        let trips = (try? context.fetch(FetchDescriptor<TripEntity>())) ?? []
        for trip in trips {
            switch trip.toName {
            case "Innsbruck Hauptbahnhof", "Landeck-Zams":
                trip.category = .commute
            case "Wien Hauptbahnhof", "Klagenfurt Hauptbahnhof", "Salzburg Hauptbahnhof":
                trip.category = .business
            case "Bludenz", "Hungerburg", "Innsbruck Marktplatz":
                // Weekend outings with the two kids (8 and 11).
                trip.category = .leisure
                trip.companions = 2
            default:
                trip.category = .leisure
            }
        }
        try? context.save()
    }
}
