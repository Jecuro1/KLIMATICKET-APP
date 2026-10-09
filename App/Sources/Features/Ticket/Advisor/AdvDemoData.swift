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

        // Purposes only where the demo data has none (the shared demo data may categorise trips itself).
        let trips = (try? context.fetch(FetchDescriptor<TripEntity>())) ?? []
        for trip in trips {
            let purpose: TripCategory
            switch trip.toName {
            case "Innsbruck Hauptbahnhof", "Landeck-Zams":
                purpose = .commute
            case "Wien Hauptbahnhof", "Klagenfurt Hauptbahnhof", "Salzburg Hauptbahnhof":
                purpose = .business
            case "Bludenz", "Hungerburg", "Innsbruck Marktplatz":
                // Weekend outings with the two kids (8 and 11).
                purpose = .leisure
                trip.companions = 2
            default:
                purpose = .leisure
            }
            if trip.category == nil { trip.category = purpose }
        }
        try? context.save()
    }
}
