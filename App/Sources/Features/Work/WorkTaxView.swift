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

    @Environment(AppState.self) private var app
    @State private var exports = WorkTaxExports()
    @State private var isAssigning = false

    private var settings: WorkSettings { .shared }

    /// Rebuild exports whenever content that ends up in them changes.
    private var exportKey: String {
        let latest = data.trips.map(\.date).max()?.timeIntervalSinceReferenceDate ?? 0
        return [data.ticket.id.uuidString, "\(data.trips.count)", "\(data.business.trips.count)",
                Format.number(data.business.total, decimals: 2), Format.number(data.job.ownShare, decimals: 2),
                "\(settings.countsCommuteAsBusiness)", "\(data.selfEmployed.businessTripCount)", "\(latest)",
                data.ticket.holderName, data.trips.map(\.note).joined()].joined(separator: "|")
    }

    var body: some View {
        @Bindable var settings = WorkSettings.shared
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Ticketjahr \(data.ticketYear) · \(data.ticket.name)")
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                WorkDisclaimerBanner()
                Picker("Ich bin", selection: $settings.role.animation(.snappy)) {
                    ForEach(WorkTaxRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, Theme.Spacing.xxs)
                .accessibilityLabel("Beschäftigung")

                if settings.role == .employee {
                    WorkJobticketCard(data: data)
                        .statsEntrance(0)
                    WorkBusinessTripsCard(data: data, exports: exports, onAssign: { isAssigning = true })
                        .statsEntrance(1)
                    WorkPendlerCard(data: data)
                        .statsEntrance(2)
                } else {
                    WorkSelfEmployedCard(data: data)
                        .statsEntrance(0)
                    WorkLogbookCard(data: data, exports: exports, onAssign: { isAssigning = true })
                        .statsEntrance(1)
                }
                WorkSourceLinks(sources: WorkSourceLinks.tax)
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { SetBackdrop(skyOpacity: 0.45, fadeEnd: 0.45) }
        .toolbar { toolbarContent }
        .sheet(isPresented: $isAssigning) {
            WorkAssignSheet(period: data.period)
        }
        .sensoryFeedback(.selection, trigger: settings.role) { _, _ in app.settings.hapticsEnabled }
        .task(id: exportKey) {
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
