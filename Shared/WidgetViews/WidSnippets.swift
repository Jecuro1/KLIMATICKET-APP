import SwiftUI
import WidgetKit
import KlimaCore

// Siri / Shortcuts / Spotlight snippets (ShowBalanceIntent, LogFavoriteTripIntent). Shared because the quick-log intent
// also runs in the widget extension. The system draws the platter; these views only bring content, in the widgets'
// typography (thin numeral, eyebrow, route gradient) so an answer from Siri reads like the widget it came from.

/// "Hat sich mein KlimaTicket gelohnt?" – the balance at a glance.
struct WidBalanceSnippet: View {
    var snapshot: WidgetSnapshot?

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                WidSnippetEmpty()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func content(_ s: WidgetSnapshot) -> some View {
        let paid = WidInsight.isPaidOff(s)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidEyebrow(text: paid ? "Rentiert" : "Amortisiert",
                           symbol: paid ? "checkmark.seal.fill" : "mountain.2.fill",
                           tint: paid ? Theme.positive : Theme.accent)
                Spacer(minLength: 6)
                Text(WidInsight.validityText(s))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    WidPercentNumeral(fraction: s.amortizedFraction, size: 54)
                    WidVerdictLine(snapshot: s, size: 14)
                        .padding(.top, -4)
                }
                Spacer(minLength: 0)
                WidForecastBlock(snapshot: s, valueSize: 20)
                    .padding(.bottom, 2)
            }
            WidLinearBar(progress: s.amortizedFraction, fill: AnyShapeStyle(Theme.routeGradient),
                         track: AnyShapeStyle(Theme.textTertiary.opacity(0.35)))
                .frame(height: 6)
            Text(statsLine(s))
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation \(s.ticketName)")
        .accessibilityValue(WidInsight.spokenSummary(s))
    }

    /// "87 Fahrten · 4.812 km · 612 kg CO₂ gespart"
    private func statsLine(_ s: WidgetSnapshot) -> String {
        "\(WidFormat.trips(s.tripCount)) · \(WidFormat.km(s.distanceKm)) · \(WidFormat.kg(s.co2SavedKg)) CO₂ gespart"
    }
}

/// "✓ Pendeln erfasst" – the confirmation after logging a favourite by voice, Shortcut or Spotlight.
struct WidLoggedSnippet: View {
    var title: String
    var favorite: WidgetSnapshot.Favorite?
    var snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    WidModeBadge(symbol: favorite?.modeSymbol ?? "star.fill", size: 40)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Theme.positive)
                        .background(Circle().fill(Theme.background).padding(1))
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(title) erfasst")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // Up to two lines: beside "+ € 47,00" one line cut "St. Anton am Arlberg → Innsbruck Hbf" after
                    // the arrow – the destination is the part that matters.
                    Text(routeLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                if let favorite {
                    Text(verbatim: "+ " + WidFormat.euroPrecise(favorite.value))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.summitText)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let snapshot {
                HStack(spacing: 10) {
                    WidLinearBar(progress: snapshot.amortizedFraction, fill: AnyShapeStyle(Theme.routeGradient),
                                 track: AnyShapeStyle(Theme.textTertiary.opacity(0.35)))
                        .frame(height: 6)
                    Text(progressText(snapshot))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) erfasst")
        .accessibilityValue(spokenValue)
    }

    /// "St. Anton → Innsbruck Hbf" (short names, like the Live Activity) · "Heute, 07:42" for a favourite without stations.
    private var routeLine: String {
        let route = [favorite?.fromName ?? "", favorite?.toName ?? ""].map(RideNames.short).filter { !$0.isEmpty }
            .joined(separator: " → ")
        guard route.isEmpty else { return route }
        let time = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(WidFormat.locale))
        return "Heute, \(time)"
    }

    private func progressText(_ s: WidgetSnapshot) -> String {
        WidInsight.isPaidOff(s) ? "+ \(WidFormat.euroWhole(WidFigures.profit(s))) im Plus" : "\(WidFormat.percent(s.amortizedFraction)) amortisiert"
    }

    private var spokenValue: String {
        var parts: [String] = []
        if let favorite { parts.append("Wert \(WidFormat.euroPrecise(favorite.value))") }
        if let snapshot { parts.append(progressText(snapshot)) }
        return parts.joined(separator: ", ")
    }
}

/// No ticket yet (snippet).
private struct WidSnippetEmpty: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch kein Ticket")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(WidEmptyView.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
