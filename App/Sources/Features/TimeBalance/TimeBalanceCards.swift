import SwiftUI
import KlimaCore

// MARK: - Car

/// „Im Auto wärst du 96 Std. selbst gefahren“ – the Auto-Vergleich's figure for the same trips, the two bars, and the
/// honest verdict (longer rides are „Mehrzeit“, never „Zeit gespart“).
struct TimeBalanceCarCard: View {
    let balance: TimeBalance

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let verdict = TimeBalanceText.verdict(balance.carVerdict)
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsCardHeader(kicker: "Öffis vs. Auto · Zeit", title: TimeBalanceText.carSentence(balance.carMinutes)) { EmptyView() }
                StatsGrowOnView(delay: Motion.Stagger.delay(3)) { grow in
                    VStack(spacing: Theme.Spacing.s) {
                        bar(symbol: "tram.fill", label: "In Bahn & Bus", minutes: balance.totalMinutes, color: Theme.glacier, grow: grow)
                        bar(symbol: "car.fill", label: "Selbst am Steuer", minutes: balance.carMinutes, color: Theme.remaining, grow: grow)
                    }
                }
                if let verdict {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        Image(systemName: verdict.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(verdict.isGain ? Theme.positive : Theme.dusk)
                            .frame(width: 34, height: 34)
                            .background((verdict.isGain ? Theme.positive : Theme.dusk).opacity(0.14), in: .circle)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verdict.title)
                                .font(.headline)
                                .foregroundStyle(verdict.isGain ? Theme.positiveText : Theme.textPrimary)
                                .contentTransition(.numericText())
                            Text(verdict.detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceSecondary.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                }
                Text("Auto: dieselben Fahrten mit Durchschnittstempo, ohne Stau und Parkplatzsuche – derselbe Wert wie im Auto-Vergleich.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(verdict))
        .accessibilityIdentifier("timeBalance.car")
    }

    private func spoken(_ verdict: TimeBalanceText.Verdict?) -> String {
        var text = "Öffis gegen Auto. In Bahn und Bus \(TimeBalanceText.spoken(balance.totalMinutes)). "
            + "Im Auto wärst du \(TimeBalanceText.spoken(balance.carMinutes)) selbst gefahren."
        if let verdict { text += " \(verdict.title). \(verdict.detail)" }
        return text
    }

    private func bar(symbol: String, label: String, minutes: Double, color: Color, grow: Double) -> some View {
        let top = max(balance.totalMinutes, balance.carMinutes, 1)
        return VStack(alignment: .leading, spacing: 5) {
            if typeSize.isAccessibilitySize {
                Label(label, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(TimeBalanceText.short(minutes))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .frame(width: 18)
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(TimeBalanceText.short(minutes))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                }
            }
            ProgressRail(progress: minutes / top * grow, height: 8, fill: AnyShapeStyle(color))
        }
    }
}

// MARK: - Delays

/// „Verspätungen: 3,5 Std. verloren“ – only when at least one trip of the period has a recorded delay.
struct TimeBalanceDelayCard: View {
    let delays: TimeBalanceDelays
    let tripCount: Int

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2, tint: Theme.dawn) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.summitText)
                    .frame(width: 44, height: 44)
                    .background(Theme.dawn.opacity(0.16), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Kicker(text: "Verspätungen")
                    Text(TimeBalanceText.delayTitle(delays))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(TimeBalanceText.delayDetail(delays, tripCount: tripCount))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Nicht in den Stunden oben eingerechnet.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeBalance.delays")
    }
}

// MARK: - Facts

/// Longest single trip and the weekly average – two tiles, stacked at the accessibility sizes.
struct TimeBalanceFactsRow: View {
    let balance: TimeBalance

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
        layout {
            if let longest = balance.longest {
                tile(symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.dusk, kicker: "Längste Fahrt",
                     value: TimeBalanceText.clock(longest.minutes),
                     detail: "\(longest.fromName) → \(longest.toName) · \(Format.dayMonth(longest.date))",
                     badge: longest.isEstimated ? "geschätzt" : nil,
                     spoken: "Längste Fahrt: \(TimeBalanceText.spoken(longest.minutes, exact: true)), \(longest.fromName) nach \(longest.toName), \(Format.dayMonth(longest.date))\(longest.isEstimated ? ", geschätzt" : "")")
            }
            tile(symbol: "calendar", tint: Theme.pine, kicker: "Ø pro Woche",
                 value: TimeBalanceText.short(balance.averageMinutesPerWeek),
                 detail: weeksDetail, badge: nil,
                 spoken: "Im Schnitt \(TimeBalanceText.spoken(balance.averageMinutesPerWeek)) pro Woche, \(weeksDetail)")
        }
    }

    private var weeksDetail: String {
        let weeks = balance.weeksElapsed
        return weeks < 1.5 ? "in der ersten Woche" : "über \(Format.number(weeks.rounded(.down))) Wochen"
    }

    private func tile(symbol: String, tint: Color, kicker: String, value: String, detail: String, badge: String?, spoken: String) -> some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.14), in: .circle)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                }
                Kicker(text: kicker)
                Text(value)
                    .font(Theme.Typography.numberMedium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Modes

/// Share of the time per transport mode – directly labelled horizontal bars (DESIGN.md §5.4), icon + name, never colour alone.
struct TimeBalanceModesCard: View {
    let balance: TimeBalance

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let top = balance.modes.first?.minutes ?? 1
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsCardHeader(kicker: "Nach Verkehrsmittel", title: headline) { EmptyView() }
                StatsGrowOnView { grow in
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(balance.modes) { share in
                            row(share, fraction: share.minutes / max(top, 1) * grow)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("timeBalance.modes")
    }

    private var headline: String {
        guard let first = balance.modes.first else { return "" }
        return "Am meisten Zeit: \(first.mode.displayName) mit \(Format.percent(first.share))"
    }

    private func row(_ share: TimeBalanceModeShare, fraction: Double) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: share.mode, size: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if typeSize.isAccessibilitySize {
                    Text(share.mode.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(figure(share)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                } else {
                    HStack {
                        Text(share.mode.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(figure(share)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    }
                }
                ProgressRail(progress: fraction, height: 6, fill: AnyShapeStyle(Theme.modeColor(share.mode)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(share.mode.displayName): \(TimeBalanceText.spoken(share.minutes)), \(Format.percent(share.share))")
    }

    private func figure(_ share: TimeBalanceModeShare) -> String {
        "\(TimeBalanceText.short(share.minutes)) · \(Format.percent(share.share))"
    }
}
