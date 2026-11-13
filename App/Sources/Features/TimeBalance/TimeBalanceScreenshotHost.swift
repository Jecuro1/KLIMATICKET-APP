import SwiftUI
import SwiftData
import KlimaCore

/// Until the screens were looked at in CI screenshots, the Zeitbilanz's entry points (Statistik card, klimabilanz://timebalance,
/// the editor's „Dauer“ row) show only in screenshot runs.
enum TimeBalanceRelease {
    static var isLive: Bool { LaunchMode.isScreenshot }
}

/// Sample durations for the demo year („Demo ansehen“, screenshots): the commute logged from the Fahrplan (planned arrival),
/// some rides with an entered duration, the rest without – so the Zeitbilanz shows all three sources. Delays only in the
/// `timeBalanceDelays` fixture: this build has no way to record one yet.
@MainActor
enum TimeBalanceDemo {
    static func assign(trips: [TripEntity]) {
        let calendar = Calendar.vienna
        for trip in trips {
            let minute = calendar.component(.minute, from: trip.date)
            switch (trip.fromName, trip.toName) {
            case ("St. Anton am Arlberg", "Innsbruck Hauptbahnhof"):
                if minute % 2 == 0 { trip.arrivalAt = trip.date.addingTimeInterval(72 * 60) }   // Railjet, from the Fahrplan
            case ("St. Anton am Arlberg", "Landeck-Zams"):
                trip.durationMinutes = 25
            case ("Innsbruck Hauptbahnhof", "Salzburg Hauptbahnhof"):
                trip.arrivalAt = trip.date.addingTimeInterval(108 * 60)
            case ("Innsbruck Hauptbahnhof", "Wien Hauptbahnhof"):
                trip.arrivalAt = trip.date.addingTimeInterval(255 * 60)
            case ("Langen am Arlberg", "Bregenz"):
                if minute % 2 == 1 { trip.durationMinutes = 75 }
            case ("Graz Hauptbahnhof", "Klagenfurt Hauptbahnhof"):
                trip.durationMinutes = 45   // Koralmbahn
            default:
                break
            }
        }
    }

    /// The `timeBalanceDelays` fixture: the same trips with arrival delays as a later delay diary or a followed ride would
    /// record them (live for the Fahrplan connections, typed in for a few others).
    static func withDelays(_ inputs: [TimeTripInput]) -> [TimeTripInput] {
        let pattern = [0, 4, 0, 11, 2, 0, 0, 23, 6, 0, 3, 0, 14, 0, 38, 1]
        var index = 0
        return inputs.map { input in
            var trip = input
            if trip.arrivalAt != nil {
                trip.delayMinutes = pattern[index % pattern.count]
                trip.delaySource = .live
                index += 1
            } else if trip.durationMinutes > 0, index % 3 == 0 {
                trip.delayMinutes = 9
                trip.delaySource = .manual
                index += 1
            }
            return trip
        }
    }
}

/// CI screenshot routes of the Zeitbilanz (`-KBScreenshot <screen> -KBDemo YES`, demo data, no network):
/// - `timeBalance` / `timeBalanceMid` / `timeBalanceBottom`: the demo ticket year (top, the weeks and facts, the end)
/// - `timeBalanceMonth`: the month view with its stepper
/// - `timeBalanceEmpty`: a period without trips
/// - `timeBalanceDelays`: the demo year with recorded delays (fixture)
/// - `timeBalanceAX5` / `timeBalanceAX5Mid` / `timeBalanceAX5Bottom`: the largest accessibility text size
/// - `timeBalanceCard`: the Statistik card
/// - `tripEditDuration`: „Fahrt bearbeiten“ with the „Dauer“ wheel open
struct TimeBalanceScreenshotHost: View {
    static let screens: Set<String> = [
        "timeBalance", "timeBalanceMid", "timeBalanceBottom", "timeBalanceMonth", "timeBalanceEmpty", "timeBalanceDelays",
        "timeBalanceAX5", "timeBalanceAX5Mid", "timeBalanceAX5Bottom", "timeBalanceCard", "tripEditDuration",
    ]

    let screen: String

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]

    var body: some View {
        content
            .dynamicTypeSize(screen.contains("AX5") ? .accessibility5 : .large)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "timeBalanceMid", "timeBalanceAX5Mid":
            NavigationStack { TimeBalanceView() }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.55))
        case "timeBalanceBottom", "timeBalanceAX5Bottom":
            NavigationStack { TimeBalanceView() }
                .defaultScrollAnchor(.bottom)
        case "timeBalanceMonth":
            NavigationStack { TimeBalanceView(initialKind: .month) }
        case "timeBalanceEmpty":
            NavigationStack { TimeBalanceView(fixture: []) }
        case "timeBalanceDelays":
            NavigationStack { TimeBalanceView(fixture: TimeBalanceDemo.withDelays(trips.map(\.timeInput))) }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.3))
        case "timeBalanceCard":
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Statistik")
                            .font(Theme.Typography.heroTitle)
                            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                        if let ticket = Analytics.activeTicket(in: tickets, selectedID: nil) {
                            TimeBalanceEntryCard(period: ticket.period)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                }
                .ambientBackground()
            }
            .zoomTransitionScope()
        case "tripEditDuration":
            MainTabView()
                .onAppear { app.selectedTab = .trips }
                .task {
                    try? await Task.sleep(for: .milliseconds(600))
                    let candidates = Repository(context: context, app: app).liveTrips()
                    if let trip = candidates.first(where: { $0.durationMinutes > 0 }) ?? candidates.first {
                        TripListActions(app: app, context: context).edit(trip)
                    }
                }
        default:
            NavigationStack { TimeBalanceView() }
        }
    }
}
