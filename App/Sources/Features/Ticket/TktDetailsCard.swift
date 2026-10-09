import SwiftUI
import KlimaCore

// MARK: - Details

/// Details list (synthesis §9.6 order): Pro Fahrt bisher ↓ · Kosten pro Tag · Preis · pro Monat · Ticketart ·
/// Bundesländer · Gültig · Gültigkeitsbereich · Berechtigung (catalog texts expandable).
struct TktDetailsCard: View {
    let ticket: TicketEntity
    let summary: SavingsSummary
    /// Trips within this ticket period (AnalyticsSnapshot.trips).
    let records: [TripRecord]
    let product: TicketProduct?

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                costRows
                divider
                ticketRows
                catalogRows
            }
        }
    }

    private var divider: some View {
        TktHairline().padding(.leading, TktStyle.rowPaddingH)
    }

    // MARK: Groups

    private var costRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            perTripRow
            divider
            TktDetailRow(label: "Kosten pro Tag", value: Format.euroPrecise(summary.costPerDay))
            divider
            TktDetailRow(label: "Preis bezahlt", value: Format.euroPrecise(ticket.price))
            divider
            TktDetailRow(label: "Entspricht pro Monat", value: Format.euroPrecise(ticket.price / 12))
        }
    }

    private var ticketRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            TktDetailRow(label: "Ticketart", value: TktText.ticketType(variant: ticket.variant, family: ticket.family))
            divider
            TktDetailRow(label: "Bundesländer", value: statesText)
            divider
            TktDetailRow(label: "Gültig", value: "\(Format.date(ticket.startDate)) – \(Format.date(ticket.endDate))")
        }
    }

    @ViewBuilder
    private var catalogRows: some View {
        if let coverage {
            divider
            TktLongTextRow(label: "Gültigkeitsbereich", text: coverage, collapsedLines: 3)
        }
        if let eligibility {
            divider
            TktLongTextRow(label: "Berechtigung", text: eligibility, collapsedLines: 2)
        }
    }

    // MARK: Values

    @ViewBuilder
    private var perTripRow: some View {
        if summary.tripCount > 0 {
            TktDetailRow(label: "Pro Fahrt bisher", value: Format.euroPrecise(basePrice / Double(summary.tripCount))) {
                if let drop = perTripDrop {
                    TktDropBadge(drop: drop)
                }
            }
        } else {
            TktDetailRow(label: "Pro Fahrt bisher", value: "noch keine Fahrt", valueColor: Theme.textSecondary)
        }
    }

    /// The price the payoff is measured against (`TicketEntity.period` – the holder's own share), so "Pro Fahrt bisher"
    /// matches "Kosten pro Tag" and the amortisation.
    private var basePrice: Double { summary.ticketPrice }

    /// How much cheaper each trip got since the start of this month (or, early on, since the previous trip).
    private var perTripDrop: TktPerTripDrop? {
        let total = records.count
        let price = basePrice
        guard total > 1, price > 0 else { return nil }
        let monthStart = Calendar.vienna.dateInterval(of: .month, for: Date())?.start ?? Date()
        let before = records.filter { $0.date < monthStart }.count
        let sinceMonthStart = before > 0 && before < total
        let reference = sinceMonthStart ? before : total - 1
        let amount = price / Double(reference) - price / Double(total)
        guard amount >= 0.005 else { return nil }
        return TktPerTripDrop(amount: amount, sinceMonthStart: sinceMonthStart)
    }

    private var statesText: String {
        if ticket.family == .oe { return "Alle 9 Bundesländer" }
        let codes = ticket.states.isEmpty ? (product?.states ?? []) : ticket.states
        let names = codes.compactMap { FederalState(rawValue: $0)?.displayName }
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }

    private var coverage: String? {
        guard let text = product?.coverage, !text.isEmpty else { return nil }
        return TktText.cleanCatalogText(text)
    }

    private var eligibility: String? {
        guard let text = product?.eligibility, !text.isEmpty else { return nil }
        return TktText.cleanCatalogText(text)
    }
}

private struct TktPerTripDrop {
    var amount: Double
    var sinceMonthStart: Bool
}

/// Pine pill "↓ € 0,91" next to "Pro Fahrt bisher".
private struct TktDropBadge: View {
    var drop: TktPerTripDrop

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.down")
            Text(Format.euroPrecise(drop.amount))
        }
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(Theme.positiveText)
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 3)
        .background(Theme.positive.opacity(0.14), in: .capsule)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(drop.sinceMonthStart
                            ? "seit Monatsbeginn um \(Format.euroPrecise(drop.amount)) gesunken"
                            : "seit der letzten Fahrt um \(Format.euroPrecise(drop.amount)) gesunken")
    }
}

