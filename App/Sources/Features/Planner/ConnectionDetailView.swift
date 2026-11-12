import SwiftUI
import SwiftData
import KlimaCore

/// One connection in detail (docs/OEBB_LIVE.md §E3 „Detail“, UX §4.3, mock 12): times with realtime, the map, the value
/// card with the price source, the timeline with platforms, changes and notices – and „Fahrt erfassen“ in one tap.
struct ConnectionDetailView: View {
    let rowID: String

    @Environment(AppState.self) var app
    @Environment(\.modelContext) var context
    @Environment(\.scenePhase) var scenePhase
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse) var trips: [TripEntity]

    @State var polylines: [String: [GeoPoint]] = [:]
    @State var price = PlannerPriceState()
    @State var expanded: Set<String> = []
    @State private var showsMap = false
    @State var showsShop = false
    @State var showsPriceInfo = false
    @State var loggedTrips: [TripEntity] = []
    @State var confirmsFuture = false
    @State var logTick = 0
    @State var calendarFile: URL?
    @State var reminderFire: Date?
    @State private var showsShare = false
    @State private var alarmInput: ExitAlarmSheetInput?   // MARK: exitalarm – the Aussteige-Wecker sheet

    var body: some View {
        let model = app.planner
        Group {
            if let row = model.row(id: rowID) {
                content(row, model: model)
            } else {
                ContentUnavailableView("Verbindung nicht mehr da", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                       description: Text("Such die Verbindung noch einmal."))
            }
        }
        .ambientBackground(.standard, glow: 0.4)
        .navigationBarTitleDisplayMode(.inline)
        .zoomDestination(id: rowID)
    }

    // MARK: Content

    private func content(_ row: ConnectionRow, model: PlannerModel) -> some View {
        let journey = row.journey
        let amount = displayQuote(row)
        return ScrollView {
            VStack(spacing: Theme.Spacing.s) {
                headerCard(row)
                    .reveal(order: 0)
                valueCard(row, amount: amount, model: model)
                    .reveal(order: 1)
                ForEach(journeyNotices(journey)) { NoticeRow(notice: $0, compact: false) }
                    .reveal(order: 2)
                timelineCard(row)
                    .reveal(order: 3)
                planCard(row, model: model)
                    .reveal(order: 4)
                footer(row)
                    .reveal(order: 5)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, 120)
        }
        .revealScope()
        .safeAreaInset(edge: .bottom) { actionBar(row, amount: amount, model: model) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let target = followTarget(row) {   // MARK: scotty – Live verfolgen (first ride leg)
                    Button { LiveFollowTracker.shared.start(target, live: app.live) } label: {
                        Image(systemName: "location.fill")
                    }
                    .accessibilityLabel("Live verfolgen")
                    // MARK: exitalarm – a thin button: the shared sheet does the rest
                    Button { alarmInput = ExitAlarmSheetInput(target: target) } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("Aussteige-Wecker")
                }
                Button { showsShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Teilen")
                if let calendarFile {
                    ShareLink(item: calendarFile) { Image(systemName: "calendar.badge.plus") }
                        .accessibilityLabel("In den Kalender")
                }
            }
        }
        .sheet(isPresented: $showsMap) { ConnectionMapSheet(route: mapRoute(row)) }
        .sheet(item: $alarmInput) { ExitAlarmSheet(input: $0) }   // MARK: exitalarm
        .sheet(isPresented: $showsShare) {
            PlannerShareSheet(journey: row.journey, link: PlannerShare.link(for: row.journey, vias: model.queriedVias))
        }
        .sheet(isPresented: $showsShop) { if let url = journey.shopURL { PlannerSafariSheet(url: url) } }
        .confirmationDialog("Diese Fahrt liegt in der Zukunft.", isPresented: $confirmsFuture, titleVisibility: .visible) {
            Button("Trotzdem erfassen") { logNow(row, amount: amount, model: model) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Erfasse sie am besten nach der Ankunft.")
        }
        .task(id: journey.id) { await loadExtras(row, model: model) }
        .task(id: scenePhase) { await refreshLoop(model) }
        .haptic(.success, trigger: logTick)
    }

    // MARK: Header

    private func headerCard(_ row: ConnectionRow) -> some View {
        let s = row.summary
        let isLive = s.departure.state != .scheduled || s.arrival.state != .scheduled
        return GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: dayText(s.plannedDeparture))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    timeBlock(s.plannedDeparture, s.departure)
                    Image(systemName: "arrow.right").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    timeBlock(s.plannedArrival, s.arrival)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("\(s.durationText) · \(s.changesText)")
                        .font(.system(size: 17)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    liveChip(s, isLive: isLive)
                }
                ConnectionMapView(route: mapRoute(row), onExpand: { showsMap = true })
                    .padding(.top, 2)
            }
        }
    }

    private func timeBlock(_ planned: Date?, _ label: RealtimeLabel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(planned.map(Format.time) ?? "–")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(label.state == .cancelled ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(label.state == .cancelled, color: Theme.negativeText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if label.state == .late || label.state == .veryLate, let text = label.text {
                Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(PlannerRealtimeStyle.text(label.state))
            }
        }
    }

    private func liveChip(_ s: ConnectionSummary, isLive: Bool) -> some View {
        let worst = [s.departure, s.arrival].max { rank($0.state) < rank($1.state) } ?? s.departure
        let text: String
        switch worst.state {
        case .scheduled: text = "Fahrplan"
        case .onTime: text = "Live · pünktlich"
        case .late, .veryLate: text = "Live · +\(worst.delayMinutes ?? 0) min"
        case .cancelled: text = "Fällt aus"
        }
        return HStack(spacing: 5) {
            if isLive { LiveDot(state: worst.state, size: 7) }
            Text(text).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(PlannerRealtimeStyle.text(worst.state))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PlannerRealtimeStyle.dot(worst.state).opacity(0.14), in: .capsule)
    }

    private func rank(_ state: RealtimeState) -> Int {
        switch state { case .scheduled: 0; case .onTime: 1; case .late: 2; case .veryLate: 3; case .cancelled: 4 }
    }
}
