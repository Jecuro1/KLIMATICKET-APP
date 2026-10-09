import SwiftUI
import SwiftData
import KlimaCore

/// „Ratgeber“ – everything a KlimaTicket holder has to decide, computed from their real trips (pushed from the Ticket tab):
/// Verlängern oder kündigen? · Kündigungsrechner · 1.-Klasse-Upgrade · Familien-Bilanz · Jobticket.
struct AdvisorView: View {
    let ticket: TicketEntity
    /// Scrolls to a section or block on appear (screenshot routes).
    var initialAnchor: AdvAnchor? = nil

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    @State private var showsInlineTitle = false
    @State private var editRequest: TktEditRequest?
    @State private var jumpCount = 0
    @State private var didInitialScroll = false

    var body: some View {
        let advice = AdvAdvisor.advice(for: ticket, trips: trips, app: app)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(advice)
                        .padding(.horizontal, Theme.Spacing.screen)
                        .padding(.top, Theme.Spacing.xxs)
                    AdvGlanceCard(glances: advice.advGlances) { section in
                        jump(to: section, proxy: proxy)
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.m)
                    .advEntrance(0)
                    sections(advice)
                    footer
                        .padding(.horizontal, Theme.Spacing.screen)
                        .padding(.top, AdvStyle.sectionSpacing)
                }
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: Bool.self, of: { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 52
            }, action: { _, isPastHeader in
                withAnimation(.easeInOut(duration: 0.2)) { showsInlineTitle = isPastHeader }
            })
            .task {
                guard let initialAnchor, !didInitialScroll else { return }
                didInitialScroll = true
                try? await Task.sleep(for: .milliseconds(350))
                proxy.scrollTo(initialAnchor, anchor: .top)
            }
        }
        .ambientBackground(.standard, glow: 0.45 + 0.5 * advice.summary.progressClamped)
        .navigationTitle("Ratgeber")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Ratgeber")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .opacity(showsInlineTitle ? 1 : 0)
                    .accessibilityHidden(!showsInlineTitle)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(item: $editRequest) { request in
            TktEditSheet(ticket: request.ticket, initial: request.draft)
        }
        .sensoryFeedback(.selection, trigger: jumpCount) { _, _ in app.settings.hapticsEnabled }
    }

    // MARK: Header

    private func header(_ advice: TicketAdvice) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Ticket-Ratgeber · \(TicketAdvisor.yearLabel(start: ticket.startDate, end: ticket.endDate))")
            Text("Ratgeber")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle(advice))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(_ advice: TicketAdvice) -> String {
        let count = advice.summary.tripCount
        if count == 0 { return "\(ticket.name) · sobald du Fahrten erfasst, wird's persönlich" }
        return "\(ticket.name) · aus \(AdvText.trips(count)) berechnet"
    }

    // MARK: Sections

    @ViewBuilder
    private func sections(_ advice: TicketAdvice) -> some View {
        let hasContribution = advice.jobticket.hasContribution
        section(.renewal, index: 1) {
            AdvRenewalCard(renewal: advice.renewal, summary: advice.summary, hasEmployerContribution: hasContribution)
            if !advice.renewal.isExpired {
                AdvRenewalReminderCard(ticketID: ticket.id, ticketName: ticket.name, renewal: advice.renewal,
                                       family: ticket.family, isMonthlyPayment: ticket.isMonthlyPayment,
                                       onEdit: { edit() })
                    .id(AdvAnchor.renewalReminder)
            }
        }
        if advice.cancellation.verdict != .expired {
            section(.cancellation, index: 2) {
                AdvCancellationCard(advice: advice.cancellation, hasEmployerContribution: hasContribution)
                if advice.cancellation.extraordinary != nil {
                    AdvExtraordinaryCard(advice: advice.cancellation)
                }
            }
        }
        if let firstClass = advice.firstClass {
            section(.firstClass, index: 3) {
                AdvFirstClassCard(advice: firstClass, isExpired: advice.renewal.isExpired)
            }
        }
        if let family = advice.family {
            section(.family, index: 4) {
                AdvFamilyCard(advice: family, isExpired: advice.renewal.isExpired, isKlimaTicketOe: ticket.family == .oe)
            }
        }
        section(.jobticket, index: 5) {
            if hasContribution {
                AdvJobticketCard(advice: advice.jobticket, isExpired: advice.renewal.isExpired)
            } else {
                AdvJobticketHint(onEdit: { edit() })
            }
        }
    }

    private func section<Content: View>(_ id: AdvSection, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AdvStyle.cardSpacing) {
            content()
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, AdvStyle.sectionSpacing)
        .id(AdvAnchor.section(id))
        .advEntrance(index)
    }

    private var footer: some View {
        AdvNote(symbol: "checkmark.shield",
                text: "Grundlage: AGB KlimaTicket Ö (gültig ab 1. Jänner 2026), ÖBB-Extras und -Tarife, Stand 9. Oktober 2026. Prognosen beruhen auf deinem bisherigen Fahrtempo. Alle Angaben ohne Gewähr – keine Rechts- oder Steuerberatung.")
    }

    // MARK: Actions

    private func jump(to section: AdvSection, proxy: ScrollViewProxy) {
        jumpCount += 1
        withAnimation(.smooth(duration: 0.5)) {
            proxy.scrollTo(AdvAnchor.section(section), anchor: .top)
        }
    }

    private func edit() {
        editRequest = TktEditRequest(ticket: ticket, draft: TktDraft(ticket: ticket))
    }
}

// MARK: - Auf einen Blick

/// One tappable line per section (verdict + key number); tap scrolls to the section.
struct AdvGlanceCard: View {
    var glances: [AdvGlance]
    var onSelect: (AdvSection) -> Void

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Auf einen Blick")
                    .padding(.horizontal, TktStyle.rowPaddingH)
                    .padding(.top, TktStyle.rowPaddingH)
                    .padding(.bottom, Theme.Spacing.xxs)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(glances.enumerated()), id: \.element.id) { index, glance in
                    if index > 0 {
                        TktHairline()
                            .padding(.leading, TktStyle.rowPaddingH + 36 + Theme.Spacing.s)
                    }
                    row(glance)
                }
            }
            .padding(.bottom, Theme.Spacing.xxs)
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private func row(_ glance: AdvGlance) -> some View {
        Button {
            onSelect(glance.section)
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                TktIconTile(symbol: glance.section.symbol, color: glance.section.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(glance.section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(glance.verdict)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !glance.detail.isEmpty {
                        Text(glance.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                if let value = glance.value {
                    Text(value)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(glance.tone.textColor)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TktStyle.rowPaddingH)
            .padding(.vertical, TktStyle.rowPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdvRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zeigt den Abschnitt \(glance.section.title)")
    }
}

/// Row highlight while pressed (list-style rows inside frosted cards).
struct AdvRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surfaceSecondary : Color.clear)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
