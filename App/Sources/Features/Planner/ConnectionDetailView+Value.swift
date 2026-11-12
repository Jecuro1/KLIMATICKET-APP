import SwiftUI
import KlimaCore

// The value card, the timeline card and the footer of the connection detail (split from ConnectionDetailView.swift).

extension ConnectionDetailView {
    // MARK: Value

    func valueCard(_ row: ConnectionRow, amount: Double?, model: PlannerModel) -> some View {
        let coverage = row.coverage?.overall ?? .unknown
        let snapshot = valueSnapshot(extra: counts(coverage) ? amount : nil)
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    Image(systemName: coverage == .notCovered ? "ticket" : "ticket.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(coverage == .notCovered ? Theme.negativeText : Theme.positive)
                        .frame(width: 52, height: 52)
                        .background((coverage == .notCovered ? Theme.negative : Theme.positive).opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let amount {
                                Text(Format.euroPrecise(amount))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(coverage == .notCovered ? Theme.textPrimary : Theme.positiveText)
                                    .numericValue(amount)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Text(valueCaption(coverage)).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        HStack(spacing: 6) {
                            Text("Normalpreis").font(.system(size: 15)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            if let badge = price.badge ?? row.price.badge { PriceSourceBadge(source: badge) }
                            if let quote = price.quote ?? row.price.quote {
                                Button { showsPriceInfo = true } label: {
                                    Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                                        .frame(width: 32, height: 32).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Woher kommt der Preis?")
                                .popover(isPresented: $showsPriceInfo) { PriceInfoPopover(quote: quote).presentationCompactAdaptation(.popover) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let note = valueNote(row, coverage: coverage) {
                    Text(note).font(.system(size: 15)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let snapshot {
                    Divider().overlay(Theme.separator)
                    HStack {
                        Text("Amortisiert").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        HStack(spacing: 5) {
                            Text(Format.percent(snapshot.before)).foregroundStyle(Theme.textSecondary)
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textTertiary)
                            Text(Format.percent(snapshot.after)).foregroundStyle(Theme.accentText)
                        }
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The honest note under the price: where the ticket stops, why a price needs a check.
    private func valueNote(_ row: ConnectionRow, coverage: CoverageResult) -> String? {
        switch coverage {
        case .partial:
            if let name = row.coverage?.lastCoveredStopName { return "Dein Ticket gilt bis \(DisplayNames.name(name)) – nur dieser Teil wird bewertet. Danach brauchst du ein Ticket." }
            return "Dein Ticket gilt nur auf einem Teil der Strecke – nur dieser Teil wird bewertet."
        case .notCovered: return "Nicht im \(app.planner.ticketName) enthalten – für diese Fahrt brauchst du ein Ticket."
        case .unknown, .notApplicable: return "Ob dein Ticket hier gilt, lässt sich nicht sicher sagen – bitte prüfen."
        case .discount: return row.coverage?.legs.compactMap(\.badge).first
        default: return nil
        }
    }

    private func counts(_ coverage: CoverageResult) -> Bool { coverage == .covered || coverage == .surcharge || coverage == .partial }

    private func valueCaption(_ coverage: CoverageResult) -> String {
        switch coverage {
        case .covered, .surcharge, .partial: "gespart"
        case .notCovered: "Ticket nötig"
        default: "Normalpreis"
        }
    }

    private struct ValueSnapshot { var before: Double; var after: Double }

    /// Amortisation before and after this connection counts (only with a ticket and a price that counts).
    private func valueSnapshot(extra: Double?) -> ValueSnapshot? {
        guard let extra, extra > 0, let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return nil }
        let summary = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog).summary
        guard summary.ticketPrice > 0 else { return nil }
        return ValueSnapshot(before: summary.amortizedFraction, after: (summary.totalValue + extra) / summary.ticketPrice)
    }

    func displayQuote(_ row: ConnectionRow) -> Double? {
        (price.quote ?? row.price.quote)?.amountEUR
    }

    // MARK: Timeline

    func timelineCard(_ row: ConnectionRow) -> some View {
        TimelineList(journey: row.journey, summary: row.summary, expanded: $expanded)
            .padding(Theme.Spacing.m)
            .frostedCard(cornerRadius: Theme.Radius.card)
    }

    func journeyNotices(_ journey: Journey) -> [Notice] {
        let remarks = journey.remarks
        return JourneyPresentation.notices(remarks).filter { $0.severity >= .warning }
    }

    // MARK: Footer

    func footer(_ row: ConnectionRow) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if row.journey.shopURL != nil {
                Button { showsShop = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari").font(.system(size: 16, weight: .semibold))
                        Text("Im ÖBB-Ticketshop öffnen").font(.system(size: 17, weight: .semibold))
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
                Text("KlimaBilanz verkauft keine Tickets – der Kauf läuft im Shop der ÖBB.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
            PlannerAttribution()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xs)
    }
}
