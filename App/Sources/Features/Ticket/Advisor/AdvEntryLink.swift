import SwiftUI
import KlimaCore

/// Entry point on the Ticket tab: „Ticket-Ratgeber“ with a one-line teaser of the renewal verdict; pushes `AdvisorView`.
struct AdvEntryLink: View {
    let ticket: TicketEntity
    let trips: [TripEntity]

    @Environment(AppState.self) private var app

    var body: some View {
        let advice = AdvAdvisor.advice(for: ticket, trips: trips, app: app)
        NavigationLink {
            AdvisorView(ticket: ticket)
        } label: {
            AdvEntryCard(advice: advice)
        }
        .buttonStyle(AdvCardButtonStyle())
        .accessibilityHint("Öffnet den Ticket-Ratgeber")
    }
}

private struct AdvEntryCard: View {
    let advice: TicketAdvice

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: "signpost.right.and.left.fill", color: Theme.dusk, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ticket-Ratgeber")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(teaser)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(topics)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Verlängern lohnt sich · + € 1.130 im Ticketjahr 2027/28".
    private var teaser: String {
        let r = advice.renewal
        guard r.verdict != .tooEarly else { return "Verlängern, kündigen, 1. Klasse – aus deinen Fahrten berechnet" }
        return "\(AdvText.renewalTitle(r)) · \(AdvText.signed(r.projectedNextYearNet)) im Ticketjahr \(r.nextYearLabel)"
    }

    private var topics: String {
        advice.advSections.map(\.title).joined(separator: " · ")
    }
}

/// Subtle press feedback for whole-card links.
struct AdvCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
