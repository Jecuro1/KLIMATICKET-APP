import SwiftUI
import WidgetKit
import KlimaCore

/// "Hat sich mein Ticket schon rentiert?" – home-screen (small / medium / large) and lock-screen
/// (circular / rectangular / inline) designs. Shared by the widget extension and the in-app gallery,
/// so the family is passed in explicitly (`@Environment(\.widgetFamily)` is read only by the extension).
struct AmortizationWidgetView: View {
    var snapshot: WidgetSnapshot?
    var family: WidgetFamily
    /// Content margins (the extension passes the system's; the gallery uses the iPhone default).
    var margins: EdgeInsets = WidLayout.defaultMargins
    /// False in the in-app gallery: favourite buttons are shown but do not log anything.
    var isInteractive: Bool = true

    var body: some View {
        if let snapshot {
            content(for: snapshot)
        } else {
            WidEmptyView(family: family, margins: margins)
        }
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            WidAmortizationSmall(snapshot: snapshot, margins: margins)
        case .systemLarge:
            WidAmortizationLarge(snapshot: snapshot, margins: margins, isInteractive: isInteractive)
        case .accessoryCircular:
            WidAccessoryCircular(snapshot: snapshot)
        case .accessoryRectangular:
            WidAccessoryRectangular(snapshot: snapshot)
        case .accessoryInline:
            WidAccessoryInline(snapshot: snapshot)
        default:
            WidAmortizationMedium(snapshot: snapshot, margins: margins)
        }
    }
}

// MARK: - Home screen

/// Small: mini summit + "73 %" + "noch € 354".
private struct WidAmortizationSmall: View {
    let snapshot: WidgetSnapshot
    let margins: EdgeInsets

    var body: some View {
        let paid = WidInsight.isPaidOff(snapshot)
        ZStack(alignment: .topLeading) {
            WidSummitArt(model: WidSummitModel(snapshot: snapshot), top: 0.6, bottom: 0.97, scale: 0.82)
            VStack(alignment: .leading, spacing: 0) {
                WidEyebrow(text: paid ? "Rentiert" : "Amortisiert",
                           symbol: paid ? "checkmark.seal.fill" : "mountain.2.fill",
                           tint: paid ? Theme.positive : Theme.accent)
                WidPercentNumeral(fraction: snapshot.amortizedFraction, size: 50)
                WidVerdictLine(snapshot: snapshot, size: 13)
                    .padding(.top, -3)
                Spacer(minLength: 0)
            }
            .padding(margins)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation")
        .accessibilityValue(WidInsight.spokenSummary(snapshot))
    }
}

/// Medium: + break-even forecast and the value route climbing to the summit.
private struct WidAmortizationMedium: View {
    let snapshot: WidgetSnapshot
    let margins: EdgeInsets

    var body: some View {
        let paid = WidInsight.isPaidOff(snapshot)
        ZStack(alignment: .topLeading) {
            WidSummitArt(model: WidSummitModel(snapshot: snapshot), top: 0.5, bottom: 0.97, scale: 0.95)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    WidEyebrow(text: paid ? "Rentiert" : "Amortisiert",
                               symbol: paid ? "checkmark.seal.fill" : "mountain.2.fill",
                               tint: paid ? Theme.positive : Theme.accent)
                    WidPercentNumeral(fraction: snapshot.amortizedFraction, size: 56)
                    WidVerdictLine(snapshot: snapshot, size: 13.5, showsProfit: false)
                        .padding(.top, -3)
                }
                Spacer(minLength: 0)
                WidForecastBlock(snapshot: snapshot, valueSize: 21)
            }
            .padding(margins)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation")
        .accessibilityValue(WidInsight.spokenSummary(snapshot))
    }
}

/// Large: + ticket header, verdict in words, stats and one-tap favourites.
private struct WidAmortizationLarge: View {
    let snapshot: WidgetSnapshot
    let margins: EdgeInsets
    let isInteractive: Bool

