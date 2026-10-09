import SwiftUI
import SwiftData
import KlimaCore

/// "Arbeit & Steuer": Jobticket/Arbeitgeberzuschuss, Dienstreisen (AK cap, PDF/CSV-Nachweis), Pendlerpauschale –
/// or, for the self-employed, 50-%-Pauschale vs. Öffi-Fahrtenbuch. Always with the "Keine Steuerberatung" note.
struct WorkTaxView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    @State private var pickedTicketID: UUID?

    var body: some View {
        Group {
            if let ticket = Analytics.activeTicket(in: tickets, selectedID: pickedTicketID ?? app.settings.selectedTicketID) {
                WorkTaxScreen(data: WorkTaxData.make(ticket: ticket, trips: trips, catalog: app.catalog,
                                                     countsCommute: WorkSettings.shared.countsCommuteAsBusiness),
                              tickets: tickets, pickedTicketID: $pickedTicketID)
            } else {
                ScrollView {
                    EmptyStateView(symbol: "briefcase", title: "Noch kein Ticket",
                                   message: "Lege dein KlimaTicket an – dann siehst du hier Arbeitgeberzuschuss, Dienstreisen und was du steuerlich geltend machen kannst.",
                                   actionTitle: "Zum Ticket") {
                        app.isShowingSettings = false
                        app.selectedTab = .ticket
                    }
                    .padding(.top, Theme.Spacing.xxl)
                }
                .background { SetBackdrop(skyOpacity: 0.45, fadeEnd: 0.45) }
            }
        }
        .navigationTitle("Arbeit & Steuer")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct WorkTaxScreen: View {
    let data: WorkTaxData
    let tickets: [TicketEntity]
    @Binding var pickedTicketID: UUID?

    @State private var exports = WorkTaxExports()
    @State private var isAssigning = false
    @State private var isEditingContribution = false
    @State private var contributionSaves = 0

    private var settings: WorkSettings { .shared }

    /// Prepared files of the ticket on screen (none while a switched ticket year is being prepared).
    private var currentExports: WorkTaxExports {
        exports.ticketID == data.ticket.id ? exports : WorkTaxExports()
    }

    /// Rebuild the export documents whenever content that ends up in them changes (trips incl. notes and purposes,
    /// the business-trip cap, the own share, the commute setting, holder and ticket name).
    private var exportKey: Int {
        var hasher = Hasher()
        hasher.combine(data.ticket.id)
        hasher.combine(data.trips)
        hasher.combine(data.business)
        hasher.combine(data.job.ownShare)
        hasher.combine(data.selfEmployed.businessTripCount)
        hasher.combine(settings.countsCommuteAsBusiness)
        hasher.combine(data.ticket.holderName)
        hasher.combine(data.ticket.name)
        return hasher.finalize()
    }

    var body: some View {
        @Bindable var settings = WorkSettings.shared
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Ticketjahr \(data.ticketYear) · \(data.ticket.name)")
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                WorkDisclaimerBanner()
                // Glass segments: the selection capsule glides, the cards below swap with a rise (plays its own haptic).
                GlassSegmentedPicker(selection: $settings.role, options: WorkTaxRole.allCases) { role in
                    Text(role.displayName)
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Beschäftigung")
                .reveal(order: 1)

                Group {
                    if settings.role == .employee {
                        WorkJobticketCard(data: data, onEditContribution: { isEditingContribution = true })
                            .reveal(order: 2)
                        WorkBusinessTripsCard(data: data, exports: currentExports, onAssign: { isAssigning = true })
                            .reveal(order: 3)
                        WorkPendlerCard(data: data)
                            .reveal(order: 4)
                    } else {
                        WorkSelfEmployedCard(data: data)
                            .reveal(order: 2)
                        WorkLogbookCard(data: data, exports: currentExports, onAssign: { isAssigning = true })
                            .reveal(order: 3)
                    }
                }
                .scrollCardTransition()
                .motionTransition(.rise)
                WorkSourceLinks(sources: WorkSourceLinks.tax)
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .revealScope()
        .background { SetBackdrop(skyOpacity: 0.45, fadeEnd: 0.45) }
        .toolbar { toolbarContent }
        .sheet(isPresented: $isAssigning) {
            WorkAssignSheet(period: data.period)
        }
        .sheet(isPresented: $isEditingContribution) {
            WorkContributionSheet(ticket: data.ticket) { contributionSaves += 1 }
        }
        .haptic(.success, trigger: contributionSaves)
        .task(id: exportKey) {
            // Only the documents are built here (rows, totals, CSV text); the PDFs are drawn when shared.
            exports = WorkTaxExports.make(data, countsCommute: settings.countsCommuteAsBusiness)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if tickets.count > 1 {
                Menu {
                    Picker("Ticketjahr", selection: Binding(get: { data.ticket.id }, set: { pickedTicketID = $0 })) {
                        ForEach(tickets) { ticket in
                            Text("\(StatsCalc.ticketYearLabel(ticket.period)) · \(ticket.name)").tag(ticket.id)
                        }
                    }
                } label: {
                    Label("Ticketjahr wählen", systemImage: "calendar")
                }
            }
            Button {
                isAssigning = true
            } label: {
                Label("Fahrten zuordnen", systemImage: "tag")
            }
        }
    }
}
