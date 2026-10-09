import SwiftUI
import SwiftData
import KlimaCore

/// Sheets presented by the Vorteilswelt screen.
enum PerkSheet: Identifiable {
    case catalog
    case add(PerkPartner)
    case edit(BenefitEntity)

    var id: String {
        switch self {
        case .catalog: "catalog"
        case .add(let partner): "add-\(partner.id)"
        case .edit(let benefit): "edit-\(benefit.id.uuidString)"
        }
    }
}

/// "Vorteile" – the Vorteilswelt log: the yearly "Zusatz-Ersparnis" (always separate from the trip payoff),
/// quick-add chips, the used benefits by month (swipe to delete / log again, tap to edit) and the entry to the
/// Fahrgastrechte assistant. Lives inside a NavigationStack provided by the presenter.
struct PerkBenefitsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<BenefitEntity> { $0.deletedAt == nil }, sort: \BenefitEntity.date, order: .reverse)
    private var benefits: [BenefitEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]

    @State private var sheet: PerkSheet?
    @State private var showsPassengerRights = false
    @State private var successTick = 0
    @State private var warningTick = 0

    private let catalog = PerkCatalogStore.shared

    var body: some View {
        let period = PerkPeriod.current(tickets: tickets, selectedID: app.settings.selectedTicketID)
        let summary = PerkSummary.make(benefits: benefits, period: period)
        let haptics = app.settings.hapticsEnabled
        List {
            topSection(period: period, summary: summary)
            if benefits.isEmpty {
                emptySection
            }
            quickAddSection(isEmpty: benefits.isEmpty)
            ForEach(PerkMonthGroup.group(benefits)) { group in
                monthSection(group)
            }
            rightsSection
            footerSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.m)
        .scrollContentBackground(.hidden)
        .ambientBackground(.standard, glow: 0.5)
        .navigationTitle("Vorteile")
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(period.label)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheet = .catalog
                } label: {
                    Label("Vorteil erfassen", systemImage: "plus")
                }
            }
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .navigationDestination(isPresented: $showsPassengerRights) {
            PerkPassengerRightsView()
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: benefits.count)
        .perkHaptic(.success, trigger: successTick, enabled: haptics)
        .perkHaptic(.warning, trigger: warningTick, enabled: haptics)
    }

    // MARK: Sections

    @ViewBuilder
    private func topSection(period: PerkPeriod, summary: PerkSummary) -> some View {
        if !benefits.isEmpty {
            Section {
                PerkHeroCard(summary: summary, benefits: benefits, period: period)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xxs, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                PerkSeparateNote(tripSummary: tripSummary, summary: summary)
                    .listRowInsets(EdgeInsets(top: PerkStyle.cardSpacing, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private var emptySection: some View {
        Section {
            GlassCard(padding: Theme.Spacing.xxs) {
                EmptyStateView(symbol: "gift",
                               title: "Noch keine Vorteile erfasst",
                               message: "Mit dem KlimaTicket sparst du auch abseits der Schiene – CAT −50 %, Museen, Sommer-Bergbahnen. Erfasse, was du nutzt: Wir zählen es als Zusatz-Ersparnis, getrennt von deiner Ticket-Bilanz.",
                               actionTitle: "Vorteil erfassen") {
                    sheet = .catalog
                }
            }
            .listRowInsets(EdgeInsets(top: Theme.Spacing.xxs, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func quickAddSection(isEmpty: Bool) -> some View {
        Section {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(quickAddPartners) { partner in
                            PerkQuickAddChip(partner: partner) {
                                sheet = .add(partner)
                            }
                        }
                        allButton
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Schnell erfassen")
        } header: {
            PerkListHeader(title: isEmpty ? "Beliebte Vorteile" : "Schnell erfassen")
        }
    }

    private var allButton: some View {
        Button {
            sheet = .catalog
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.footnote.weight(.semibold))
                Text("Alle \(catalog.partners.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 46)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Alle \(catalog.partners.count) Vorteile durchsuchen")
    }

    private func monthSection(_ group: PerkMonthGroup) -> some View {
        Section {
            ForEach(group.benefits) { benefit in
                row(benefit)
            }
        } header: {
            PerkMonthHeader(group: group)
        }
    }

    private func row(_ benefit: BenefitEntity) -> some View {
        let partner = catalog.partner(id: benefit.partnerID)
        return Button {
            sheet = .edit(benefit)
        } label: {
            PerkBenefitRow(benefit: benefit, partner: partner)
        }
        .buttonStyle(.plain)
        .listRowBackground(PerkRowBackground())
        .listRowSeparatorTint(Theme.separator)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(benefit)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                repeatToday(benefit)
            } label: {
                Label("Nochmal", systemImage: "arrow.clockwise")
            }
            .tint(Theme.pine)
        }
        .contextMenu {
            Button { sheet = .edit(benefit) } label: { Label("Bearbeiten", systemImage: "pencil") }
            Button { repeatToday(benefit) } label: { Label("Heute nochmal genutzt", systemImage: "arrow.clockwise") }
            if let partner, let url = URL(string: partner.url) {
                Link(destination: url) { Label("Zum Angebot", systemImage: "arrow.up.right.square") }
            }
            Divider()
            Button(role: .destructive) { delete(benefit) } label: { Label("Löschen", systemImage: "trash") }
        }
        .accessibilityAction(named: "Heute nochmal genutzt") { repeatToday(benefit) }
        .accessibilityAction(named: "Löschen") { delete(benefit) }
    }

    private var rightsSection: some View {
        Section {
            PerkRightsTeaserCard {
                showsPassengerRights = true
            }
            .listRowInsets(EdgeInsets(top: Theme.Spacing.xxs, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            PerkListHeader(title: "Fahrgastrechte")
        }
    }

    private var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: PerkCatalogStore.sourceURL) {
                    Label("Alle Vorteile auf klimaticket.at", systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: PerkSheet) -> some View {
        switch item {
        case .catalog:
            PerkCatalogSheet()
        case .add(let partner):
            NavigationStack {
                PerkEditorView(mode: .new(partner)) { sheet = nil }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .edit(let benefit):
            NavigationStack {
                PerkEditorView(mode: .edit(benefit)) { sheet = nil }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Derived

    /// Recently used partners first, then the featured ones (max. 8 chips).
    private var quickAddPartners: [PerkPartner] {
        var seen = Set<String>()
        var result: [PerkPartner] = []
        for benefit in benefits {
            guard result.count < 4, !seen.contains(benefit.partnerID),
                  let partner = catalog.partner(id: benefit.partnerID) else { continue }
            seen.insert(partner.id)
            result.append(partner)
        }
        for partner in catalog.featured where result.count < 8 && !seen.contains(partner.id) {
            seen.insert(partner.id)
            result.append(partner)
        }
        return result
    }

    /// Trip payoff of the active ticket – shown next to (never mixed with) the Zusatz-Ersparnis.
    private var tripSummary: SavingsSummary? {
        guard let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) else { return nil }
        return Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog).summary
    }

    private var footerText: String {
        let asOf = PerkCatalogStore.asOfText.map { "Katalog Stand \($0). " } ?? ""
        return "\(asOf)Die Zusatz-Ersparnis zeigt, was du dank Partner-Rabatten weniger bezahlt hast. Sie wird getrennt ausgewiesen und ändert die Amortisation deines Tickets nicht."
    }

    // MARK: Actions

    private func delete(_ benefit: BenefitEntity) {
        let title = benefit.title
        withAnimation(reduceMotion ? nil : .snappy) {
            Repository(context: context, app: app).deleteBenefit(benefit)
        }
        warningTick += 1
        app.showToast("trash.fill", "Vorteil gelöscht", title)
    }

    private func repeatToday(_ benefit: BenefitEntity) {
        let copy = withAnimation(reduceMotion ? nil : .snappy) {
            Repository(context: context, app: app).repeatBenefit(benefit)
        }
        successTick += 1
        app.showToast("gift.fill", "Nochmal erfasst", "\(copy.title) · \(PerkFormat.plusEuro(copy.savedEUR))")
    }
}

// MARK: - Hero

/// "ZUSATZ-ERSPARNIS · + € 86 · durch 12 Vorteile" with the monthly chart (stacked by category) and its legend.
struct PerkHeroCard: View {
    var summary: PerkSummary
    var benefits: [BenefitEntity]
    var period: PerkPeriod

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center) {
                    Kicker(text: "Zusatz-Ersparnis")
                    Spacer(minLength: Theme.Spacing.xs)
                    Image(systemName: "gift.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(LinearGradient(colors: [Theme.gold, Theme.dawn], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: .circle)
                        .environment(\.colorScheme, .light)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    PerkEuroNumeral(amount: summary.total.rounded())
                    Text(subline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                PerkMonthlyChart(benefits: benefits, period: period)
                    .padding(.top, Theme.Spacing.xxs)
                if !summary.byCategory.isEmpty {
                    PerkCategoryLegend(totals: summary.byCategory)
                }
            }
        }
    }

    private var subline: String {
        guard summary.count > 0 else { return "Noch kein Vorteil in diesem Zeitraum" }
        return "durch \(PerkFormat.count(summary.count)) · \(Format.euroPrecise(summary.total)) gespart"
    }
}

/// Makes the separation explicit: the trip payoff stays as it is, the benefits are counted on top.
struct PerkSeparateNote: View {
    var tripSummary: SavingsSummary?
    var summary: PerkSummary

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "mountain.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Vorteile zählen extra – sie ändern deine Amortisation nicht.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard let tripSummary else { return "Getrennt von deiner Ticket-Bilanz" }
        return "Ticket-Bilanz: \(Format.percent(tripSummary.amortizedFraction)) amortisiert · \(Format.euro(tripSummary.totalValue, decimals: 0)) Fahrten-Wert"
    }
}

/// Fahrgastrechte entry card inside the Vorteilswelt list.
struct PerkRightsTeaserCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Theme.dawn, Theme.alpenglow], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: .rect(cornerRadius: 13, style: .continuous))
                    .environment(\.colorScheme, .light)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Geld zurück bei Verspätung")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Unter 93 % Pünktlichkeit gibt's eine Entschädigung – Checkliste & Erinnerung.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCard(cornerRadius: Theme.Radius.card)
            .contentShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PerkPressableStyle())
        .accessibilityHint("Öffnet den Fahrgastrechte-Assistenten")
    }
}

/// Section header on the 20 pt text margin ("Schnell erfassen", "Fahrgastrechte").
struct PerkListHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionTitle)
            .foregroundStyle(Theme.textPrimary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}
