import SwiftUI
import Charts
import KlimaCore

// MARK: - Kündigungsrechner

/// Ordinary cancellation (from the 7th validity month, fee = one monthly amount): when it becomes possible, the money
/// back today vs. on the last day of the validity month vs. next month, and the comparison with the trips you would lose.
struct AdvCancellationCard: View {
    let advice: CancellationAdvice
    let hasEmployerContribution: Bool

    var body: some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: AdvStyle.blockSpacing) {
                AdvCardHeader(kicker: "Kündigungsrechner", title: AdvText.cancellationTitle(advice),
                              tone: AdvText.cancellationTone(advice), info: AdvRules.cancellation)
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch advice.verdict {
        case .keep, .consider, .notWorthwhile:
            possibleContent
        case .notYet:
            notYetContent
        case .beforeStart:
            Text("Vor dem ersten Gültigkeitstag kannst du dein Ticket bei einer Servicestelle gebührenfrei zurückgeben. Online gekauft hast du außerdem 14 Tage Widerrufsrecht.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .unsupported:
            unsupportedContent
        case .expired:
            EmptyView()
        }
    }

    // MARK: Possible now

    @ViewBuilder
    private var possibleContent: some View {
        if let end = advice.endOfMonth {
            statusPanel(symbol: "checkmark.seal.fill", tone: .positive,
                        text: "Kündbar seit \(Format.date(advice.possibleFrom, .long)) · du bist im \(advice.currentMonth). Gültigkeitsmonat")
            AdvFigure(value: AdvText.cents(max(0, advice.isMonthlyPayment ? end.saving : end.refund)),
                      caption: figureCaption(end), color: end.isWorthwhile ? Theme.positive : Theme.textPrimary)
            if end.isWorthwhile {
                comparison(end)
            }
            Text(verdictText(end))
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            AdvFactList(rows: timingRows(end))
            breakdown(end)
            chartBlock
            howTo
        }
    }

    private func figureCaption(_ q: CancellationAdvice.Quote) -> String {
        let day = Format.date(q.date, .long)
        if !q.isWorthwhile { return "Ab jetzt ist das Kündigungsentgelt höher als die Erstattung." }
        if advice.isMonthlyPayment {
            return "sparst du bei Kündigung bis \(day): keine weiteren \(q.unstartedMonths) Raten, minus Kündigungsentgelt"
        }
        return "zurück, wenn du bis \(day) kündigst"
    }

    private func comparison(_ q: CancellationAdvice.Quote) -> some View {
        let money = max(0, advice.isMonthlyPayment ? q.saving : q.refund)
        let top = max(money, q.lostTripValue, 1)
        return VStack(spacing: Theme.Spacing.s) {
            AdvCompareBar(label: advice.isMonthlyPayment ? "Ersparnis" : "Erstattung", symbol: "arrow.uturn.backward.circle.fill",
                          value: money, maxValue: top, color: Theme.positive, valueText: AdvText.euro(money))
            AdvCompareBar(label: "Fahrten bis Ablauf", symbol: "tram.fill", value: q.lostTripValue, maxValue: top,
                          color: Theme.glacier, valueText: "≈ \(AdvText.euro(q.lostTripValue))",
                          badge: AdvBadge(text: "Prognose", tone: .neutral))
        }
    }

    private func verdictText(_ q: CancellationAdvice.Quote) -> String {
        let money = max(0, advice.isMonthlyPayment ? q.saving : q.refund)
        switch advice.verdict {
        case .keep:
            let difference = q.lostTripValue - money
            return "Wenn du jetzt kündigst, verlierst du voraussichtlich \(AdvText.euro(q.lostTripValue)) an Fahrten – \(AdvText.euro(difference)) mehr, als du zurückbekommst. Behalten lohnt sich."
        case .consider:
            if q.lostTripValue < 1 {
                return "Zuletzt bist du kaum gefahren. Brauchst du das Ticket nicht mehr, bekommst du \(AdvText.euro(money)) zurück."
            }
            return "Deine Fahrten bis Ablauf wären voraussichtlich nur \(AdvText.euro(q.lostTripValue)) wert – weniger als die \(AdvText.euro(money)), die du sparst. Fährst du kaum noch, kann sich Kündigen lohnen."
        default:
            return "Im \(advice.currentMonth). Gültigkeitsmonat deckt die Erstattung das Kündigungsentgelt von \(AdvText.cents(advice.fee)) nicht mehr. Fahr dein Ticket einfach bis zum Ende."
        }
    }

    private func timingRows(_ end: CancellationAdvice.Quote) -> [AdvFact] {
        var rows: [AdvFact] = []
        func money(_ q: CancellationAdvice.Quote) -> String {
            AdvText.cents(max(0, advice.isMonthlyPayment ? q.saving : q.refund))
        }
        if let today = advice.today, today.date < end.date {
            rows.append(AdvFact(label: "Heute kündigen", value: money(today),
                                detail: "Danach fährst du nicht mehr mit diesem Ticket."))
        }
        rows.append(AdvFact(label: "Bis \(Format.date(end.date)) kündigen", value: money(end), detail: endOfMonthDetail(end),
                            valueColor: Theme.positiveText))
        if let next = advice.nextMonth {
            let drop = max(0, (advice.isMonthlyPayment ? end.saving : end.refund) - max(0, advice.isMonthlyPayment ? next.saving : next.refund))
            rows.append(AdvFact(label: "Ab \(Format.date(next.date))", value: money(next),
                                detail: drop > 0.004 ? "\(AdvText.cents(drop)) weniger – ein Monatsbetrag" : "Dann bringt Kündigen nichts mehr."))
        }
        return rows
    }

    private func endOfMonthDetail(_ end: CancellationAdvice.Quote) -> String {
        guard let today = advice.today, today.date < end.date else {
            return "Heute ist der letzte Tag dieses Gültigkeitsmonats."
        }
        let ridden = max(0, today.lostTripValue - end.lostTripValue)
        guard ridden >= 1 else { return "Gleich viel zurück – und bis dahin gilt dein Ticket weiter." }
        return "Gleich viel zurück – und bis dahin fährst du weiter (≈ \(AdvText.euro(ridden)) an Fahrten)."
    }

    private func breakdown(_ q: CancellationAdvice.Quote) -> some View {
        let months = AdvText.months(q.unstartedMonths)
        let text: String
        if advice.fee > 0 {
            text = "\(months) nicht angefangen × \(AdvText.cents(advice.monthlyAmount)) = \(AdvText.cents(q.refundGross)), minus Kündigungsentgelt \(AdvText.cents(advice.fee))"
        } else {
            text = "\(months) nicht angefangen × \(AdvText.cents(advice.monthlyAmount)) = \(AdvText.cents(q.refundGross)), ohne Kündigungsentgelt (Kennenlern-Aktion)"
        }
        return AdvNote(symbol: "function", text: text)
    }

    // MARK: Not yet possible

    @ViewBuilder
    private var notYetContent: some View {
        let days = Calendar.vienna.dateComponents([.day], from: Calendar.vienna.startOfDay(for: Date()),
                                                  to: advice.possibleFrom).day ?? 0
        AdvFigure(value: Format.days(max(days, 0)),
                  caption: "bis du ohne Angabe von Gründen kündigen kannst – ab dem \(advice.possibleFromMonth). Gültigkeitsmonat")
        if let first = advice.firstPossible {
            let money = max(0, advice.isMonthlyPayment ? first.saving : first.refund)
            statusPanel(symbol: "calendar.badge.clock", tone: .neutral,
                        text: advice.isMonthlyPayment
                            ? "Kündigst du bis \(Format.date(first.date, .long)), sparst du \(AdvText.cents(money)): keine weiteren \(first.unstartedMonths) Raten, minus Entgelt."
                            : "Kündigst du bis \(Format.date(first.date, .long)), bekommst du \(AdvText.cents(money)) zurück.")
            if first.lostTripValue > 0 {
                Text("Bei deinem Tempo wären deine Fahrten ab dann noch ≈ \(AdvText.euro(first.lostTripValue)) wert\(first.lostTripValue > money ? " – mehr, als du zurückbekämst." : ".")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        chartBlock
        howTo
    }

    // MARK: Regional

    @ViewBuilder
    private var unsupportedContent: some View {
        switch advice.policy {
        case .regional(let note):
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            AdvNote(symbol: "info.circle", text: "Die genauen Bedingungen und Formulare findest du auf der Website deines Verkehrsverbunds.")
        default:
            Text("Für eigene Tickets kennen wir die Kündigungsbedingungen nicht. Schau in die Bedingungen deines Anbieters.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Shared blocks

    @ViewBuilder
    private var chartBlock: some View {
        if !advice.months.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: advice.isMonthlyPayment ? "Ersparnis je Kündigungsmonat" : "Erstattung je Kündigungsmonat")
                AdvCancellationChart(months: advice.months, showsLostValue: advice.dailyPace > 0)
                    .frame(height: 170)
                legend
            }
            .padding(.top, Theme.Spacing.xxs)
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.s) {
            AdvLegendSwatch(style: AnyShapeStyle(Theme.positive), label: advice.isMonthlyPayment ? "Ersparnis" : "Erstattung")
            if advice.dailyPace > 0 {
                StatsLegendItem(label: "Fahrten danach", style: AnyShapeStyle(Theme.glacier))
            }
            AdvLegendSwatch(style: AnyShapeStyle(Theme.textTertiary.opacity(0.3)), label: "nicht kündbar")
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private var howTo: some View {
        var text = "So geht's: Kündigungsformular unterschreiben und mit deiner Karte bei einer Servicestelle abgeben – maßgeblich ist der Tag der Rückgabe."
        if hasEmployerContribution {
            text += " Hat dein Arbeitgeber mitgezahlt, sprich die Kündigung mit ihm ab."
        }
        return AdvNote(symbol: "doc.text.fill", text: text)
    }

    private func statusPanel(symbol: String, tone: AdvTone, text: String) -> some View {
        AdvPanel(tint: tone.fill) {
            Label {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tone.textColor)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Chart

/// Money back per validity month (bars, months 1–6 not cancellable) and the projected value of the trips after that
/// month (line). Where the bar rises above the line, cancelling pays off.
struct AdvCancellationChart: View {
    var months: [CancellationAdvice.Month]
    var showsLostValue: Bool

    private var maxY: Double {
        let top = months.map { max($0.saving, showsLostValue ? $0.lostTripValue : 0) }.max() ?? 0
        return max(top, 20) * 1.22
    }

    var body: some View {
        Chart {
            ForEach(months) { month in
                bar(month)
            }
            if showsLostValue {
                ForEach(months.filter { !$0.isPast }) { month in
                    lostLine(month)
                }
            }
        }
        .chartYScale(domain: 0...maxY)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: months.map { "\($0.index)" }) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let month = months.first(where: { "\($0.index)" == id }) {
                        Text(id)
                            .font(.caption2.weight(month.isCurrent ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(month.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Erstattung je Kündigungsmonat")
    }

    @ChartContentBuilder
    private func bar(_ month: CancellationAdvice.Month) -> some ChartContent {
        let height = month.isAllowed ? max(0, month.saving) : maxY * 0.035
        BarMark(x: .value("Monat", "\(month.index)"), y: .value("Erstattung", height), width: .ratio(0.62))
            .cornerRadius(4)
            .foregroundStyle(style(month))
            .annotation(position: .top, spacing: 3) {
                if month.isCurrent {
                    Text("jetzt")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.positiveText)
                        .fixedSize()
                }
            }
            .accessibilityLabel("\(month.index). Gültigkeitsmonat\(month.isCurrent ? ", jetzt" : "")")
            .accessibilityValue(accessibilityValue(month))
    }

    @ChartContentBuilder
    private func lostLine(_ month: CancellationAdvice.Month) -> some ChartContent {
        LineMark(x: .value("Monat", "\(month.index)"), y: .value("Fahrten danach", month.lostTripValue))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            .foregroundStyle(Theme.glacier)
            .accessibilityHidden(true)
        PointMark(x: .value("Monat", "\(month.index)"), y: .value("Fahrten danach", month.lostTripValue))
            .symbolSize(month.isCurrent ? 36 : 14)
            .foregroundStyle(Theme.glacier)
            .accessibilityHidden(true)
    }

    private func style(_ month: CancellationAdvice.Month) -> AnyShapeStyle {
        if !month.isAllowed { return AnyShapeStyle(Theme.textTertiary.opacity(0.3)) }
        if month.isCurrent {
            return AnyShapeStyle(LinearGradient(colors: [Theme.positive, Theme.positive.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Theme.positive.opacity(month.isPast ? 0.25 : 0.5))
    }

    private func accessibilityValue(_ month: CancellationAdvice.Month) -> String {
        guard month.isAllowed else { return "nicht kündbar" }
        var text = month.saving > 0 ? "\(AdvText.euro(month.saving)) zurück" : "keine Erstattung"
        if showsLostValue && !month.isPast { text += ", Fahrten danach ≈ \(AdvText.euro(month.lostTripValue))" }
        return text
    }
}

// MARK: - Außerordentlich

/// Fee-free cancellation for important reasons (moving abroad, illness ≥ 3 months, unemployment) – within 4 weeks.
struct AdvExtraordinaryCard: View {
    let advice: CancellationAdvice

    private struct Reason: Identifiable {
        var symbol: String
        var title: String
        var detail: String
        var id: String { title }
    }

    private var reasons: [Reason] {
        if advice.policy == .ooevv {
            return [Reason(symbol: "house.and.flag.fill", title: "Umzug", detail: "in ein anderes Bundesland oder ins Ausland")]
        }
        return [
            Reason(symbol: "airplane.departure", title: "Umzug ins Ausland", detail: "neuer Hauptwohnsitz außerhalb Österreichs"),
            Reason(symbol: "cross.case.fill", title: "Krankheit ab 3 Monaten", detail: "mit ärztlichem Attest"),
            Reason(symbol: "briefcase.fill", title: "Arbeitslosigkeit", detail: "ab dem Tag, an dem sie beginnt"),
        ]
    }

    var body: some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: AdvStyle.blockSpacing) {
                AdvCardHeader(kicker: "Außerordentlich kündigen", title: "Ohne Entgelt bei wichtigen Gründen",
                              info: AdvRules.extraordinary)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(reasons) { reason in
                        HStack(spacing: Theme.Spacing.s) {
                            TktIconTile(symbol: reason.symbol, color: Theme.dusk, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reason.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(reason.detail)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let quote = advice.extraordinary {
                    AdvPanel(tint: Theme.positive.opacity(0.12)) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Text(advice.isMonthlyPayment
                                 ? "Heute: keine weiteren \(quote.unstartedMonths) Raten"
                                 : "Heute: \(AdvText.months(quote.unstartedMonths)) × \(AdvText.cents(advice.monthlyAmount))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Theme.Spacing.xs)
                            Text(AdvText.cents(quote.saving))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.positiveText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                AdvNote(symbol: "clock.badge.exclamationmark",
                        text: "Gib Formular, Nachweis und Karte binnen \(AdvisorRules.extraordinaryFilingWeeks) Wochen nach Eintritt des Grundes ab.")
            }
        }
    }
}
