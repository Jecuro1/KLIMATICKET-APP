import SwiftUI
import Charts
import UIKit
import KlimaCore

// MARK: - Verlängern oder kündigen?

/// Projection of the payoff at expiry and for the next ticket year at the new price, with an honest recommendation.
struct AdvRenewalCard: View {
    let renewal: RenewalAdvice
    let summary: SavingsSummary
    let hasEmployerContribution: Bool

    var body: some View {
        GlassCard(padding: AdvStyle.cardPadding) {
            VStack(alignment: .leading, spacing: AdvStyle.blockSpacing) {
                AdvCardHeader(kicker: "Verlängern oder kündigen?", title: AdvText.renewalTitle(renewal),
                              tone: AdvText.renewalTone(renewal), info: AdvRules.renewal)
                AdvFigure(value: AdvText.signed(renewal.projectedNextYearNet), caption: figureCaption, color: figureColor)
                AdvRenewalChart(columns: columns)
                    .frame(height: 196)
                legend
                AdvFactList(rows: facts)
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Figure

    private var figureColor: Color {
        if renewal.verdict == .tooEarly { return Theme.textPrimary }
        return renewal.projectedNextYearNet >= 0 ? Theme.positive : Theme.summit
    }

    private var figureCaption: String {
        let base = "voraussichtlich im Ticketjahr \(renewal.nextYearLabel) · Fahrtwert minus Preis"
        return renewal.verdict == .tooEarly ? "erste Schätzung für \(renewal.nextYearLabel) – noch unsicher" : base
    }

    // MARK: Chart data

    private var columns: [AdvYearColumn] {
        let current = AdvYearColumn(id: 0, label: TicketAdvisor.yearLabel(start: summaryStart, end: renewal.expiry),
                                    actual: summary.totalValue,
                                    forecast: max(0, renewal.projectedValueAtExpiry - summary.totalValue),
                                    price: renewal.ownShare, isNext: false)
        let next = AdvYearColumn(id: 1, label: renewal.nextYearLabel, actual: 0, forecast: renewal.projectedNextYearValue,
                                 price: renewal.nextOwnShare, isNext: true)
        return [current, next]
    }

    /// First day of the current ticket year (derived from expiry, the summary has no dates).
    private var summaryStart: Date {
        Calendar.vienna.date(byAdding: .day, value: -(summary.daysTotal - 1), to: Calendar.vienna.startOfDay(for: renewal.expiry))
            ?? renewal.expiry
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.s) {
            AdvLegendSwatch(style: AnyShapeStyle(AdvRenewalChart.actualGradient), label: "Bisher")
            AdvLegendSwatch(style: AnyShapeStyle(Theme.glacier.opacity(0.28)), label: "Prognose")
            StatsLegendItem(label: hasEmployerContribution ? "Dein Anteil" : "Ticketpreis", style: AnyShapeStyle(Theme.summit),
                            dashed: true)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    // MARK: Facts

    private var facts: [AdvFact] {
        var rows: [AdvFact] = []
        if renewal.isExpired {
            rows.append(AdvFact(label: "Ticketjahr beendet", value: AdvText.euro(summary.totalValue),
                                detail: "\(AdvText.signed(summary.net)) gegenüber \(AdvText.euro(renewal.ownShare)) Preis"))
        } else {
            rows.append(AdvFact(label: "Bis Ablauf am \(Format.date(renewal.expiry))",
                                value: "≈\u{00A0}\(AdvText.euro(renewal.projectedValueAtExpiry))",
                                detail: "\(AdvText.signed(renewal.projectedNetAtExpiry)) gegenüber \(AdvText.euro(renewal.ownShare)) Preis"))
        }
        rows.append(AdvFact(label: "Preis ab \(Format.date(renewal.renewalStart))", value: AdvText.euro(renewal.nextPrice),
                            detail: priceDetail))
        rows.append(AdvFact(label: "Break-even \(renewal.nextYearLabel)", value: breakEvenValue, detail: breakEvenDetail))
        if renewal.fareGrowth > 1.0005 {
            let percent = Format.number((renewal.fareGrowth - 1) * 100, decimals: 1)
            rows.append(AdvFact(label: "Normalpreise", value: "+\u{00A0}\(percent)\u{00A0}%",
                                detail: "Die angekündigte Tariferhöhung der ÖBB ist eingerechnet."))
        }
        return rows
    }

    private var priceDetail: String {
        var text: String
        switch renewal.priceStatus {
        case .announced(let date):
            text = "Neuer Preis für Tickets ab \(Format.date(date, .long))."
        case .latestKnown:
            text = "Für \(renewal.nextYearLabel) ist noch kein neuer Preis veröffentlicht – wir rechnen mit dem aktuellen."
        case .custom:
            text = "Eigenes Ticket – wir rechnen mit deinem bisherigen Preis."
        }
        if renewal.priceChange > 0.5 {
            text += " Das sind \(AdvText.euro(renewal.priceChange)) mehr als bei deinem Ticket."
        } else if renewal.priceChange < -0.5 {
            text += " Das sind \(AdvText.euro(-renewal.priceChange)) weniger als bei deinem Ticket."
        }
        if hasEmployerContribution {
            text += " Dein Anteil nach Zuschuss: \(AdvText.euro(renewal.nextOwnShare))."
        }
        return text
    }

    private var breakEvenValue: String {
        if renewal.nextOwnShare <= 0.01 { return "ab der 1. Fahrt" }
        guard let trips = renewal.nextYearBreakEvenTrips else { return "–" }
        return "≈\u{00A0}\(AdvText.trips(trips))"
    }

    private var breakEvenDetail: String? {
        if renewal.nextOwnShare <= 0.01 { return "Dein Arbeitgeber zahlt das ganze Ticket." }
        guard renewal.nextYearBreakEvenTrips != nil else { return "Sobald du Fahrten erfasst, rechnen wir es aus." }
        if let date = renewal.nextYearBreakEvenDate {
            return "bei deinem Tempo um den \(Format.date(date, .long))"
        }
        return "bei deinem bisherigen Tempo nicht innerhalb des Ticketjahres"
    }

    // MARK: Recommendation

    private var paragraph: String {
        let value = AdvText.euro(renewal.projectedNextYearValue)
        let net = renewal.projectedNextYearNet
        switch renewal.verdict {
        case .renew:
            if renewal.nextOwnShare <= 0.01 {
                return "Dein Arbeitgeber übernimmt den Preis – jede Fahrt ist für dich reiner Gewinn."
            }
            return "Fährst du weiter wie bisher, sind deine Fahrten im Ticketjahr \(renewal.nextYearLabel) voraussichtlich \(value) wert – \(AdvText.euro(net)) mehr, als das Ticket kostet. Verlängern ist die gute Wahl."
        case .close:
            let trips = renewal.nextYearBreakEvenTrips.map { " Rund \(AdvText.trips($0)) wie deine im Jahr, und du bist auf der sicheren Seite." } ?? ""
            return "Bei deinem Tempo wären es ≈\u{00A0}\(value) – ziemlich genau der Preis.\(trips)"
        case .reconsider:
            return "Deine Fahrten wären nächstes Jahr voraussichtlich nur ≈\u{00A0}\(value) wert, \(AdvText.euro(-net)) weniger als der Preis. Unter Statistik › „Welches Ticket lohnt sich?“ siehst du, ob ein regionales KlimaTicket günstiger wäre – oder du planst bewusst mehr Fahrten."
        case .tooEarly:
            return "Erfass noch ein paar Wochen lang deine Fahrten – dann sagen wir dir ehrlich, ob sich das nächste Jahr lohnt."
        }
    }
}

// MARK: - Chart

struct AdvYearColumn: Identifiable {
    var id: Int
    var label: String
    var actual: Double
    var forecast: Double
    var price: Double
    var isNext: Bool

    var total: Double { actual + forecast }
    var x: Double { Double(id) }
}

/// Two columns – this ticket year (logged + forecast) and the next one (forecast) – each with its price as a dashed
/// „Gipfellinie“ (DESIGN.md §5.4 motif).
struct AdvRenewalChart: View {
    var columns: [AdvYearColumn]

    static let actualGradient = LinearGradient(colors: [Theme.glacier, Theme.dusk.opacity(0.9)], startPoint: .top, endPoint: .bottom)
    private static let barHalfWidth = 0.26
    private static let ruleHalfWidth = 0.36

    private var maxY: Double {
        let top = columns.map { max($0.total, $0.price) }.max() ?? 0
        return max(top, 10) * 1.3
    }

    var body: some View {
        Chart {
            ForEach(columns) { column in
                barMarks(column)
                priceRule(column)
            }
        }
        .chartXScale(domain: -0.6...1.6)
        .chartYScale(domain: 0...maxY)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: columns.map(\.x)) { value in
                AxisValueLabel(anchor: .top) {
                    if let x = value.as(Double.self), let column = columns.first(where: { $0.x == x }) {
                        Text(column.label)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(column.isNext ? Theme.textSecondary : Theme.textPrimary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vergleich der Ticketjahre")
        .accessibilityValue(accessibilitySummary)
    }

    /// The projected column is drawn full height in a soft tint, the logged value fills it from the bottom – no seam
    /// between two rounded segments, and the column reads like a gauge that is filling up.
    @ChartContentBuilder
    private func barMarks(_ column: AdvYearColumn) -> some ChartContent {
        let left = column.x - Self.barHalfWidth
        let right = column.x + Self.barHalfWidth
        if column.forecast > 0 {
            RectangleMark(xStart: .value("Jahr", left), xEnd: .value("Jahr", right),
                          yStart: .value("Wert", 0.0), yEnd: .value("Wert", column.total))
                .cornerRadius(10)
                .foregroundStyle((column.isNext ? Theme.dusk : Theme.glacier).opacity(column.isNext ? 0.30 : 0.22))
                .annotation(position: .top, spacing: 4) {
                    valueLabel(column)
                }
        }
        if column.actual > 0 {
            RectangleMark(xStart: .value("Jahr", left), xEnd: .value("Jahr", right),
                          yStart: .value("Wert", 0.0), yEnd: .value("Wert", column.actual))
                .cornerRadius(10)
                .foregroundStyle(Self.actualGradient)
                .annotation(position: .top, spacing: 4) {
                    if column.forecast <= 0 { valueLabel(column) }
                }
        }
    }

    @ChartContentBuilder
    private func priceRule(_ column: AdvYearColumn) -> some ChartContent {
        RuleMark(xStart: .value("Jahr", column.x - Self.ruleHalfWidth), xEnd: .value("Jahr", column.x + Self.ruleHalfWidth),
                 y: .value("Preis", column.price))
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
            .foregroundStyle(Theme.summit)
            .annotation(position: column.total >= column.price ? .bottom : .top, alignment: .leading, spacing: 3) {
                Text(AdvText.euro(column.price))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.summitText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.sheetBackground.opacity(0.8), in: .capsule)
                    .fixedSize()
            }
    }

    private func valueLabel(_ column: AdvYearColumn) -> some View {
        Text(column.forecast > 0 ? "≈\u{00A0}\(AdvText.euro(column.total))" : AdvText.euro(column.total))
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            .fixedSize()
    }

    private var accessibilitySummary: String {
        columns.map { column in
            let value = column.forecast > 0 ? "voraussichtlich \(AdvText.euro(column.total))" : AdvText.euro(column.total)
            return "Ticketjahr \(column.label): Fahrtwert \(value), Preis \(AdvText.euro(column.price))"
        }
        .joined(separator: ". ")
    }
}

/// Legend swatch for bars (solid or dashed outline).
struct AdvLegendSwatch: View {
    var style: AnyShapeStyle
    var label: String
    var dashed: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(style)
                .overlay {
                    if dashed {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Theme.glacier.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .frame(width: 9, height: 12)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Automatic renewal / reminder

/// SEPA renewal: when the letter comes, what to do, and a reminder ~9 weeks before expiry.
/// Single payment: explains that nothing happens automatically.
struct AdvRenewalReminderCard: View {
    let ticketID: UUID
    let ticketName: String
    let renewal: RenewalAdvice
    let family: TicketFamily
    let isMonthlyPayment: Bool
    var onEdit: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var scheduled: Date?
    @State private var isDenied = false
    /// The switch stays on while the permission prompt / scheduling is in flight.
    @State private var isScheduling = false
    @State private var successCount = 0

    init(ticketID: UUID, ticketName: String, renewal: RenewalAdvice, family: TicketFamily, isMonthlyPayment: Bool,
         onEdit: @escaping () -> Void) {
        self.ticketID = ticketID
        self.ticketName = ticketName
        self.renewal = renewal
        self.family = family
        self.isMonthlyPayment = isMonthlyPayment
        self.onEdit = onEdit
        // Screenshot mode shows the configured state (no permission prompt, no pending-request round trip).
        _scheduled = State(initialValue: LaunchMode.isScreenshot && renewal.autoRenews ? renewal.reminderDate : nil)
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if renewal.autoRenews {
                    automaticContent
                } else {
                    manualContent
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: scheduled)
        .animation(.smooth(duration: 0.3), value: isDenied)
        .sensoryFeedback(.success, trigger: successCount) { _, _ in app.settings.hapticsEnabled }
        .task(id: renewal.reminderDate) { await refresh() }
    }

    // MARK: Automatic (SEPA)

    @ViewBuilder
    private var automaticContent: some View {
        titleRow(symbol: "arrow.triangle.2.circlepath", color: Theme.dawn, title: "Automatische Verlängerung",
                 subtitle: "Per SEPA · nächstes Ticket ab \(Format.date(renewal.renewalStart, .long))")
        TktHairline().padding(.leading, TktStyle.rowPaddingH)
        Text(automaticExplanation)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TktStyle.rowPaddingH)
            .padding(.vertical, TktStyle.rowPaddingV)
        TktHairline().padding(.leading, TktStyle.rowPaddingH)
        if renewal.reminderDate > Date() {
            reminderToggle
            if isDenied {
                deniedNotice
                    .transition(.opacity)
            }
        } else {
            Label {
                Text(lateNotice)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: renewal.cancellationDeadline == nil ? "envelope.open.fill" : "calendar.badge.exclamationmark")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.summitText)
            .padding(.horizontal, TktStyle.rowPaddingH)
            .padding(.vertical, TktStyle.rowPaddingV)
        }
    }

    /// Less than 9 weeks before expiry: what to do now instead of a reminder.
    private var lateNotice: String {
        let today = Calendar.vienna.startOfDay(for: Date())
        if let deadline = renewal.cancellationDeadline {
            if deadline >= today { return "Die Frist läuft: Kündige bis \(Format.date(deadline, .long)), wenn du nicht verlängern willst." }
            return "Die Kündigungsfrist ist vorbei – dein Ticket verlängert sich am \(Format.date(renewal.renewalStart, .long))."
        }
        if let letter = renewal.letterDate, letter > today {
            return "Dein Verlängerungsbrief kommt um den \(Format.date(letter, .long)) – prüf dann die Frist darin."
        }
        return "Der Brief sollte schon da sein – prüf die Frist darin."
    }

    private var automaticExplanation: String {
        if let deadline = renewal.cancellationDeadline {
            return "Kündige spätestens bis \(Format.date(deadline, .long)) – einen Monat vor Ablauf –, sonst verlängert sich dein Ticket um 12 Monate."
        }
        if let letter = renewal.letterDate {
            return "Dein Verlängerungsbrief kommt um den \(Format.date(letter, .long)). Willst du nicht verlängern, widersprich schriftlich bis zur Frist, die im Brief steht – sonst läuft dein Ticket 12 Monate weiter."
        }
        return "Kündige rechtzeitig vor Ablauf, sonst verlängert sich dein Ticket automatisch. Die genaue Frist nennt dir dein Verkehrsverbund."
    }

    private var reminderToggle: some View {
        Toggle(isOn: Binding(get: { scheduled != nil || isScheduling }, set: { setReminder($0) })) {
            HStack(spacing: Theme.Spacing.s) {
                TktIconTile(symbol: "bell.badge.fill", color: Theme.glacier)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erinnere mich am \(Format.date(renewal.reminderDate))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reminderSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
    }

    private var reminderSubtitle: String {
        if renewal.cancellationDeadline != nil { return "2 Wochen vor der Kündigungsfrist · 9:00 Uhr" }
        return "9 Wochen vor Ablauf, bevor der Brief kommt · 9:00 Uhr"
    }

    private var deniedNotice: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "bell.slash.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.summitText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Mitteilungen sind ausgeschaltet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Erlaube Mitteilungen für KlimaBilanz, damit die Erinnerung ankommt.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
        .background(Theme.dawn.opacity(0.09))
    }

    // MARK: Manual (single payment)

    @ViewBuilder
    private var manualContent: some View {
        titleRow(symbol: "banknote.fill", color: Theme.glacier, title: "Verlängert sich nicht von selbst",
                 subtitle: renewal.isExpired ? "Abgelaufen am \(Format.date(renewal.expiry, .long))"
                                             : "Gültig bis \(Format.date(renewal.expiry, .long))")
        TktHairline().padding(.leading, TktStyle.rowPaddingH)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(manualExplanation)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if isMonthlyPayment {
                AdvNote(symbol: "info.circle",
                        text: "Mit Monatsraten zahlst du per SEPA – dann verlängert sich dein KlimaTicket in der Regel automatisch.")
            }
            Button(action: onEdit) {
                Label("Zahlst du per SEPA? Im Ticket einstellen", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
    }

    private var manualExplanation: String {
        if family == .oe {
            return "Rund 2 Monate vor Ablauf bekommst du einen Zahlschein. Verlängert wird nur, wenn du ihn einzahlst oder im Kundenkonto auf „Karte erneuern“ tippst. Tust du nichts, endet dein Ticket einfach."
        }
        return "Ohne Abbuchungsauftrag endet dein Ticket mit Ablauf. Für ein Folgeticket bestellst du einfach neu."
    }

    // MARK: Building blocks

    private func titleRow(symbol: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            TktIconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func refresh() async {
        guard !LaunchMode.isScreenshot else { return }
        let pending = await AdvReminder.scheduledDate(ticketID: ticketID)
        // Validity or rules changed since scheduling → move the reminder to the new date.
        if let pending, renewal.autoRenews, abs(pending.timeIntervalSince(renewal.reminderDate)) > 60 {
            let outcome = await AdvReminder.schedule(ticketID: ticketID, ticketName: ticketName, renewal: renewal)
            apply(outcome)
            return
        }
        if pending != nil, !renewal.autoRenews {
            AdvReminder.cancel(ticketID: ticketID)
            scheduled = nil
            return
        }
        scheduled = pending
    }

    private func setReminder(_ isOn: Bool) {
        if isOn {
            guard !isScheduling else { return }
            isScheduling = true
            Task {
                let outcome = await AdvReminder.schedule(ticketID: ticketID, ticketName: ticketName, renewal: renewal)
                isScheduling = false
                apply(outcome)
                if case .scheduled(let date) = outcome {
                    successCount += 1
                    app.showToast("bell.badge.fill", "Erinnerung geplant", "am \(Format.date(date, .long)) um 9:00 Uhr")
                }
            }
        } else {
            AdvReminder.cancel(ticketID: ticketID)
            scheduled = nil
            isDenied = false
        }
    }

    private func apply(_ outcome: AdvReminder.Outcome) {
        switch outcome {
        case .scheduled(let date):
            scheduled = date
            isDenied = false
        case .denied:
            scheduled = nil
            isDenied = true
        case .past:
            scheduled = nil
        }
    }
}
