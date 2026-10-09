import SwiftUI
import SwiftData
import KlimaCore

/// Compact card for the dashboard / ticket screen: "+ € 86 Zusatz-Ersparnis durch Vorteile".
/// Self-contained (reads benefits and tickets itself) and pushes the Vorteilswelt screen – the host only needs
/// to provide a NavigationStack. Without benefits it invites to discover the Vorteilswelt.
struct PerkSummaryCard: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<BenefitEntity> { $0.deletedAt == nil }, sort: \BenefitEntity.date, order: .reverse)
    private var benefits: [BenefitEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]

    var body: some View {
        let period = PerkPeriod.current(tickets: tickets, selectedID: app.settings.selectedTicketID)
        let summary = PerkSummary.make(benefits: benefits, period: period)
        NavigationLink {
            PerkBenefitsView()
        } label: {
            content(summary: summary, period: period)
        }
        .buttonStyle(PerkPressableStyle())
        .accessibilityHint("Öffnet die Vorteilswelt")
    }

    private func content(summary: PerkSummary, period: PerkPeriod) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: summary.isEmpty ? "Vorteilswelt" : "Zusatz-Ersparnis")
                if summary.isEmpty {
                    Text("Mehr aus deinem Ticket holen")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("CAT −50 %, Museen, Sommer-Bergbahnen – erfasse genutzte Vorteile.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    headline(summary)
                    Text("\(PerkFormat.count(summary.count)) · extra zur Ticket-Bilanz")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card)
        .contentShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(summary: summary, period: period))
    }

    private func headline(_ summary: PerkSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(PerkFormat.plusEuroRounded(summary.total))
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: summary.total))
            Text("durch Vorteile")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var icon: some View {
        Image(systemName: "gift.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(LinearGradient(colors: [Theme.gold, Theme.dawn], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 13, style: .continuous))
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }

    private func accessibilityText(summary: PerkSummary, period: PerkPeriod) -> String {
        if summary.isEmpty {
            return "Vorteilswelt: Mehr aus deinem Ticket holen. Erfasse genutzte Partner-Vorteile."
        }
        return "Zusatz-Ersparnis \(period.label): \(Format.euroPrecise(summary.total)) durch \(PerkFormat.count(summary.count)), extra zur Ticket-Bilanz"
    }
}
