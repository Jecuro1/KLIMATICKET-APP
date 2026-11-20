import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – demo delays and the CI screenshot routes of the Verspätungs-Tagebuch (docs/DELAY_DIARY.md §8)

extension DelayDiaryRelease {
    /// The hooks in shared screens (trip detail, Statistik, Fahrgastrechte) show when live – and in screenshot runs, so their
    /// scenes can be looked at before they go live.
    static var showsEntryPoints: Bool { isLive || LaunchMode.isScreenshot }
}

/// Delays for the demo year („Demo ansehen“, screenshots): most Fahrten carry an arrival typed in by hand, about one in eight
/// is late, every fifth has no entry (so „Nachtragen“ has something to show). Only „von Hand“: this build never takes a
/// delay from live data, so the demo does not either. The commute logged from the Fahrplan gets its line. Values, km and
/// totals stay as they are.
@MainActor
enum DelayDiaryDemo {
    /// Minutes in recording order; ≥ 5 is late with the default mark.
    static let pattern = [0, 0, 3, 0, 12, 0, 0, 1, 0, 0, 0, 7, 0, 0, 2, 0, 0, 0, 25, 0, 0, 4, 0, 0, 0, 9, 0, 0, 0, 0, 0, 16, 0, 0, 1, 0]

    static func assign(trips: [TripEntity]) {
        guard DelayDiaryRelease.showsEntryPoints else { return }
        var recorded = 0
        for (index, trip) in trips.sorted(by: { $0.date < $1.date }).enumerated() {
            if trip.arrivalAt != nil, trip.lineSummary.isEmpty, trip.fromName == "St. Anton am Arlberg" {
                trip.lineSummary = "Railjet Xpress"
            }
            guard index % 5 != 4 else { continue }
            trip.delayMinutes = pattern[recorded % pattern.count]
            trip.delaySourceRaw = TripDelaySource.manual.rawValue
            recorded += 1
        }
    }

    /// The `delayDiaryEmpty` fixture: the demo year's trips without any entry.
    static func withoutDelays(_ trips: [TripEntity]) -> [DelayDiaryTrip] {
        trips.map { trip in
            var input = trip.delayDiaryTrip
            input.delayMinutes = 0
            input.delaySource = nil
            return input
        }
    }
}

/// CI screenshot routes (`-KBScreenshot <screen> -KBDemo YES`, demo data, no network, no permission):
/// - `delayDiary` / `delayDiaryMid` / `delayDiaryBottom`: the diary of the demo year (top, the months, report and method)
/// - `delayDiaryMonth`: a month opened to its late Fahrten
/// - `delayDiaryEmpty`: nothing recorded yet
/// - `delayEntrySheet` / `delayEntryOnTime`: the sheet over a trip (a late entry; a trip without one)
/// - `delayTripRow`: the „Verspätung“ row in the trip detail
/// - `delayReport`: „Nachweis als PDF“ with the real PDF in the preview
/// - `delayBackfill`: „Nachtragen“ for the current month
/// - `delayOptions`: the diary's settings
/// - `delayDiaryCard`: the Statistik card; `delayRightsLink`: „Mein Verspätungs-Tagebuch“ in Fahrgastrechte
/// - `delayDiaryAX5` / `delayDiaryAX5Mid` / `delayEntrySheetAX5`: the largest accessibility text size
struct DelayDiaryScreenshotHost: View {
    static let screens: Set<String> = [
        "delayDiary", "delayDiaryMid", "delayDiaryBottom", "delayDiaryMonth", "delayDiaryEmpty", "delayEntrySheet", "delayEntryOnTime",
        "delayTripRow", "delayReport", "delayBackfill", "delayOptions", "delayDiaryCard", "delayDiaryAX5", "delayDiaryAX5Mid",
        "delayEntrySheetAX5", "delayRightsLink",
    ]

    let screen: String

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }, sort: \TicketEntity.startDate, order: .reverse)
    private var tickets: [TicketEntity]

    @State private var sheetShown = false

    /// Sheets do not inherit the type size set on the presenter: they get it again.
    private var typeSize: DynamicTypeSize { screen.contains("AX5") ? .accessibility5 : .large }

    var body: some View {
        content
            .dynamicTypeSize(typeSize)
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                sheetShown = true
            }
    }

    private var ticket: TicketEntity? { Analytics.activeTicket(in: tickets, selectedID: nil) }

    private var year: DelayDiaryYear? {
        guard let ticket else { return nil }
        return DelayDiaryMemo.year(trips: trips, start: ticket.startDate, end: ticket.endDate, now: Date(),
                                   options: DelayDiarySettings.shared.options)
    }

    /// The newest late trip (the entry sheet's subject), else the newest trip.
    private var lateTrip: TripEntity? {
        trips.first { ($0.recordedDelay?.minutes ?? 0) >= DelayDiaryRules.defaultThresholdMinutes } ?? trips.first
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "delayDiaryMid", "delayDiaryAX5Mid":
            NavigationStack { DelayDiaryView() }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.5))
        case "delayDiaryBottom":
            NavigationStack { DelayDiaryView() }
                .defaultScrollAnchor(.bottom)
        case "delayDiaryMonth":
            NavigationStack { DelayDiaryView(initiallyExpanded: year?.months.last(where: { $0.lateCount > 0 })?.index) }
        case "delayDiaryEmpty":
            NavigationStack { DelayDiaryView(fixture: DelayDiaryDemo.withoutDelays(trips)) }
        case "delayEntrySheet", "delayEntrySheetAX5", "delayEntryOnTime":
            let trip = screen == "delayEntryOnTime" ? trips.first { $0.recordedDelay == nil } : lateTrip
            NavigationStack {
                if let trip { TripDetailView(trip: trip) }
            }
            .sheet(isPresented: $sheetShown) {
                if let trip { DelayEntrySheet(trip: trip).dynamicTypeSize(typeSize) }
            }
        case "delayTripRow":
            NavigationStack {
                if let trip = lateTrip { TripDetailView(trip: trip) }
            }
            .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.42))
        case "delayReport":
            NavigationStack { DelayDiaryView() }
                .sheet(isPresented: $sheetShown) {
                    if let ticket, let year { DelayReportSheet(ticket: ticket, year: year) }
                }
        case "delayBackfill":
            NavigationStack { DelayDiaryView() }
                .sheet(isPresented: $sheetShown) {
                    if let ticket, let current = year?.months.last(where: { $0.notRecordedCount > 0 }) {
                        DelayBackfillSheet(ticket: ticket, request: DelayBackfillRequest(monthIndex: current.index))
                    }
                }
        case "delayRightsLink":
            NavigationStack { PerkPassengerRightsView() }
                .defaultScrollAnchor(UnitPoint(x: 0.5, y: 0.32))
        case "delayOptions":
            NavigationStack { DelayDiaryView() }
                .sheet(isPresented: $sheetShown) { DelayOptionsSheet() }
        case "delayDiaryCard":
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Statistik")
                            .font(Theme.Typography.heroTitle)
                            .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                        if let ticket {
                            TimeBalanceEntryCard(period: ticket.period)
                            DelayDiaryEntryCard(period: ticket.period)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                }
                .ambientBackground()
            }
            .zoomTransitionScope()
        default:
            NavigationStack { DelayDiaryView() }
        }
    }
}
