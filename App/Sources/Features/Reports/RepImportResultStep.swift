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
            .padding(.top, Theme.Spacing.xs)

        if model.isUndone {
            undoneCard
        } else if let summary {
            if let before = summary.before, let after = summary.after, after > before + 0.0001 {
                impactCard(before: before, after: after, year: summary.ticketYear, price: summary.ticketPrice)
            }
            detailsCard(summary)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle()
                    .fill((model.isUndone ? Theme.textTertiary : Theme.pine).opacity(0.16))
                    .frame(width: 84, height: 84)
                    .scaleEffect(appeared ? 1 : 0.6)
                Circle()
                    .fill(model.isUndone ? AnyShapeStyle(Theme.textTertiary.gradient) : AnyShapeStyle(Theme.pine.gradient))
                    .frame(width: 60, height: 60)
                    .shadow(color: (model.isUndone ? Color.black : Theme.pine).opacity(0.28), radius: 16, y: 8)
                Image(systemName: model.isUndone ? "arrow.uturn.backward" : "checkmark")
                    .font(.system(size: 26, weight: .bold))
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
                    .font(.system(size: 68, weight: .thin, design: .rounded))
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

    private func impactCard(before: Double, after: Double, year: String?, price: Double?) -> some View {
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
                RepImpactRail(before: before, after: after)
                    .frame(height: 10)
                HStack {
                    if let price, price > 0 {
                        Text("Gipfel \(Format.euro(price, decimals: 0))")
                    }
                    Spacer()
                    Label(after >= 1 ? "Gipfel erreicht" : "+ \(Format.number((after - before) * 100, decimals: 1)) Prozentpunkte",
                          systemImage: after >= 1 ? "flag.fill" : "arrow.up.right")
                        .labelStyle(RepCompactLabelStyle())
                        .foregroundStyle(Theme.positiveText)
                }
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
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

/// Amortisation bar for the import result: what was there (route gradient) plus what the import added (pine),
/// scaled so that values beyond 100 % still fit; a summit tick marks the ticket price.
struct RepImpactRail: View {
    var before: Double
    var after: Double

    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let scale = max(1, after)
            let beforeW = max(h, w * CGFloat(min(max(before, 0), scale) / scale))
            let afterW = max(beforeW, w * CGFloat(min(max(after, 0), scale) / scale))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textTertiary.opacity(0.18))
                Capsule().fill(Theme.pine)
                    .frame(width: grown ? afterW : beforeW)
                Capsule().fill(Theme.routeGradient)
                    .frame(width: beforeW)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Theme.sheetBackground).frame(width: 2)
                    }
                    .clipShape(Capsule())
                if scale > 1 {
                    Rectangle().fill(Theme.summit)
                        .frame(width: 2, height: h + 6)
                        .offset(x: w / CGFloat(scale) - 1)
                }
            }
        }
        .onAppear {
            guard !grown else { return }
            if reduceMotion || LaunchMode.isScreenshot {
                grown = true
            } else {
                withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(0.25)) { grown = true }
            }
        }
        .accessibilityHidden(true)
    }
}
