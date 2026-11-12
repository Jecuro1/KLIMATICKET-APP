import SwiftUI
import KlimaCore

/// „Raten-Übersicht“ (docs/TICKET_LETTERS.md §3): the 12 installments of a KlimaTicket Ö paid by SEPA monthly – what has been
/// paid so far, what is open, and next to it what the trips so far were worth, so cash and value can be compared honestly.
/// AGB 15.2: the first two installments come with the order, the other ten are debited in the first five working days of a
/// month („rund um den Monatsanfang“).
struct InstallmentsView: View {
    let context: TicketLetterContext
    /// The value of the trips of this ticket year so far (`SavingsSummary.totalValue`).
    let tripValue: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let plan = TicketRights.appliesAGB(to: context.ticket) && context.ticket.isMonthlyPayment
            ? InstallmentPlan.make(price: context.ticket.price, start: context.ticket.start) : nil
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    .reveal(.focus, order: 0)
                if let plan {
                    summaryCard(plan)
                        .reveal(order: 1)
                    timelineCard(plan)
                        .reveal(order: 2)
                    noteCard(plan)
                        .reveal(order: 3)
                } else {
                    emptyCard
                        .reveal(order: 1)
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .revealScope()
        .scrollEdgeEffectStyle(.soft, for: .all)
        .ambientBackground(.standard, glow: 0.55)
        .navigationTitle("Raten-Übersicht")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Raten · \(TicketAdvisor.yearLabel(start: context.ticket.start, end: context.ticket.end))")
            Text("Deine Raten")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("\(context.ticket.name) · SEPA-Monatsraten")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Paid versus value

    private func summaryCard(_ plan: InstallmentPlan) -> some View {
        let balance = plan.balance(tripValue: tripValue)
        return GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        paidColumn(plan)
                        valueColumn(balance)
                    }
                } else {
                    // Cash paid and value received side by side – the comparison is the point of this screen.
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        paidColumn(plan)
                        valueColumn(balance)
                    }
                }
                VStack(spacing: Theme.Spacing.s) {
                    AdvCompareBar(label: "Bezahlt", symbol: "eurosign.circle.fill", value: balance.paid, maxValue: max(balance.paid, balance.value, 1),
                                  color: Theme.dawn, valueText: Format.euroPrecise(balance.paid))
                    AdvCompareBar(label: "Fahrten", symbol: "tram.fill", value: balance.value, maxValue: max(balance.paid, balance.value, 1),
                                  color: Theme.glacier, valueText: Format.euro(balance.value))
                }
                verdict(balance)
                TktHairline()
                factRow("Noch offen", value: Format.euroPrecise(plan.openAmount),
                        detail: plan.openCount == 1 ? "1 Rate" : "\(plan.openCount) Raten")
                if let next = plan.next {
                    factRow("Nächste Abbuchung", value: Format.monthYear(next.month), detail: "rund um den Monatsanfang")
                } else {
                    Label("Alle 12 Raten sind bezahlt.", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.positiveText)
                }
            }
        }
    }

    private func paidColumn(_ plan: InstallmentPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Bezahlt bis heute")
            CountUpText(value: plan.paidAmount) { Format.euroPrecise($0) }
                .font(Theme.Typography.numberMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(plan.paidCount == 1 ? "1 Rate" : "\(plan.paidCount) Raten")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func valueColumn(_ balance: InstallmentPlan.Balance) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Nutzen der Fahrten bis heute")
            CountUpText(value: balance.value) { Format.euro($0) }
                .font(Theme.Typography.numberMedium)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Wert deiner erfassten Fahrten")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func verdict(_ balance: InstallmentPlan.Balance) -> some View {
        let covers = balance.coversPayments
        return AdvPanel(tint: (covers ? Theme.positive : Theme.dawn).opacity(0.12)) {
            Label {
                Text(covers
                     ? (balance.difference < 0.5 ? "Deine Fahrten decken genau die bisherigen Raten."
                                                 : "Deine Fahrten sind \(Format.euroPrecise(balance.difference)) mehr wert, als du bisher bezahlt hast.")
                     : "Deine Fahrten decken die bisherigen Raten noch nicht: \(Format.euroPrecise(balance.difference)) fehlen.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: covers ? "checkmark.seal.fill" : "hourglass")
                    .foregroundStyle(covers ? Theme.positiveText : Theme.summitText)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private func factRow(_ label: String, value: String, detail: String) -> some View {
        AdvFactRow(label: label, value: value, detail: detail)
    }

    // MARK: Timeline

    private func timelineCard(_ plan: InstallmentPlan) -> some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "12 Raten")
                    Text("\(Format.euroPrecise(plan.typicalAmount)) im Monat")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(plan.lastDiffers ? "zusammen \(Format.euroPrecise(plan.price)) – die letzte Rate gleicht den Cent aus"
                                          : "zusammen \(Format.euroPrecise(plan.price))")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                segmentBar(plan)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                        InstallmentRow(item: item, nextState: index + 1 < plan.items.count ? plan.items[index + 1].state : nil,
                                       isFirst: index == 0, isLast: index == plan.items.count - 1)
                    }
                }
            }
        }
    }

    /// Twelve segments that fill one after another when the card first scrolls into view.
    private func segmentBar(_ plan: InstallmentPlan) -> some View {
        DrawInReader { isDrawn in
            HStack(spacing: 3) {
                ForEach(plan.items) { item in
                    Capsule()
                        .fill(segmentStyle(item.state))
                        .frame(height: 8)
                        .scaleEffect(x: isDrawn ? 1 : 0.001, anchor: .leading)
                        .animation(MotionPolicy.isStatic ? nil : Motion.gentle.delay(Double(item.number) * 0.045), value: isDrawn)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plan.paidCount) von 12 Raten bezahlt")
    }

    private func segmentStyle(_ state: InstallmentPlan.Item.State) -> AnyShapeStyle {
        switch state {
        case .paid: AnyShapeStyle(Theme.positive)
        case .booking: AnyShapeStyle(Theme.dawn)
        case .upcoming: AnyShapeStyle(Theme.textTertiary.opacity(0.25))
        }
    }

    // MARK: Note

    private func noteCard(_ plan: InstallmentPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AdvNote(symbol: "doc.text.magnifyingglass",
                    text: "Grundlage: AGB KlimaTicket Ö (Stand \(TicketRights.agbStandShort)), Punkt 15.2 – die ersten zwei Raten mit der Bestellung, die übrigen zehn in den ersten fünf Werktagen eines Monats. Bei einer automatischen Verlängerung buchen sie alle zwölf monatlich ab (Punkt 15.6).")
            AdvNote(symbol: "banknote",
                    text: "Wann deine Bank genau bucht, wissen wir nicht, und auf den Cent können einzelne Raten abweichen. Als bezahlt zählt eine Rate erst nach den ersten fünf Werktagen des Monats. Dein Kontoauszug gilt.")
            if context.ticket.employerContribution > 0 {
                AdvNote(symbol: "briefcase",
                        text: "Ein Zuschuss deines Arbeitgebers ist hier nicht abgezogen: Die Raten gehen über den vollen Ticketpreis.")
            }
        }
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
    }

    private var emptyCard: some View {
        let isMonthly = context.ticket.isMonthlyPayment
        return LetterNoticeCard(symbol: isMonthly ? "info.circle.fill" : "banknote.fill",
                                title: isMonthly ? "Hier gibt es keine Raten-Übersicht" : "Du hast auf einmal bezahlt",
                                message: isMonthly ? LetterText.otherTicket
                                                   : "Die Raten-Übersicht gibt es nur für das KlimaTicket Ö mit SEPA-Monatsraten.")
    }
}

