import SwiftUI
import KlimaCore

// Ticket-Schreiben: the entries in the Ticket-Ratgeber (one line each in AdvisorView, `// MARK: ticketletters`).

// MARK: - Renewal section

/// „Widerspruchsbrief erstellen“ for a KlimaTicket Ö that renews itself per SEPA, and the „Raten-Übersicht“ link for monthly
/// payment. Shown under the renewal reminder; nothing for other tickets (their cards already say what applies).
struct TicketLettersRenewalEntry: View {
    let ticket: TicketEntity
    let advice: TicketAdvice

    @State private var showsObjection = false

    var body: some View {
        let context = TicketLetterContext(ticket)
        let offersLetter = RenewalObjectionLetter.eligibility(for: context.ticket) == .available
        let plan = ticket.isMonthlyPayment && TicketRights.appliesAGB(to: context.ticket)
            ? InstallmentPlan.make(price: context.ticket.price, start: context.ticket.start) : nil
        if offersLetter || plan != nil {
            GlassCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if offersLetter {
                        Button {
                            showsObjection = true
                        } label: {
                            LetterEntryRow(symbol: "envelope.fill", color: Theme.dawn, title: "Widerspruchsbrief erstellen",
                                           subtitle: "Fertiger Brief als PDF – ausdrucken, unterschreiben, eingeschrieben senden.",
                                           trailing: "chevron.right")
                        }
                        .buttonStyle(AdvRowButtonStyle())
                        .accessibilityHint("Öffnet das Formular für deinen Widerspruch gegen die automatische Verlängerung")
                    }
                    if offersLetter, plan != nil {
                        TktHairline().padding(.leading, TktStyle.rowPaddingH + 36 + Theme.Spacing.s)
                    }
                    if let plan {
                        NavigationLink {
                            InstallmentsView(context: context, tripValue: advice.summary.totalValue)
                        } label: {
                            LetterEntryRow(symbol: "calendar.badge.clock", color: Theme.glacier, title: "Raten-Übersicht",
                                           subtitle: "Bezahlt \(Format.euroPrecise(plan.paidAmount)) · \(plan.paidCount) von 12 Raten",
                                           trailing: "chevron.right")
                        }
                        .buttonStyle(AdvRowButtonStyle())
                    }
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .id(AdvAnchor.lettersRenewal)
            .sheet(isPresented: $showsObjection) {
                ObjectionLetterView(context: context)
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Cancellation section

/// „Kündigungsschreiben erstellen“ for a running KlimaTicket Ö. Before the 7th validity month the line says from which date
/// the cancellation without a reason is possible – the sheet then offers only the extraordinary reasons.
struct TicketLettersCancellationEntry: View {
    let ticket: TicketEntity
    let advice: TicketAdvice

    @State private var showsLetter = false

    var body: some View {
        let context = TicketLetterContext(ticket)
        let status = CancellationLetter.status(for: context.ticket)
        if status.canWriteExtraordinary {
            GlassCard(padding: 0) {
                Button {
                    showsLetter = true
                } label: {
                    LetterEntryRow(symbol: "xmark.seal.fill", color: Theme.dusk, title: "Kündigungsschreiben erstellen",
                                   subtitle: subtitle(status), trailing: "chevron.right")
                }
                .buttonStyle(AdvRowButtonStyle())
                .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityHint("Öffnet das Formular für dein Kündigungsschreiben")
            }
            .id(AdvAnchor.lettersCancellation)
            .sheet(isPresented: $showsLetter) {
                CancellationLetterView(context: context)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func subtitle(_ status: CancellationLetter.Status) -> String {
        if status.canWriteOrdinary {
            let fee = status.fee > 0 ? "mit \(Format.euroPrecise(status.fee)) Kündigungsentgelt" : "ohne Kündigungsentgelt"
            return "Ohne Grund \(fee) – oder mit wichtigem Grund ohne Entgelt."
        }
        return "Ohne Grund ab \(Format.date(status.possibleFrom, .long)) · mit wichtigem Grund schon jetzt."
    }
}

// MARK: - Row

/// A row of the entry cards: icon tile, title, one line of explanation, chevron.
struct LetterEntryRow: View {
    var symbol: String
    var color: Color
    var title: String
    var subtitle: String
    var trailing: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            TktIconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV + Theme.Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
