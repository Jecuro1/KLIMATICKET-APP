import SwiftUI
import WidgetKit
import KlimaCore

// Ticket widgets that need no network: the remaining validity, the break-even forecast and the year teaser. All read the
// widget snapshot (`WidgetSnapshot`), like the amortisation widget, and show the day counts of the entry's date.

// MARK: - Ticket-Restzeit

/// "noch 143 Tage": a gauge of the remaining validity on the lock screen, the number on the small home widget.
struct TicketRemainingWidgetView: View {
    var snapshot: WidgetSnapshot?
    var family: WidgetFamily
    var now: Date
    var margins: EdgeInsets = WidLayout.defaultMargins

    var body: some View {
        if let snapshot {
            content(snapshot)
        } else {
            WidEmptyView(family: family, margins: margins)
        }
    }

    @ViewBuilder
    private func content(_ s: WidgetSnapshot) -> some View {
        let days = WidInsight.daysRemaining(s, now: now)
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(max(days, 0), 365)), in: 0...365) {
                Text(verbatim: "Restzeit")
            } currentValueLabel: {
                Text(verbatim: "\(max(days, 0))")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel("Ticket-Restzeit")
            .accessibilityValue(WidInsight.validityText(s, now: now))
        case .accessoryInline:
            Label(WidInsight.validityText(s, now: now), systemImage: "ticket.fill")
        default:
            VStack(alignment: .leading, spacing: 2) {
                WidEyebrow(text: "Ticket-Restzeit", symbol: "ticket.fill")
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(max(days, 0))")
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text(verbatim: max(days, 0) == 1 ? "Tag" : "Tage")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.widSecondary)
                }
                Text(verbatim: "gültig bis \(WidFormat.dayMonth(s.validUntil))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Break-even

/// "Break-even am 14. Dez.": when the ticket has paid off by the current pace, or the profit once it has. The gauge is the
/// amortised share; the lock-screen circle shows it as a gauge.
struct BreakEvenWidgetView: View {
    var snapshot: WidgetSnapshot?
    var family: WidgetFamily
    var now: Date
    var margins: EdgeInsets = WidLayout.defaultMargins

    var body: some View {
        if let snapshot {
            content(snapshot)
        } else {
            WidEmptyView(family: family, margins: margins)
        }
    }

    @ViewBuilder
    private func content(_ s: WidgetSnapshot) -> some View {
        let forecast = WidInsight.forecast(s, now: now)
        let percent = WidFormat.percentValue(s.amortizedFraction)
        switch family {
        case .accessoryCircular:
            Gauge(value: min(max(s.amortizedFraction, 0), 1)) {
                Text(verbatim: "Break-even")
            } currentValueLabel: {
                Text(verbatim: "\(percent)")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel("Break-even")
            .accessibilityValue("\(WidFormat.percent(s.amortizedFraction)) amortisiert. \(forecast.kicker) \(forecast.value)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(forecast.kicker, systemImage: forecast.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(verbatim: "\(forecast.value) · \(forecast.caption)")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                WidLinearBar(progress: s.amortizedFraction)
                    .frame(height: 5)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .accessoryInline:
            Label("\(percent) % · \(forecast.kicker) \(forecast.value)", systemImage: "flag.fill")
                .lineLimit(1)
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidEyebrow(text: forecast.kicker, symbol: forecast.symbol,
                           tint: forecast.isPositive ? Theme.positive : Theme.accent)
                Text(verbatim: forecast.value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(verbatim: forecast.caption)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    WidMiniRing(fraction: s.amortizedFraction)
                        .frame(width: 26, height: 26)
                    Text(verbatim: "\(percent) % amortisiert")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.widSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Jahresrückblick

/// The year teaser: in December, or in the last 30 days of the ticket, the year's figures (trips, distance, CO₂ saved and
/// the value). At any other time the widget shows the countdown instead, so it is never empty.
struct YearReviewWidgetView: View {
    var snapshot: WidgetSnapshot?
    var family: WidgetFamily
    var now: Date
    var margins: EdgeInsets = WidLayout.defaultMargins

    var body: some View {
        if let snapshot {
            if WidgetYearReview.isVisible(now: now, validUntil: snapshot.validUntil) {
                review(snapshot)
            } else {
                countdown(snapshot)
            }
        } else {
            WidEmptyView(family: family, margins: margins)
        }
    }

    private func review(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidEyebrow(text: "Jahresrückblick", symbol: "sparkles")
            Text(verbatim: WidFormat.trips(s.tripCount))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(verbatim: "\(WidFormat.km(s.distanceKm)) · \(WidFormat.kg(s.co2SavedKg)) CO₂ gespart")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.widSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if family != .systemSmall {
                Text(verbatim: "Wert \(WidFormat.euroWhole(s.totalValue))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(verbatim: "Ticket-Zeitraum · \(s.ticketName)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func countdown(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidEyebrow(text: "Dein Ticket", symbol: "ticket.fill")
            Text(verbatim: WidInsight.validityText(s, now: now))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(verbatim: "Jahresrückblick ab Dezember")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.widSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
