import SwiftUI
import KlimaCore

/// Step 4 – "12 Fahrten importiert": value, effect on the current ticket year, what was skipped, and undo.
struct RepImportResultStep: View {
    let model: RepImportModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var summary: RepImportSummary? { model.summary }
    private var animates: Bool { !(reduceMotion || LaunchMode.isScreenshot) }

    var body: some View {
        hero
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.l)

        if model.isUndone {
            undoneCard
        } else if let summary {
            if let before = summary.before, let after = summary.after, after > before + 0.0001 {
                impactCard(before: before, after: after, year: summary.ticketYear)
            }
            detailsCard(summary)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle()
                    .fill((model.isUndone ? Theme.textTertiary : Theme.pine).opacity(0.16))
                    .frame(width: 118, height: 118)
                    .scaleEffect(appeared ? 1 : 0.6)
                Circle()
                    .fill(model.isUndone ? AnyShapeStyle(Theme.textTertiary.gradient) : AnyShapeStyle(Theme.pine.gradient))
                    .frame(width: 82, height: 82)
                    .shadow(color: (model.isUndone ? Color.black : Theme.pine).opacity(0.28), radius: 16, y: 8)
                Image(systemName: model.isUndone ? "arrow.uturn.backward" : "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: model.importRevision)
            }
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)

            if model.isUndone {
                Text("Import rückgängig gemacht")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Deine Fahrten sind wieder genau wie vorher.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            } else if let summary {
                Text("\(summary.imported)")
                    .font(.system(size: 88, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(summary.imported)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.bottom, -Theme.Spacing.xs)
                Text(summary.imported == 1 ? "Fahrt importiert" : "Fahrten importiert")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Format.euroPrecise(summary.value)) Fahrtenwert")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.positiveText)
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !appeared else { return }
            if animates {
                withAnimation(.spring(duration: 0.7, bounce: 0.35)) { appeared = true }
            } else {
                appeared = true
            }
        }
    }

    // MARK: Cards

    private func impactCard(before: Double, after: Double, year: String?) -> some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: year.map { "Ticketjahr \($0)" } ?? "Dein Ticket")
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(Format.percent(before))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                    Text(Format.percent(after))
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.textPrimary)
                    Text("amortisiert")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                ProgressRail(progress: before, preview: after,
                             leadingLabel: "vorher \(Format.percent(before))",
                             trailingLabel: after >= 1 ? "Gipfel erreicht ⚑" : "+ \(Format.number((after - before) * 100, decimals: 1)) Prozentpunkte")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation von \(Format.percent(before)) auf \(Format.percent(after)) gestiegen")
    }

    private func detailsCard(_ summary: RepImportSummary) -> some View {
        let lines = detailLines(summary)
        return Group {
            if !lines.isEmpty {
                GlassCard(padding: Theme.Spacing.m) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ForEach(lines, id: \.title) { line in
                            RepFeatureRow(symbol: line.symbol, tint: line.tint, title: line.title, message: line.message)
                        }
                    }
                }
            }
        }
    }

    private struct DetailLine { var symbol: String; var tint: Color; var title: String; var message: String }

    private func detailLines(_ s: RepImportSummary) -> [DetailLine] {
        var lines: [DetailLine] = []
        if s.estimated > 0 {
            lines.append(DetailLine(symbol: "wand.and.stars", tint: Theme.dusk,
                                    title: s.estimated == 1 ? "1 Preis geschätzt" : "\(s.estimated) Preise geschätzt",
                                    message: "ÖBB-Normalpreis wie beim Erfassen – du kannst jede Fahrt antippen und anpassen."))
        }
        if s.duplicatesSkipped > 0 {
            lines.append(DetailLine(symbol: "doc.on.doc.fill", tint: Theme.gold,
                                    title: s.duplicatesSkipped == 1 ? "1 Duplikat übersprungen" : "\(s.duplicatesSkipped) Duplikate übersprungen",
                                    message: "Diese Fahrten hattest du schon erfasst."))
        }
        if s.invalidSkipped > 0 {
            lines.append(DetailLine(symbol: "exclamationmark.triangle.fill", tint: Theme.negative,
                                    title: s.invalidSkipped == 1 ? "1 Zeile ausgelassen" : "\(s.invalidSkipped) Zeilen ausgelassen",
                                    message: "Datum, Strecke oder Preis waren nicht lesbar. Erfasse sie bei Bedarf von Hand."))
        }
        if s.outsideTicket > 0 {
            lines.append(DetailLine(symbol: "calendar.badge.exclamationmark", tint: Theme.glacier,
                                    title: s.outsideTicket == 1 ? "1 Fahrt außerhalb des Ticketjahrs" : "\(s.outsideTicket) Fahrten außerhalb des Ticketjahrs",
                                    message: "Sie zählen zu dem Ticket, in dessen Gültigkeit sie fallen."))
        }
        return lines
    }

    private var undoneCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            RepFeatureRow(symbol: "arrow.uturn.backward", tint: Theme.glacier, title: "Nichts verloren",
                          message: "Die Datei bleibt unverändert. Du kannst sie jederzeit erneut importieren.")
        }
    }
}
