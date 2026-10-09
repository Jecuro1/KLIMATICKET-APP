import SwiftUI
import KlimaCore

// Form sections the Ratgeber adds to the ticket edit sheet (`TktEditSheet`): automatic renewal, employer contribution
// and the ÖBB add-ons. Amounts use `AdvisorEuro` (accepts "1.234,50", "800", "1.490,-").

/// Scroll target ids inside `TktEditSheet`.
enum AdvEditAnchor {
    static let renewal = "adv.edit.renewal"
}

/// „Verlängerung & Jobticket“: SEPA auto-renewal toggle and the employer contribution (de-AT decimal input).
struct AdvEditRenewalSection: View {
    @Binding var autoRenews: Bool
    @Binding var employerText: String
    var family: TicketFamily
    /// Ticket price + add-ons as currently entered (for the own-share preview).
    var fullPrice: Double?
    var hapticsEnabled: Bool

    private var parsedContribution: Double? { AdvisorEuro.parse(employerText) }
    private var isInvalid: Bool {
        !employerText.trimmingCharacters(in: .whitespaces).isEmpty && parsedContribution == nil
    }

    var body: some View {
        Section {
            Toggle(isOn: $autoRenews) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatische Verlängerung (SEPA)")
                    Text(autoRenews ? "Verlängert sich, wenn du nicht widersprichst" : "Endet mit Ablauf, wenn du nichts tust")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .id(AdvEditAnchor.renewal)
            .sensoryFeedback(.selection, trigger: autoRenews) { _, _ in hapticsEnabled }
            HStack(spacing: Theme.Spacing.xs) {
                Text("Zuschuss Arbeitgeber")
                Spacer(minLength: Theme.Spacing.s)
                Text("€")
                    .foregroundStyle(Theme.textSecondary)
                TextField("0", text: $employerText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 120)
                    .foregroundStyle(isInvalid ? Theme.negativeText : Theme.textPrimary)
                    .accessibilityLabel("Zuschuss Arbeitgeber in Euro")
            }
        } header: {
            Text("Verlängerung & Jobticket")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if isInvalid { return "Bitte einen Betrag eingeben, z. B. 800 oder 1.234,50." }
        var text: String
        switch family {
        case .oe:
            text = "Mit SEPA-Lastschrift verlängert sich dein KlimaTicket um 12 Monate, wenn du nicht bis zur Frist im Verlängerungsbrief widersprichst – der Brief kommt etwa 2 Monate vor Ablauf."
        case .regional, .custom:
            text = "Mit Abbuchungsauftrag verlängern sich viele Jahrestickets automatisch, wenn du nicht rechtzeitig kündigst."
        }
        if let contribution = parsedContribution, contribution > 0, let fullPrice, fullPrice > 0 {
            let own = max(0, fullPrice - contribution)
            text += " Deine Bilanz rechnet mit deinem Eigenanteil von \(Format.euro(own, decimals: own == own.rounded() ? 0 : 2))."
        } else {
            text += " Zahlt dein Arbeitgeber mit (Jobticket), rechnen wir die Bilanz auf deinen Eigenanteil."
        }
        return text
    }
}

/// „Extras der ÖBB“: multi-select of the add-ons with their list price for the ticket category; the price field follows
/// the selection until it is edited by hand.
struct AdvEditAddOnsSection: View {
    @Binding var addOns: [String]
    @Binding var priceText: String
    var productID: String
    var variant: TicketVariant
    var hapticsEnabled: Bool

    private var selected: Set<TicketAddOn> { TicketAddOn.parse(addOns) }
    private var isInvalid: Bool {
        !priceText.trimmingCharacters(in: .whitespaces).isEmpty && AdvisorEuro.parse(priceText) == nil
    }

    var body: some View {
        Section {
            ForEach(TicketAddOn.allCases) { addOn in
                row(addOn)
            }
            if !selected.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Bezahlt für Extras")
                    Spacer(minLength: Theme.Spacing.s)
                    Text("€")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 120)
                        .foregroundStyle(isInvalid ? Theme.negativeText : Theme.textPrimary)
                        .accessibilityLabel("Bezahlt für Extras in Euro")
                }
                if let reset = listTotalIfDifferent {
                    Button {
                        priceText = AdvisorEuro.editString(reset)
                    } label: {
                        Label("Listenpreis übernehmen · \(Format.euroPrecise(reset))", systemImage: "arrow.uturn.backward")
                            .foregroundStyle(Theme.accentText)
                    }
                }
            }
        } header: {
            Text("Extras der ÖBB")
        } footer: {
            Text(isInvalid ? "Bitte einen Betrag eingeben, z. B. 1.490 oder 1.234,50."
                           : "Vorgeschlagen sind die ÖBB-Listenpreise 2026 für deine Ticketkategorie. Unterjährig oder in Raten gekauft? Trag deinen tatsächlichen Preis ein – er zählt zu deinem Ticketpreis.")
        }
    }

    private func row(_ addOn: TicketAddOn) -> some View {
        let isOn = selected.contains(addOn)
        return Button {
            toggle(addOn)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: addOn.symbolName, color: color(addOn), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(addOn.displayName)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Format.euro(addOn.listPrice(productID: productID, variant: variant))) · \(addOn.detail)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
                    .symbolReplaceTransition()
                    .symbolBounce(on: isOn)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .haptic(.selection, trigger: isOn)
    }

    private func color(_ addOn: TicketAddOn) -> Color {
        switch addOn {
        case .firstClass: Theme.dusk
        case .vorteilsabo: Theme.glacier
        case .business: Theme.gold
        }
    }

    private var listTotal: Double { TicketAddOn.listTotal(selected, productID: productID, variant: variant) }

    private var listTotalIfDifferent: Double? {
        guard let entered = AdvisorEuro.parse(priceText) else { return listTotal > 0 ? listTotal : nil }
        return abs(entered - listTotal) > 0.004 && listTotal > 0 ? listTotal : nil
    }

    /// The Businessplatz-Abo needs the 1st-class upgrade; the price follows the list total unless it was edited by hand.
    private func toggle(_ addOn: TicketAddOn) {
        let before = selected
        let oldTotal = TicketAddOn.listTotal(before, productID: productID, variant: variant)
        let followsList = AdvisorEuro.parse(priceText).map { abs($0 - oldTotal) < 0.005 } ?? true
        var next = before
        if next.contains(addOn) {
            next.remove(addOn)
            if addOn == .firstClass { next.remove(.business) }
        } else {
            next.insert(addOn)
            if addOn == .business { next.insert(.firstClass) }
        }
        withMotion(Motion.snappy) {
            addOns = TicketAddOn.allCases.filter { next.contains($0) }.map(\.rawValue)
            if followsList || next.isEmpty {
                priceText = AdvisorEuro.editString(TicketAddOn.listTotal(next, productID: productID, variant: variant))
            }
        }
    }
}