// MARK: - Row

/// One installment on the timeline: dot with connector, month and timing, amount and state – the state is written out, not
/// only coloured.
private struct InstallmentRow: View {
    var item: InstallmentPlan.Item
    /// The state of the installment below – the connector between two dots is filled once the lower one is paid.
    var nextState: InstallmentPlan.Item.State?
    var isFirst: Bool
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(connector(above: true))
                    .frame(width: 2, height: 10)
                    .opacity(isFirst ? 0 : 1)
                dot
                Rectangle()
                    .fill(connector(above: false))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .frame(width: 28)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    titleBlock
                    Spacer(minLength: Theme.Spacing.s)
                    amountBlock
                }
                VStack(alignment: .leading, spacing: 2) {
                    titleBlock
                    amountBlock
                }
            }
            .padding(.top, 6)
            .padding(.bottom, Theme.Spacing.s)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate \(item.number) von 12, \(heading), \(Format.euroPrecise(item.amount)), \(stateText)")
    }

    /// „Oktober 2026“ – or „Bei der Bestellung“ for the first two.
    private var heading: String {
        item.timing == .withOrder ? "bei der Bestellung" : Format.monthYear(item.month)
    }

    private var detail: String {
        item.timing == .withOrder ? "Rate \(item.number)" : "Rate \(item.number) · rund um den Monatsanfang"
    }

    private var stateText: String {
        switch item.state {
        case .paid: "bezahlt"
        case .booking: "wird gerade gebucht"
        case .upcoming: "offen"
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(heading.prefix(1).uppercased() + heading.dropFirst())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var amountBlock: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Format.euroPrecise(item.amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Label(stateText, systemImage: stateSymbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(stateColor)
        }
    }

    private var stateSymbol: String {
        switch item.state {
        case .paid: "checkmark"
        case .booking: "clock"
        case .upcoming: "circle.dotted"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .paid: Theme.positiveText
        case .booking: Theme.summitText
        case .upcoming: Theme.textSecondary
        }
    }

    private var dot: some View {
        ZStack {
            Circle()
                .fill(item.state == .paid ? Theme.positive : (item.state == .booking ? Theme.dawn : Theme.surfaceSecondary))
            Text("\(item.number)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(item.state == .upcoming ? Theme.textSecondary : Theme.onAccent)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func connector(above: Bool) -> Color {
        let isDone = above ? item.state == .paid : nextState == .paid
        return isDone ? Theme.positive.opacity(0.55) : Theme.separator
    }
}
