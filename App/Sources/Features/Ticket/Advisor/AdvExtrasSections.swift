import SwiftUI
import KlimaCore

// MARK: - 1.-Klasse-Upgrade

/// Σ (1st − 2nd class normal fare) of the train trips vs. the ÖBB upgrade (and the Vorteilsabo as the cheap alternative).
struct AdvFirstClassCard: View {
    let advice: FirstClassAdvice
    let isExpired: Bool

    var body: some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: AdvStyle.blockSpacing) {
                AdvCardHeader(kicker: "1.-Klasse-Upgrade – lohnt sich das?", title: AdvText.firstClassTitle(advice),
                              tone: AdvText.firstClassTone(advice), info: AdvRules.firstClass)
                if advice.verdict == .noTrainTrips {
                    Text("Sobald du Zugfahrten erfasst, rechnen wir dir hier aus, ob sich die 1. Klasse für dich auszahlt.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    content
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        AdvFigure(value: "≈ \(AdvText.euro(advice.projectedSurcharge))", caption: figureCaption,
                  color: advice.projectedSurcharge >= advice.upgradePrice ? Theme.dusk : Theme.textPrimary)
        ProgressRail(progress: advice.upgradePrice > 0 ? advice.projectedSurcharge / advice.upgradePrice : 0,
                     leadingLabel: isExpired ? "Mehrwert" : "Prognose bis Ablauf",
                     trailingLabel: "Upgrade \(AdvText.euro(advice.upgradePrice))",
                     fill: AnyShapeStyle(LinearGradient(colors: [Theme.glacier, Theme.dusk], startPoint: .leading, endPoint: .trailing)))
        if !advice.hasUpgrade {
            options
        }
        AdvFactList(rows: facts)
        Text(paragraph)
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        AdvNote(symbol: "info.circle",
                text: "ÖBB-Normalpreise 1. minus 2. Klasse. Das Upgrade gilt nur in Fernverkehrszügen – Regionalzüge sind mitgezählt, der Wert ist eher eine Obergrenze. Nicht eingerechnet: Lounges, 10 Reservierungen, CAT.")
    }

    private var figureCaption: String {
        let trips = AdvText.trips(advice.trainTrips)
        if advice.hasUpgrade {
            let basis = advice.countsOnlyFirstClassTrips ? "deine \(trips) in der 1. Klasse" : "deine \(trips) mit dem Zug"
            return isExpired ? "Mehrwert der 1. Klasse für \(basis)" : "Mehrwert der 1. Klasse für \(basis), bis Ablauf"
        }
        return isExpired ? "hätte die 1. Klasse für deine \(trips) mit dem Zug extra gekostet"
                         : "würde die 1. Klasse für deine Zugfahrten bis Ablauf extra kosten (bisher \(trips))"
    }

    private var options: some View {
        let cheapest = advice.cheapestOption
        let top = max(advice.projectedSurcharge, advice.vorteilsaboCost, advice.upgradePrice, 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Kicker(text: "Was wäre am günstigsten?")
            AdvCompareBar(label: "Einzeln aufzahlen", symbol: "ticket.fill", value: advice.projectedSurcharge, maxValue: top,
                          color: Theme.glacier, valueText: "≈ \(AdvText.euro(advice.projectedSurcharge))",
                          badge: cheapest == .payPerTrip ? cheapestBadge : nil)
            AdvCompareBar(label: "Vorteilsabo (\(AdvText.euro(advice.vorteilsaboPrice)))", symbol: "percent",
                          value: advice.vorteilsaboCost, maxValue: top, color: Theme.dusk,
                          valueText: "≈ \(AdvText.euro(advice.vorteilsaboCost))",
                          badge: cheapest == .vorteilsabo ? cheapestBadge : nil)
            AdvCompareBar(label: "Jahres-Upgrade", symbol: "sofa.fill", value: advice.upgradePrice, maxValue: top,
                          color: Theme.dawn, valueText: AdvText.euro(advice.upgradePrice),
                          badge: cheapest == .upgrade ? cheapestBadge : nil)
        }
    }

    private var cheapestBadge: AdvBadge { AdvBadge(text: "Am günstigsten", symbol: "checkmark", tone: .positive) }

    private var facts: [AdvFact] {
        var rows = [AdvFact(label: "Aufpreis pro Fahrt", value: "⌀ \(AdvText.cents(advice.averageSurchargePerLeg))",
                            detail: "je Richtung, über \(AdvText.trips(advice.trainLegs)) gerechnet")]
        if let needed = advice.legsNeeded {
            rows.append(AdvFact(label: "Das Upgrade rechnet sich ab", value: "≈ \(AdvText.trips(needed))",
                                detail: "Fahrten wie deine in einem Ticketjahr"))
        }
        if advice.hasUpgrade {
            rows.append(AdvFact(label: "In der 1. Klasse erfasst", value: "\(advice.firstClassTrips)",
                                detail: advice.countsOnlyFirstClassTrips
                                    ? "Gezählt werden nur diese Fahrten."
                                    : "Markiere 1.-Klasse-Fahrten beim Erfassen – dann rechnen wir genauer."))
        }
        return rows
    }

    private var paragraph: String {
        let value = AdvText.euro(advice.projectedSurcharge)
        let price = AdvText.euro(advice.upgradePrice)
        switch advice.verdict {
        case .worthIt:
            return "Fährst du deine Zugstrecken in der 1. Klasse, wären die Aufzahlungen ≈ \(value) wert – mehr als die \(price) fürs Jahres-Upgrade."
        case .notWorthIt:
            var text = "Für deine Fahrten wären die Aufzahlungen ≈ \(value) – deutlich weniger als die \(price) fürs Jahres-Upgrade."
            if advice.cheapestOption == .vorteilsabo {
                text += " Gönnst du dir nur ab und zu die 1. Klasse, ist das Vorteilsabo die günstigste Wahl."
            }
            return text
        case .paidOff:
            return "Deine Fahrten in der 1. Klasse wären einzeln ≈ \(value) teurer gewesen – das Upgrade um \(price) hat sich gelohnt."
        case .notPaidOff:
            let missing = AdvText.euro(max(0, advice.upgradePrice - advice.projectedSurcharge))
            return "Bis Ablauf kommst du voraussichtlich auf ≈ \(value) Mehrwert – \(missing) fehlen noch, bis das Upgrade um \(price) drin ist."
        case .noTrainTrips:
            return ""
        }
    }
}

// MARK: - Familien-Bilanz

/// Children's trips (companions × ÖBB child fare ≈ 50 %) vs. the Familie surcharge – or, without Familie, whether switching
/// would pay off.
struct AdvFamilyCard: View {
    let advice: FamilyAdvice
    let isExpired: Bool
    let isKlimaTicketOe: Bool

    var body: some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: AdvStyle.blockSpacing) {
                AdvCardHeader(kicker: "Familien-Bilanz", title: AdvText.familyTitle(advice), tone: AdvText.familyTone(advice),
                              info: AdvRules.family)
                if advice.verdict == .noChildTrips {
                    Text("Trag beim Erfassen ein, wie viele Kinder mitgefahren sind – dann siehst du hier, ob sich der Aufschlag von \(AdvText.euro(advice.surcharge)) lohnt.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    content
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let shown = advice.isFamilyTicket ? advice.childValueSoFar : advice.projectedChildValue
        AdvFigure(value: AdvText.euro(shown), caption: figureCaption,
                  color: shown >= advice.surcharge ? Theme.positive : Theme.textPrimary)
        ProgressRail(progress: advice.surcharge > 0 ? shown / advice.surcharge : 0,
                     leadingLabel: advice.isFamilyTicket ? "Kinderfahrten" : "Mitfahrende",
                     trailingLabel: "Aufschlag \(AdvText.euro(advice.surcharge))",
                     fill: AnyShapeStyle(LinearGradient(colors: [Theme.pine, Theme.glacier], startPoint: .leading, endPoint: .trailing)))
        AdvFactList(rows: facts)
        Text(paragraph)
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        if advice.verdict == .worthSwitching && isKlimaTicketOe {
            AdvPanel(tint: Theme.positive.opacity(0.12)) {
                Label {
                    Text("Auf Familie wechseln kannst du jederzeit gebührenfrei. Abgerechnet wird tagesgenau, dein Ticket gilt dann 12 Monate ab dem Wechseltag.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .foregroundStyle(Theme.positiveText)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            }
        }
        AdvNote(symbol: "info.circle", text: ruleNote)
    }

    private var figureCaption: String {
        if advice.isFamilyTicket {
            return "Wert der Kinderfahrten bisher – zum ÖBB-Kinderpreis"
        }
        return isExpired ? "hätten deine Mitfahrenden als Kinder gekostet" : "hätten deine Mitfahrenden als Kinder bis Ablauf gekostet"
    }

    private var facts: [AdvFact] {
        var rows = [
            AdvFact(label: "Fahrten mit Kindern", value: "\(advice.tripsWithChildren)"),
            AdvFact(label: "Kinder-Fahrten", value: "\(advice.childJourneys)",
                    detail: "⌀ \(Format.number(advice.averageChildren, decimals: 1)) Kinder pro Fahrt, je Richtung gezählt"),
        ]
        if advice.isFamilyTicket && !isExpired {
            rows.append(AdvFact(label: "Prognose bis Ablauf", value: "≈ \(AdvText.euro(advice.projectedChildValue))"))
        }
        return rows
    }

    private var paragraph: String {
        let value = AdvText.euro(advice.childValueSoFar)
        let projected = AdvText.euro(advice.projectedChildValue)
        let surcharge = AdvText.euro(advice.surcharge)
        switch advice.verdict {
        case .paidOff:
            return "Deine Kinder sind schon um \(value) mitgefahren – \(AdvText.euro(advice.childValueSoFar - advice.surcharge)) mehr als der Aufschlag."
        case .onTrack:
            return "Bisher \(value). Bei eurem Tempo kommt ihr bis Ablauf auf ≈ \(projected) – der Aufschlag holt sich herein."
        case .notPaidOff:
            return "Bei eurem Tempo kommt ihr bis Ablauf auf ≈ \(projected) – weniger als die \(surcharge) Aufschlag. Fahren die Kinder selten mit, reicht beim nächsten Mal vielleicht das Ticket ohne Familie."
        case .worthSwitching:
            return "Waren deine Mitfahrenden Kinder von 6 bis 14, hätten sie mit KlimaTicket Familie bis Ablauf ≈ \(projected) gespart – mehr als der Aufschlag von \(surcharge)."
        case .notWorthSwitching:
            return "Als Kinder wären deine Mitfahrenden bis Ablauf ≈ \(projected) wert – weniger als der Aufschlag von \(surcharge)."
        case .noChildTrips:
            return ""
        }
    }

    private var ruleNote: String {
        if isKlimaTicketOe {
            return "Bis zu 4 Kinder vom 6. bis zum 15. Geburtstag fahren gratis mit – ohne Nachweis. Bewertet mit dem halben Normalpreis (ÖBB-Kinderpreis)."
        }
        return "Bewertet mit dem halben Normalpreis. Altersgrenzen und Anzahl der Kinder regelt dein Verkehrsverbund."
    }
}

// MARK: - Jobticket

/// Employer contribution: the payoff is measured against the own share; business trips deductible up to it (AK).
struct AdvJobticketCard: View {
    let advice: JobticketAdvice
    let isExpired: Bool

    var body: some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: AdvStyle.blockSpacing) {
                AdvCardHeader(kicker: "Jobticket", title: title, tone: advice.isOwnSharePaidOff ? AdvTone.positive : nil,
                              info: AdvRules.jobticket)
                AdvFigure(value: AdvText.euro(advice.ownShare),
                          caption: "zahlst du selbst – \(Format.percent(advice.ownShareFraction)) von \(AdvText.euro(advice.fullPrice))")
                AdvShareBar(contribution: advice.contribution, ownShare: advice.ownShare)
                AdvFactList(rows: facts)
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                AdvNote(symbol: "building.columns.fill",
                        text: "Pendlerpauschale: wird um den steuerfreien Zuschuss gekürzt, der Pendlereuro bleibt. Orientierung, keine Steuerberatung.")
            }
        }
    }

    private var title: String {
        advice.isOwnSharePaidOff ? "Für dich hat es sich schon rentiert" : "Für dich rentiert es sich ab \(AdvText.euro(advice.ownShare))"
    }

    private var facts: [AdvFact] {
        var rows = [
            AdvFact(label: "Rentiert für dich", value: breakEvenText(advice.ownBreakEven, paid: advice.isOwnSharePaidOff),
                    valueColor: advice.isOwnSharePaidOff ? Theme.positiveText : Theme.textPrimary),
            AdvFact(label: "Ohne Zuschuss", value: breakEvenText(advice.fullBreakEven, paid: advice.isFullPricePaidOff),
                    detail: "bei vollem Preis von \(AdvText.euro(advice.fullPrice))"),
        ]
        if advice.businessTripValue > 0 {
            rows.append(AdvFact(label: "Dienstreisen bisher", value: AdvText.euro(advice.businessTripValue),
                                detail: "absetzbar bis höchstens \(AdvText.euro(advice.ownShare)) – dein Eigenanteil (AK)"))
        }
        return rows
    }

    private func breakEvenText(_ date: Date?, paid: Bool) -> String {
        guard let date else { return isExpired ? "nicht erreicht" : "erst nach Ablauf" }
        return paid ? "seit \(Format.date(date, .long))" : "≈ \(Format.date(date, .long))"
    }

    private var paragraph: String {
        let base = "Weil dein Arbeitgeber \(AdvText.euro(advice.contribution)) übernimmt, zählt für deine Bilanz nur dein Anteil."
        if let own = advice.ownBreakEven, let full = advice.fullBreakEven {
            let days = Calendar.vienna.dateComponents([.day], from: own, to: full).day ?? 0
            if days > 0 { return base + " So rentiert sich dein Ticket \(Format.days(days)) früher." }
        }
        if advice.ownBreakEven != nil && advice.fullBreakEven == nil {
            return base + " Ohne Zuschuss würde es sich bei deinem Tempo erst nach Ablauf rentieren."
        }
        return base
    }
}

/// Full price split into the employer's and the own part.
private struct AdvShareBar: View {
    var contribution: Double
    var ownShare: Double

    var body: some View {
        let total = max(contribution + ownShare, 1)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let width = max(geo.size.width - gap, 0)
                HStack(spacing: gap) {
                    Capsule()
                        .fill(Theme.pine)
                        .frame(width: max(8, width * CGFloat(contribution / total)))
                    Capsule()
                        .fill(Theme.routeGradient)
                        .frame(width: max(8, width * CGFloat(ownShare / total)))
                }
            }
            .frame(height: 10)
            HStack {
                legend(color: Theme.pine, text: "Arbeitgeber \(AdvText.euro(contribution))")
                Spacer(minLength: Theme.Spacing.xs)
                legend(color: Theme.glacier, text: "Du \(AdvText.euro(ownShare))")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aufteilung des Ticketpreises")
        .accessibilityValue("Arbeitgeber \(AdvText.euro(contribution)), du \(AdvText.euro(ownShare))")
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Without a contribution: a compact invitation to enter it.
struct AdvJobticketHint: View {
    var onEdit: () -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    TktIconTile(symbol: "briefcase.fill", color: Theme.gold, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Kicker(text: "Jobticket")
                        Text("Zahlt dein Arbeitgeber mit?")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Mit Zuschuss rechnen wir deine Bilanz auf deinen Eigenanteil – und zeigen dir, was du bei Dienstreisen absetzen kannst.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Button(action: onEdit) {
                    Label("Zuschuss eintragen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .padding(.leading, 40 + Theme.Spacing.s)
            }
        }
    }
}