/// Long catalog text (coverage / eligibility) with "Mehr anzeigen".
private struct TktLongTextRow: View {
    var label: String
    var text: String
    var collapsedLines: Int

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(isExpanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
            if isLong {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Weniger anzeigen" : "Mehr anzeigen")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TktStyle.rowPaddingH)
        .padding(.vertical, TktStyle.rowPaddingV)
    }

    private var isLong: Bool { text.count > collapsedLines * 48 }
}

// MARK: - Actions

/// "Ticket bearbeiten" / "Ticket löschen".
struct TktActionsCard: View {
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                actionRow(title: "Ticket bearbeiten", symbol: "pencil", color: Theme.accentText, action: onEdit)
                TktHairline()
                    .padding(.leading, TktStyle.rowPaddingH + 28 + Theme.Spacing.s)
                // Text-safe red: `negative` (#D64545) stays below 4.5:1 for 17 pt text on the light frosted card.
                actionRow(title: "Ticket löschen", symbol: "trash", color: Theme.negativeText, action: onDelete)
            }
        }
    }

    private func actionRow(title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(color)
            .padding(.horizontal, TktStyle.rowPaddingH)
            .padding(.vertical, TktStyle.rowPaddingV + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History

/// One ticket year with its result.
struct TktHistoryItem: Identifiable {
    let ticket: TicketEntity
    let summary: SavingsSummary
    var id: UUID { ticket.id }
}

/// „Ticket-Verlauf“: all ticket years with their result ("+ € 412 rentiert" / "– € 120"); tap shows that ticket app-wide.
struct TktHistorySection: View {
    let items: [TktHistoryItem]
    let selectedID: UUID?
    var onSelect: (TicketEntity) -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "Ticket-Verlauf")
                .padding(.horizontal, TktStyle.headerInset)
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        TktHistoryRow(item: item, isSelected: item.id == selectedID) {
                            onSelect(item.ticket)
                        }
                        TktHairline()
                            .padding(.leading, TktStyle.rowPaddingH + 46 + Theme.Spacing.s)
                    }
                    addRow
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private var addRow: some View {
        Button(action: onAdd) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 32)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.modeTile * 0.7, style: .continuous))
                    .accessibilityHidden(true)
                Text("Neues Ticket hinzufügen")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TktStyle.rowPaddingH)
            .padding(.vertical, TktStyle.rowPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TktHistoryRow: View {
    let item: TktHistoryItem
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                swatch
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.ticket.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .layoutPriority(1)
                Spacer(minLength: Theme.Spacing.xs)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(outcome.amount)
                        .font(Theme.Typography.numberSmall)
                        .foregroundStyle(outcome.color)
                        .lineLimit(1)
                    Text(outcome.caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .fixedSize()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TktStyle.rowPaddingH)
            .padding(.vertical, TktStyle.rowPaddingV)
            .background(isSelected ? Theme.accent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Wird gerade angezeigt" : "Zeigt dieses Ticket in der ganzen App")
    }

    private var theme: TicketTheme { TicketTheme.from(item.ticket.themeRaw) }

    /// Mini pass in the ticket's theme.
    private var swatch: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.modeTile * 0.7, style: .continuous)
        return shape
            .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 46, height: 32)
            .overlay {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.ink.opacity(0.85))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: theme.colors[1].opacity(0.3), radius: 4, y: 2)
            .accessibilityHidden(true)
    }

    private var subtitle: String {
        let t = item.ticket
        return "Ticketjahr \(TktText.ticketYear(start: t.startDate, end: t.endDate)) · bis \(Format.date(t.endDate))"
    }

    private var outcome: (amount: String, caption: String, color: Color) {
        let t = item.ticket
        let now = Date()
        if now < t.startDate {
            return ("–", "ab \(Format.dayMonth(t.startDate))", Theme.textSecondary)
        }
        // Whole euros from the same rounded figures as the Übersicht ("– € 0 noch offen" can never appear).
        let summary = item.summary
        if summary.isPaidOff {
            return ("+ " + SummitFigures.euro(summary.shownProfitEuro), "rentiert", Theme.positiveText)
        }
        return ("– " + SummitFigures.euro(summary.shownRemainingEuro), t.isExpired ? "nicht rentiert" : "noch offen",
                t.isExpired ? Theme.summitText : Theme.textPrimary)
    }
}
