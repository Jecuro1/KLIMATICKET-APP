import SwiftUI
import KlimaCore

/// "Ehrliche Bilanz": the payoff split into money really saved (trips you would have paid for) and extra value
/// (trips made only because of the ticket), with the honest payoff % next to the normal one.
struct MetaHonestBalanceCard: View {
    let snapshot: AnalyticsSnapshot
    let grow: Double

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title) private var compareSize: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var typeSize

    static let explanation = """
    Nicht jede Fahrt spart Geld. Fahrten, die du ohne KlimaTicket gar nicht gemacht hättest – der spontane Ausflug, der Besuch am Wochenende –, hättest du auch nie bezahlt. Sie sind echter Mehrwert, aber keine Ersparnis.

    Die ehrliche Bilanz zählt deshalb nur Fahrten, für die du sonst ein Ticket gekauft hättest. Laut KlimaTicket-Report des Mobilitätsministeriums (BMIMI) wären bis zu 8 % der KlimaTicket-Fahrten ohne Ticket gar nicht unternommen worden.
    """

    var body: some View {
        let balance = snapshot.metaHonestBalance
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                StatsCardHeader(kicker: "Ehrliche Bilanz", title: nil) {
                    StatsInfoButton(title: "Ehrliche Bilanz", text: Self.explanation)
                }
                .padding(.bottom, -Theme.Spacing.s)
                numerals(balance)
                Text(story(balance))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    rail(balance)
                    railLabels(balance)
                }
                legend(balance)
                verdict(balance)
                researchNote(balance)
            }
        }
        .metaScreenshotScrollTarget("statsHonest")
    }

    // MARK: Numerals

    @ViewBuilder
    private func numerals(_ balance: HonestBalance) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Theme.Spacing.l))
        layout {
            VStack(alignment: .leading, spacing: 0) {
                percentText(balance.honestFraction, size: heroSize, weight: .light, color: Theme.textPrimary)
                Text(balance.hasInducedTrips ? "ehrlich amortisiert" : "amortisiert – ehrlich gerechnet")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ehrlich amortisiert")
            .accessibilityValue(Format.percent(balance.honestFraction))
            if balance.hasInducedTrips {
                if !typeSize.isAccessibilitySize {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(width: 1, height: 48)
                        .padding(.bottom, 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    percentText(balance.amortizedFraction, size: compareSize, weight: .regular, color: Theme.textSecondary)
                    Text("mit allen Fahrten")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Amortisiert mit allen Fahrten")
                .accessibilityValue(Format.percent(balance.amortizedFraction))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "68 %" with a smaller percent sign.
    private func percentText(_ fraction: Double, size: CGFloat, weight: Font.Weight, color: Color) -> some View {
        let number = Format.percent(fraction).replacingOccurrences(of: " %", with: "")
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(number)
                .font(.system(size: size, weight: weight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: fraction))
            Text(verbatim: "%")
                .font(.system(size: size * 0.5, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func story(_ balance: HonestBalance) -> String {
        guard balance.hasInducedTrips else {
            return "Alle deine Fahrten hättest du sonst bezahlt – jeder Euro deiner Bilanz ist echte Ersparnis."
        }
        let trips = balance.inducedTripCount == 1 ? "Eine deiner \(balance.tripCount) Fahrten hättest" : "\(balance.inducedTripCount) deiner \(balance.tripCount) Fahrten hättest"
        let pronoun = balance.inducedTripCount == 1 ? "Sie ist" : "Sie sind"
        return "\(trips) du ohne KlimaTicket nicht gemacht. \(pronoun) \(Format.euro(balance.extraValue, decimals: 0)) Mehrwert – aber kein gespartes Geld."
    }

    // MARK: Rail

    private func rail(_ balance: HonestBalance) -> some View {
        let height: CGFloat = 12
        let scale = max(balance.totalValue, balance.ticketPrice, 1)
        return GeometryReader { geo in
            let width = geo.size.width
            let realWidth = width * CGFloat(balance.realSavings / scale * grow)
            let extraWidth = width * CGFloat(balance.extraValue / scale * grow)
            let priceX = min(width, width * CGFloat(balance.ticketPrice / scale))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.textTertiary.opacity(0.18))
                HStack(spacing: balance.extraValue > 0 && balance.realSavings > 0 ? 2 : 0) {
                    if balance.realSavings > 0 {
                        Rectangle()
                            .fill(LinearGradient(colors: [Theme.positive.mix(with: .white, by: 0.12), Theme.positive],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, realWidth))
                    }
                    if balance.extraValue > 0 {
                        Rectangle()
                            .fill(MetaCategoryStyle.inducedColor)
                            .overlay {
                                HatchShape(spacing: 5)
                                    .stroke(Theme.onAccent.opacity(0.5), lineWidth: 1.5)
                            }
                            .clipped()
                            .frame(width: max(0, extraWidth))
                    }
                }
                .frame(width: max(height, realWidth + extraWidth), alignment: .leading)
                .clipShape(Capsule())
                // Summit marker: the ticket price.
                Capsule()
                    .fill(Theme.summit)
                    .frame(width: 3, height: height + 10)
                    .overlay { Capsule().strokeBorder(Theme.onAccent.opacity(0.7), lineWidth: 0.5) }
                    .offset(x: priceX - 1.5)
            }
        }
        .frame(height: height)
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }

    private func railLabels(_ balance: HonestBalance) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Gesamtwert \(Format.euro(balance.totalValue, decimals: 0))")
            Spacer(minLength: Theme.Spacing.xs)
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Theme.summit)
                Text("Ticketpreis \(Format.euro(balance.ticketPrice, decimals: 0))")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityHidden(true)
    }

    // MARK: Legend

    private func legend(_ balance: HonestBalance) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            legendRow(title: "Echte Ersparnis",
                      detail: "\(StatsNames.trips(balance.realTripCount)), die du sonst bezahlt hättest",
                      value: balance.realSavings) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.positive)
            }
            if balance.hasInducedTrips {
                legendRow(title: "Mehrwert",
                          detail: "\(StatsNames.trips(balance.inducedTripCount)), die es ohne Ticket nicht gäbe",
                          value: balance.extraValue) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MetaCategoryStyle.inducedColor)
                        .overlay {
                            HatchShape(spacing: 4)
                                .stroke(Theme.onAccent.opacity(0.55), lineWidth: 1.2)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                }
            }
        }
    }

    private func legendRow<Swatch: View>(title: String, detail: String, value: Double,
                                         @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            swatch()
                .frame(width: 14, height: 14)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euro(value, decimals: 0))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Format.euro(value, decimals: 0)), \(detail)")
    }

    // MARK: Verdict & research

    @ViewBuilder
    private func verdict(_ balance: HonestBalance) -> some View {
        Group {
            if balance.isHonestlyPaidOff {
                Label {
                    Text("Auch ehrlich gerechnet rentiert · \(Text("+ \(Format.euro(balance.honestNet, decimals: 0))").foregroundStyle(Theme.positiveText)) echt gespart")
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
                }
                .foregroundStyle(Theme.textPrimary)
            } else if balance.isPaidOff {
                Label {
                    Text("Rentiert – ehrlich gerechnet fehlen noch \(Text(Format.euro(balance.remainingHonest, decimals: 0)).foregroundStyle(Theme.summitText))")
                } icon: {
                    Image(systemName: "flag.fill").foregroundStyle(Theme.summit)
                }
                .foregroundStyle(Theme.textPrimary)
            } else if balance.ticketPrice > 0 {
                Label {
                    Text("Noch \(Text(Format.euro(balance.remainingHonest, decimals: 0)).foregroundStyle(Theme.summitText)) echte Ersparnis bis zum Gipfel")
                } icon: {
                    Image(systemName: "flag.fill").foregroundStyle(Theme.summit)
                }
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func researchNote(_ balance: HonestBalance) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
            Label {
                Text(researchText(balance))
            } icon: {
                Image(systemName: balance.hasInducedTrips ? "chart.bar.doc.horizontal" : MetaCategoryStyle.inducedSymbol)
                    .foregroundStyle(balance.hasInducedTrips ? Theme.textTertiary : MetaCategoryStyle.inducedColor)
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.xxs)
    }

    private func researchText(_ balance: HonestBalance) -> String {
        let research = "Laut KlimaTicket-Report des Mobilitätsministeriums wären bis zu \(Format.percent(HonestBalance.researchInducedShare)) aller KlimaTicket-Fahrten ohne Ticket gar nicht passiert"
        if balance.hasInducedTrips {
            return "\(research) – bei dir sind es \(Format.percent(balance.inducedTripShare))."
        }
        return "\(research). Markiere solche Fahrten beim Erfassen mit „Ohne KlimaTicket wäre ich nicht gefahren“ – dann siehst du hier deine echte Ersparnis."
    }
}
