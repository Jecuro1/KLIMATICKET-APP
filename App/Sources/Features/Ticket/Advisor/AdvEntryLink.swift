import SwiftUI
import KlimaCore

/// Entry point on the Ticket tab: „Ticket-Ratgeber“ with a one-line teaser of the renewal verdict; pushes `AdvisorView`.
struct AdvEntryLink: View {
    let ticket: TicketEntity
    let trips: [TripEntity]
    /// The Ticket tab's scroll proxy – only used by the `ticketAdvisor` screenshot route to bring the entry into view.
    var scrollProxy: ScrollViewProxy? = nil

    @Environment(AppState.self) private var app

    private static let scrollID = "adv.entry"

    var body: some View {
        let advice = AdvAdvisor.advice(for: ticket, trips: trips, app: app)
        NavigationLink {
            AdvisorView(ticket: ticket)
        } label: {
            AdvEntryCard(advice: advice)
        }
        .buttonStyle(AdvCardButtonStyle())
        .accessibilityHint("Öffnet den Ticket-Ratgeber")
        .id(Self.scrollID)
        .task {
            guard LaunchMode.screenshotScreen == "ticketAdvisor", let scrollProxy else { return }
            try? await Task.sleep(for: .milliseconds(600))
            scrollProxy.scrollTo(Self.scrollID, anchor: .center)
        }
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
}

/// Subtle press feedback for whole-card links.
struct AdvCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