    private var isPaidOff: Bool { WidInsight.isPaidOff(snapshot) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WidSummitArt(model: WidSummitModel(snapshot: snapshot), top: 0.43, bottom: 0.755, scale: 1.08,
                         todayLabel: "Heute", summitLabel: WidFormat.euroWhole(snapshot.ticketPrice),
                         mistFrom: 0.66, mistOpacity: 0.12)
            VStack(alignment: .leading, spacing: 0) {
                summaryBlock
                Spacer(minLength: 6)
                statsLine
                    .padding(.bottom, 9)
                favoritesRow
            }
            .padding(margins)
        }
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .bottom, spacing: 8) {
                WidPercentNumeral(fraction: snapshot.amortizedFraction, size: 66)
                Spacer(minLength: 0)
                WidForecastBlock(snapshot: snapshot, valueSize: 22)
                    .padding(.bottom, 12)
            }
            .padding(.top, 2)
            verdict
                .padding(.top, -4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation \(snapshot.ticketName)")
        .accessibilityValue(WidInsight.spokenSummary(snapshot))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .widgetAccentable()
            Text(snapshot.ticketName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(WidInsight.validityText(snapshot))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 2) {
            headline
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.widSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var headline: Text {
        if isPaidOff {
            let seal = Text(Image(systemName: "checkmark.seal.fill"))
                .foregroundStyle(Theme.positive)
            return Text("\(seal) Rentiert – jede Fahrt ist jetzt Gewinn")
        }
        let amount = Text(verbatim: WidFormat.euroWhole(snapshot.remaining))
            .fontWeight(.bold)
            .foregroundStyle(Theme.accentText)
        return Text("Noch \(amount) bis zum Break-even")
    }

    private var detail: String {
        if isPaidOff {
            return "\(WidFormat.euroWhole(snapshot.totalValue)) Wert · \(WidFormat.trips(snapshot.tripCount))"
        }
        return "\(WidFormat.euroWhole(snapshot.totalValue)) von \(WidFormat.euroWhole(snapshot.ticketPrice)) amortisiert"
    }

    private var statsLine: some View {
        HStack(spacing: 14) {
            stat(symbol: "tram.fill", value: WidFormat.number(Double(snapshot.tripCount)), label: "Fahrten", tint: Theme.accent)
            stat(symbol: "point.topleft.down.to.point.bottomright.curvepath", value: WidFormat.km(snapshot.distanceKm), label: nil, tint: Theme.dusk)
            stat(symbol: "leaf.fill", value: WidFormat.kg(snapshot.co2SavedKg), label: "CO₂", tint: Theme.pine)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(symbol: String, value: String, label: String?, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let label {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.widSecondary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var favoritesRow: some View {
        let favorites = Array(snapshot.favorites.prefix(2))
        if favorites.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .widgetAccentable()
                Text("Lege Favoriten an, um hier mit einem Tipp zu erfassen.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.widSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.surface))
        } else {
            HStack(spacing: 8) {
                ForEach(favorites) { favorite in
                    WidFavoriteButton(favorite: favorite, isInteractive: isInteractive)
                }
            }
        }
    }
}

// MARK: - Lock screen

/// Circular capacity gauge with the mountain glyph.
private struct WidAccessoryCircular: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let fraction = snapshot.amortizedFraction.isFinite ? snapshot.amortizedFraction : 0
        Gauge(value: min(max(fraction, 0), 1)) {
            Text("Amortisiert")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Image(systemName: WidInsight.isPaidOff(snapshot) ? "flag.fill" : "mountain.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: String(WidFormat.percentValue(fraction)))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation")
        .accessibilityValue(WidInsight.spokenSummary(snapshot))
    }
}

/// "73 % · noch € 354" with a slim progress bar.
private struct WidAccessoryRectangular: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let paid = WidInsight.isPaidOff(snapshot)
        let title: String = paid ? "Rentiert" : "Amortisation"
        let detail: String = paid ? "+ \(WidFormat.euroWhole(snapshot.net))" : "noch \(WidFormat.euroWhole(snapshot.remaining))"
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: "mountain.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(WidFormat.percent(snapshot.amortizedFraction))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 13.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            WidLinearBar(progress: snapshot.amortizedFraction)
                .frame(height: 5)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation")
        .accessibilityValue(WidInsight.spokenSummary(snapshot))
    }
}

/// "⛰ 73 % rentiert" above the clock.
private struct WidAccessoryInline: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let text: String = WidInsight.isPaidOff(snapshot)
            ? "Rentiert · + \(WidFormat.euroWhole(snapshot.net))"
            : "\(WidFormat.percent(snapshot.amortizedFraction)) rentiert"
        Label {
            Text(text)
        } icon: {
            Image(systemName: "mountain.2.fill")
        }
        .accessibilityLabel("Amortisation: \(WidInsight.spokenSummary(snapshot))")
    }
}
