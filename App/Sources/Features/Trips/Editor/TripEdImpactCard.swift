import SwiftUI
import SwiftData
import KlimaCore

/// "Wirkung": what this trip does to the active ticket – "Danach 77 % amortisiert", "+ € 47,00", the
/// rail with the new segment glowing/striped on top of the current progress, "73 → 77 % · + 3,8 %" and the
/// summit price. The new segment grows in on appear and follows every change of the form.
struct TripEdImpactCard: View {
    let model: TripEditorModel

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @State private var revealed = false

    var body: some View {
        if let impact = currentImpact {
            SurfaceCard(padding: 14, cornerRadius: Theme.Radius.formGroup) {
                content(impact)
            }
            .onAppear { reveal() }
        }
    }

    // MARK: Model

    private struct Impact {
        var before: Double
        var after: Double
        var added: Double
        var price: Double
        var inPeriod: Bool
        /// Editing: `before` is the ticket without this trip, `added` its (new) full value.
        var isEditing: Bool

        var delta: Double { max(0, after - before) }
        var isPaidOffAlready: Bool { before >= 1 }
        var reachesSummit: Bool { before < 1 && after >= 1 }
    }

    private var currentImpact: Impact? {
        // The other trips are summed once per sheet (TripEditorModel.tripEdBaseline); the trip this sheet saves stays out.
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID),
              let fractions = model.tripEdImpact(ticket: ticket, context: context) else { return nil }
        return Impact(before: fractions.before,
                      after: fractions.after,
                      added: model.totalValue,
                      price: fractions.price,
                      inPeriod: fractions.inPeriod,
                      isEditing: model.isEditing)
    }

    // MARK: Layout

    private func content(_ impact: Impact) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(title(impact))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: impact.after))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.xs)
                if impact.inPeriod && impact.added > 0 {
                    Text(impact.isEditing ? Format.euroPrecise(impact.added) : TripEdFormat.plusEuro(impact.added))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.summitText)
                        .contentTransition(.numericText(value: impact.added))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            rail(impact)
            HStack(spacing: Theme.Spacing.xs) {
                Text(footnote(impact))
                    .contentTransition(.numericText(value: impact.after))
                Spacer(minLength: Theme.Spacing.xs)
                HStack(spacing: 3) {
                    if impact.reachesSummit {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(Theme.summitText)
                            .motionTransition(.pop)
                    }
                    Text("Gipfel " + Format.euro(impact.price))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        // The new segment and the percentages settle calmly; the euro amount follows the price like the save button.
        .motionAnimation(Motion.gentle, value: impact.after)
        .motionAnimation(Motion.number, value: impact.added)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wirkung auf die Amortisation")
        .accessibilityValue(spokenValue(impact))
    }

    private func title(_ impact: Impact) -> String {
        if !impact.inPeriod { return "Außerhalb deines Ticketzeitraums" }
        if impact.isPaidOffAlready { return "Schon rentiert – reiner Gewinn" }
        if impact.added <= 0 { return "Aktuell \(Format.percent(impact.before)) amortisiert" }
        if impact.reachesSummit { return "Damit ist dein Ticket rentiert!" }
        if impact.isEditing { return "Mit dieser Fahrt \(Format.percent(impact.after)) amortisiert" }
        return "Danach \(Format.percent(impact.after)) amortisiert"
    }

    private func footnote(_ impact: Impact) -> String {
        if !impact.inPeriod { return "Zählt nicht zur Bilanz dieses Tickets" }
        if impact.isPaidOffAlready {
            return "Gewinn danach " + TripEdFormat.plusEuro((impact.after - 1) * impact.price)
        }
        if impact.added <= 0 { return "Vorschau, sobald der Preis feststeht" }
        if impact.isEditing { return "Ohne diese Fahrt \(Format.percent(impact.before))" }
        var text = "\(Format.number(impact.before * 100)) → \(Format.percent(impact.after))"
        if impact.delta > 0 { text += " · + \(Format.number(impact.delta * 100, decimals: 1)) %" }
        return text
    }

    private func spokenValue(_ impact: Impact) -> String {
        if !impact.inPeriod { return "Die Fahrt liegt außerhalb des Ticketzeitraums und zählt nicht zur Bilanz." }
        var text = "Von \(Format.percent(impact.before)) auf \(Format.percent(impact.after)) amortisiert"
        if impact.added > 0 { text += ", plus \(Format.euroPrecise(impact.added))" }
        if impact.reachesSummit { text += ". Damit ist das Ticket rentiert." }
        return text
    }

    // MARK: Rail

    private func rail(_ impact: Impact) -> some View {
        let before = min(max(impact.before, 0), 1)
        let target = min(max(impact.after, 0), 1)
        let shown = revealed ? target : before
        let height: CGFloat = 10
        // Crossing the summit with this trip turns the new segment gold (DESIGN_FINAL_SYNTHESIS §8.14).
        let segmentColor = impact.reachesSummit ? Theme.gold : Theme.dawn
        return GeometryReader { geo in
            let width = geo.size.width
            // The segment always exists and only changes width, so it grows out of the current fill instead of
            // fading in at full length; it starts under the fill's rounded end, so its glow stays on the new part.
            let start = max(0, width * before - height)
            let end = max(start + height, width * shown)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.18))
                newSegment(color: segmentColor)
                    .frame(width: end - start)
                    .offset(x: start)
                    .opacity(shown > before + 0.0005 ? 1 : 0)
                Capsule()
                    .fill(impact.isPaidOffAlready ? AnyShapeStyle(Theme.positive) : AnyShapeStyle(progressFill))
                    .frame(width: max(height, width * before))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Current progress: glacier → dusk (the new segment is the dawn-coloured part beyond it).
    private var progressFill: LinearGradient {
        LinearGradient(colors: [Theme.glacier, Theme.dusk], startPoint: .leading, endPoint: .trailing)
    }

    /// The value this trip adds: dawn (gold at the summit), diagonally striped, softly glowing.
    private func newSegment(color: Color) -> some View {
        Capsule()
            .fill(color)
            .overlay {
                HatchShape(spacing: 5)
                    .stroke(Theme.onAccent.opacity(0.45), lineWidth: 1.5)
                    .clipShape(Capsule())
            }
            .shadow(color: color.opacity(0.55), radius: 6)
    }

    /// The new segment grows out of today's fill once, after the sheet has settled.
    private func reveal() {
        guard !revealed else { return }
        withMotion(Motion.gentle.delay(0.35)) { revealed = true }
    }
}
