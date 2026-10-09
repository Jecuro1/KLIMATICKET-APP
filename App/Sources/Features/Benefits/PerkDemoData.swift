import Foundation
import SwiftData
import KlimaCore

/// Demo benefits for the sample year (screenshots, "Demo ansehen", "Demo-Daten laden"): the Arlberg commuter uses
/// a dozen Vorteilswelt offers (≈ € 86 Zusatz-Ersparnis). In screenshot mode it also pre-fills the Fahrgastrechte
/// checklist and two months marked "unter 93 %" so the assistant shows a realistic state.
@MainActor
enum PerkDemoData {
    private struct Item {
        let daysAgo: Int
        let partnerID: String
        let title: String
        let saved: Double
        let note: String
    }

    private static let items: [Item] = [
        Item(daysAgo: 2, partnerID: "wienmobil-rad", title: "WienMobil Rad", saved: 0.43, note: "Hauptbahnhof → Prater"),
        Item(daysAgo: 6, partnerID: "burgtheater", title: "Burgtheater", saved: 12.00, note: "Der Talisman · 2. Rang"),
        Item(daysAgo: 23, partnerID: "sommer-bergbahnen", title: "Nordkettenbahnen Innsbruck", saved: 4.20, note: "Hafelekar mit Lena & Tom"),
        Item(daysAgo: 47, partnerID: "salzburg-card", title: "Salzburg Card 24 h", saved: 3.50, note: "Tourist Info Hauptbahnhof"),
        Item(daysAgo: 64, partnerID: "sommer-bergbahnen", title: "Galzigbahn St. Anton", saved: 3.40, note: "Sommerbetrieb"),
        Item(daysAgo: 88, partnerID: "nextbike-noe", title: "nextbike Niederösterreich", saved: 1.00, note: "Krems → Dürnstein"),
        Item(daysAgo: 101, partnerID: "rail-drive", title: "Rail & Drive (ÖBB)", saved: 19.90, note: "Fahrtguthaben nach Upload"),
        Item(daysAgo: 132, partnerID: "technisches-museum", title: "Technisches Museum Wien", saved: 3.40, note: ""),
        Item(daysAgo: 149, partnerID: "hotel-daniel-wien", title: "Hotel Daniel Vienna", saved: 24.00, note: "1 Nacht beim Hauptbahnhof"),
        Item(daysAgo: 166, partnerID: "westbahn", title: "WESTbahn Comfort Class", saved: 4.00, note: "Salzburg → Wien, Reservierung inklusive"),
        Item(daysAgo: 190, partnerID: "cat", title: "City Airport Train (CAT)", saved: 7.00, note: "Wien Mitte → Flughafen"),
        Item(daysAgo: 205, partnerID: PerkCatalog.customID, title: "Kletterhalle Innsbruck", saved: 3.00, note: "Öffi-Rabatt an der Kassa"),
    ]

    /// Inserts the demo benefits (dates relative to `now`, inside the demo ticket year) – does not save.
    static func seed(into context: ModelContext, ticket: TicketEntity, now: Date = Date()) {
        let cal = Calendar.vienna
        for item in items {
            let day = cal.date(byAdding: .day, value: -item.daysAgo, to: cal.startOfDay(for: now)) ?? now
            let date = cal.date(bySettingHour: 11, minute: 30, second: 0, of: day) ?? day
            guard date >= ticket.startDate, date <= now else { continue }
            context.insert(BenefitEntity(date: date, partnerID: item.partnerID, title: item.title, savedEUR: item.saved, note: item.note))
        }
        if LaunchMode.isScreenshot {
            PerkRightsStore.setCompletedSteps([0], ticketID: ticket.id)
            PerkRightsStore.setBadMonths([2, 5], ticketID: ticket.id)
        }
    }
}
