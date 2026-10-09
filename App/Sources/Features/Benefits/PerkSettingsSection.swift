import SwiftUI
import SwiftData
import KlimaCore

/// Settings entry "Vorteile & Fahrgastrechte" (uses the settings module's row label and header for a consistent look).
struct PerkSettingsSection: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<BenefitEntity> { $0.deletedAt == nil }) private var benefits: [BenefitEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

    var body: some View {
        let period = PerkPeriod.current(tickets: tickets, selectedID: app.settings.selectedTicketID)
        let summary = PerkSummary.make(benefits: benefits, period: period)
        Section {
            NavigationLink {
                PerkBenefitsView()
            } label: {
                SetRowLabel(title: "Vorteile & Fahrgastrechte", subtitle: subtitle(summary), symbol: "gift.fill", tint: Theme.gold)
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Vorteilswelt")
        } footer: {
            SetFooter(text: "Zusatz-Ersparnis durch Partner-Vorteile wird getrennt ausgewiesen und zählt nicht zur Amortisation.")
        }
    }

    private func subtitle(_ summary: PerkSummary) -> String {
        if summary.isEmpty { return "Partner-Rabatte erfassen, Entschädigung sichern" }
        return "\(PerkFormat.plusEuroRounded(summary.total)) Zusatz-Ersparnis · \(PerkFormat.count(summary.count))"
    }
}
