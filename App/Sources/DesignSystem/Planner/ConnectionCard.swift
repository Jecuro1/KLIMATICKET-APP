import SwiftUI
import KlimaCore

/// The price part of a card: nothing yet, the offline value with a shimmer while the live one is on its way, or the
/// final quote.
struct PlannerPriceState: Equatable {
    var quote: PriceQuote?
    var isLoading = false
    /// The network is not available: a table price says so.
    var isOffline = false

    var badge: PriceSourceBadge.Source? {
        if isLoading { return .loading }
        return quote.map { PriceSourceBadge.Source(quote: $0, offline: isOffline) }
    }
}

/// One connection in the results list (UX §4.2, mock 11): times with realtime, duration, the journey bar, platform and
/// change line, the top notice, and the KlimaTicket footer („Mit KlimaTicket € 0 · Normalpreis € 29,70 LIVE“).
struct ConnectionCard: View {
    var summary: ConnectionSummary
    /// Plates of the ride legs (`LineBadge(line:)`), in order.
    var badges: [LineBadge] = []
    var coverage: JourneyCoverage?
    var ticketName: String
    var price: PlannerPriceState
    var priceText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                JourneyBar(segments: summary.bar, badges: badges)
                meta
                if let notice = summary.topNotice { NoticeRow(notice: notice) }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
            Divider().overlay(Theme.separator)
            ConnectionCardFooter(coverage: coverage, ticketName: ticketName, price: price)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card)
        .opacity(summary.isPast ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneyPresentation.accessibilityLabel(summary, priceText: priceText))
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            RealtimeTime(planned: summary.plannedDeparture, label: summary.departure, style: .card)
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text(summary.durationText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let tag = summary.tags.sorted(by: { $0.rawValue < $1.rawValue }).first {
                        Text(tag.title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.14), in: .capsule)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Capsule().fill(Theme.separator).frame(height: 1.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            RealtimeTime(planned: summary.plannedArrival, label: summary.arrival, style: .card, alignment: .trailing)
        }
    }

    private var meta: some View {
        Group {
            if let platform = summary.departurePlatform, summary.metaLine.hasPrefix("ab \(platform.text)") {
                Text("ab ").foregroundStyle(Theme.textSecondary)
                    + Text(platform.text).fontWeight(.bold).foregroundStyle(platform.changed ? Theme.summitText : Theme.textPrimary)
                    + Text(String(summary.metaLine.dropFirst(3 + platform.text.count))).foregroundStyle(Theme.textSecondary)
            } else {
                Text(summary.metaLine).foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 15.5))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// „Mit KlimaTicket € 0 · Normalpreis € 29,70 LIVE“ and its variants (docs/OEBB_LIVE.md §E3 card footer).
struct ConnectionCardFooter: View {
    var coverage: JourneyCoverage?
    var ticketName: String
    var price: PlannerPriceState

    var body: some View {
        // One line when it fits; otherwise the coverage text on top and the price below, right-aligned.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                leading.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: Theme.Spacing.xs)
                trailing.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 6) {
                leading
                HStack { Spacer(minLength: 0); trailing }
            }
        }
    }

    private var result: CoverageResult { coverage?.overall ?? .unknown }

    @ViewBuilder
    private var leading: some View {
        switch result {
        case .covered, .surcharge:
            HStack(spacing: 7) {
                Image(systemName: "ticket.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.positive)
                Text("Mit KlimaTicket € 0").font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                if result == .surcharge, let badge = coverage?.legs.compactMap(\.badge).first {
                    Text(badge).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.summitText)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.dawn.opacity(0.16), in: .capsule)
                        .lineLimit(1)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        case .partial:
            HStack(spacing: 7) {
                Image(systemName: "ticket").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.summitText)
                Text(partialText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        case .notCovered:
            HStack(spacing: 7) {
                Image(systemName: "ticket").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.negativeText)
                Text("Nicht im \(ticketName) enthalten").font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        case .discount:
            HStack(spacing: 7) {
                Image(systemName: "percent").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accentText)
                Text(coverage?.legs.compactMap(\.badge).first ?? "Ermäßigt").font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
        case .unknown, .notApplicable:
            HStack(spacing: 7) {
                Image(systemName: "questionmark.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Text("Gültigkeit prüfen").font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var partialText: String {
        if let name = coverage?.lastCoveredStopName { return "Gültig bis \(DisplayNames.name(name)) · danach Ticket nötig" }
        return "Teilweise gültig · danach Ticket nötig"
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let quote = price.quote {
                Text(Format.euroPrecise(quote.amountEUR))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(priceColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .redacted(reason: price.isLoading ? .placeholder : [])
            }
            if let badge = price.badge { PriceSourceBadge(source: badge, style: .tag) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .animation(MotionPolicy.animation(Motion.number), value: price.quote?.amountEUR)
    }

    private var label: String {
        switch result {
        case .notCovered: "Ticket"
        case .partial: "Teilstrecke"
        default: "Normalpreis"
        }
    }

    private var priceColor: Color {
        if price.quote?.isLive == true { return Theme.positiveText }
        return Theme.textPrimary
    }
}
