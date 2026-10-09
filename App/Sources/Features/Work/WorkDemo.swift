import SwiftUI
import SwiftData
import KlimaCore

/// Work purposes for the demo year (screenshots): the Arlberg commuter rides to Landeck for work ("Arbeitsweg") and
/// to the Innsbruck head office for meetings ("Dienstreise", each with an occasion). Values and dates stay untouched,
/// so all demo totals remain identical. Deterministic by route and weekday – no change to DemoData.swift needed.
@MainActor
enum WorkDemo {
    static let occasions = ["Projektbesprechung Landhaus", "Kundentermin Innenstadt", "Schulung Datenschutz", "Abstimmung Bauamt",
                            "Teammeeting Zentrale", "Workshop Mobilität", "Quartalsgespräch"]

    /// Weekday St. Anton ↔ Innsbruck = Dienstreise, weekday St. Anton ↔ Landeck = Arbeitsweg.
    static func applyWorkCategories(to trips: [TripEntity]) {
        let calendar = Calendar.vienna
        let routes = DemoData.routes
        guard routes.count > 1 else { return }
        var occasionIndex = 0
        for trip in trips.sorted(by: { $0.date < $1.date }) {
            let weekday = calendar.component(.weekday, from: trip.date)   // 1 = Sonntag, 7 = Samstag
            guard (2...6).contains(weekday) else { continue }
            if trip.fromName == routes[0].from, trip.toName == routes[0].to {
                trip.category = .business
                if trip.note.isEmpty { trip.note = occasions[occasionIndex % occasions.count] }
                occasionIndex += 1
            } else if trip.fromName == routes[1].from, trip.toName == routes[1].to {
                trip.category = .commute
            }
        }
    }

    /// Puts settings and demo data into the state a screenshot route needs (in-memory store, screenshot defaults).
    static func prepare(screen: String, context: ModelContext) {
        let settings = WorkSettings.shared
        settings.resetCar()
        settings.role = .employee
        settings.countsCommuteAsBusiness = true
        applyWorkCategories(to: (try? context.fetch(FetchDescriptor<TripEntity>())) ?? [])
        let ticket = (try? context.fetch(FetchDescriptor<TicketEntity>()))?.first
        switch screen {
        case "carSettings":
            settings.carMode = .fuelOnly
            settings.carGivenUp = true
        case "work", "workPDF", "workAssign":
            ticket?.employerContribution = 800      // AK example: € 1.400 − € 800 = € 600 own share
        case "workSelf", "workLogbookPDF":
            settings.role = .selfEmployed
        default:
            break
        }
        try? context.save()
    }
}

/// CI screenshot routes of this module: car carSettings carCard work workSelf workAssign workPDF workLogbookPDF.
struct WorkScreenshotHost: View {
    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var isReady = false
    @State private var showsSheet = false

    var body: some View {
        Group {
            if isReady { content } else { Color.clear.ambientBackground() }
        }
        .task {
            guard !isReady else { return }
            WorkDemo.prepare(screen: screen, context: context)
            isReady = true
            if screen == "workAssign" {
                try? await Task.sleep(for: .milliseconds(500))
                showsSheet = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "carSettings":
            NavigationStack { WorkCarSettingsView() }
        case "carCard":
            NavigationStack { WorkCarCardPreview() }
        case "work", "workSelf":
            NavigationStack { WorkTaxView() }
        case "workAssign":
            NavigationStack { WorkTaxView() }
                .sheet(isPresented: $showsSheet) {
                    if let ticket = Repository(context: context, app: app).liveTickets().first {
                        WorkAssignSheet(period: ticket.period)
                    }
                }
        case "workPDF", "workLogbookPDF":
            WorkPDFPreview(isLogbook: screen == "workLogbookPDF")
        default:
            NavigationStack { WorkCarView() }
        }
    }
}

/// The statistics card in context (QA screenshot "carCard").
private struct WorkCarCardPreview: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]

    var body: some View {
        ScrollView {
            if let ticket = Analytics.activeTicket(in: tickets, selectedID: nil) {
                let snapshot = Analytics.make(ticket: ticket, trips: trips, catalog: app.catalog)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    StatsTicketComparisonCard(snapshot: snapshot, products: app.catalog.products, variant: ticket.variant, grow: 1)
                    StatsCarCO2Section(snapshot: snapshot, kilometergeld: app.catalog.kilometergeldEUR, grow: 1)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .ambientBackground()
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
        .defaultScrollAnchor(.bottom)
    }
}

/// First PDF page scaled to the screen (QA screenshots "workPDF" / "workLogbookPDF").
private struct WorkPDFPreview: View {
    var isLogbook: Bool

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if let ticket = Analytics.activeTicket(in: tickets, selectedID: nil) {
                    let data = WorkTaxData.make(ticket: ticket, trips: trips, catalog: app.catalog,
                                                countsCommute: WorkSettings.shared.countsCommuteAsBusiness)
                    let document = isLogbook ? WorkPDF.logbookDocument(data, countsCommute: WorkSettings.shared.countsCommuteAsBusiness)
                                             : WorkPDF.businessDocument(data)
                    let pages = WorkPDF.paginate(document)
                    let scale = max(0.3, (geo.size.width - 24) / WorkPDF.pageSize.width)
                    VStack(spacing: 16) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, spec in
                            WorkPDFPage(document: document, spec: spec, pageNumber: index + 1, pageCount: pages.count)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: WorkPDF.pageSize.width * scale, height: WorkPDF.pageSize.height * scale, alignment: .topLeading)
                                .clipShape(.rect(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Theme.sheetBackground.ignoresSafeArea())
    }
}
