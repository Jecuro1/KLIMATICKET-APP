import SwiftUI
import SwiftData
import KlimaCore

extension View {
    /// Root hook of the "Unterwegs" Live Activity (RootView): saves rides handed over by the Live Activity, cleans up
    /// overdue (8 h) and orphaned activities on launch / foreground, keeps "73 % → 77 %" current and asks what to do
    /// with rides that ended without a decision.
    func rideActivityHost() -> some View {
        modifier(RideActivityHostModifier())
    }
}

private struct RideActivityHostModifier: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// Rides waiting for "Speichern / Bearbeiten / Verwerfen", oldest first.
    @State private var pending: [RideRecord] = []
    @State private var asking: RideRecord?
    @State private var isRefreshing = false

    func body(content: Content) -> some View {
        content
            .task {
                await refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: RideStore.didChange).receive(on: RunLoop.main)) { _ in
                Task { await refresh() }
            }
            .onChange(of: canAsk) { _, canAsk in
                if canAsk { askNext() }
            }
            .alert("Fahrt noch speichern?", isPresented: isAsking, presenting: asking) { record in
                Button("Speichern") { decide(record, .save) }
                Button("Bearbeiten …") { decide(record, .edit) }
                Button("Verwerfen", role: .destructive) { decide(record, .discard) }
            } message: { record in
                Text(Self.question(record))
            }
    }

    // MARK: Refresh

    private func refresh() async {
        guard !LaunchMode.isScreenshot, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let repo = Repository(context: context, app: app)
        announce(repo.ingestFinishedRides())

        let controller = RideActivityController.shared
        let undecided = await controller.reconcile()
        if !controller.rides.isEmpty, let balance = RidePlanner.balance(context: context, app: app) {
            await controller.refreshPayoffs(currentValue: balance.value, ticketPrice: balance.price)
        }
        let known = Set(pending.map(\.id) + [asking?.id].compactMap { $0 })
        pending += undecided.filter { !known.contains($0.id) }
        askNext()
    }

    /// Toast (and the break-even celebration) for rides saved from the Live Activity – worded like the trip editor's.
    private func announce(_ saved: [(record: RideRecord, trip: TripEntity)]) {
        guard !saved.isEmpty else { return }
        let total = saved.reduce(0) { $0 + $1.trip.totalValue }
        let title = saved.count == 1 ? "Fahrt gespeichert" : "\(saved.count) Fahrten gespeichert"
        app.showToast("checkmark.circle.fill", title, Self.savedSubtitle(value: total, balance: RidePlanner.balance(context: context, app: app)))
        celebrateIfSummitReached(saved.map(\.record))
    }

    /// "+ € 47,00 · jetzt 78 % amortisiert" / "+ € 47,00 · reiner Gewinn"
    private static func savedSubtitle(value: Double, balance: RidePlanner.Balance?) -> String {
        var text = RideFormat.plusEuro(value)
        if let balance {
            let before = (balance.value - value) / balance.price
            text += before >= 1 ? " · reiner Gewinn" : " · jetzt \(Format.percent(balance.value / balance.price)) amortisiert"
        }
        return text
    }

    private func celebrateIfSummitReached(_ records: [RideRecord]) {
        guard records.contains(where: { $0.payoff?.reachesSummit == true }) else { return }
        let repo = Repository(context: context, app: app)
        guard let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID),
              !app.settings.celebratedBreakEvenTicketIDs.contains(ticket.id.uuidString),
              Analytics.make(ticket: ticket, trips: repo.liveTrips(), catalog: app.catalog).summary.isPaidOff else { return }
        app.celebrateBreakEven = true
    }

    // MARK: Decisions

    private enum Decision { case save, edit, discard }

    /// Alerts cannot show above a sheet – wait until the trip editor and Settings are closed.
    private var canAsk: Bool { app.tripDraft == nil && !app.isShowingSettings && !app.isShowingAchievements }

    private var isAsking: Binding<Bool> {
        Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
    }

    private func askNext() {
        guard asking == nil, canAsk, !pending.isEmpty else { return }
        asking = pending.removeFirst()
    }

    private func decide(_ record: RideRecord, _ decision: Decision) {
        asking = nil
        let repo = Repository(context: context, app: app)
        switch decision {
        case .save:
            if let trip = repo.saveRide(record) {
                app.showToast("checkmark.circle.fill", "Fahrt gespeichert",
                              Self.savedSubtitle(value: trip.totalValue, balance: RidePlanner.balance(context: context, app: app, at: trip.date)))
                celebrateIfSummitReached([record])
            } else {
                RideStore.remove(record.id)
            }
        case .edit:
            RideStore.remove(record.id)
            var draft = TripDraft()
            draft.fromStationID = record.trip.fromStationID
            draft.toStationID = record.trip.toStationID
            draft.fromName = record.trip.fromName
            draft.toName = record.trip.toName
            draft.mode = record.trip.mode
            draft.date = record.startedAt
            draft.isRoundTrip = record.trip.isRoundTrip
            draft.via = record.trip.via   // MARK: via – "Bearbeiten" keeps the ride's via stops
            app.presentAddTrip(draft)
        case .discard:
            RideStore.remove(record.id)
        }
        RideActivityController.shared.reload()
        // The next question after the alert has gone (and not over the editor that "Bearbeiten" opens).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            askNext()
        }
    }

    private static func question(_ record: RideRecord) -> String {
        let route = RideNames.route(from: record.trip.fromName, to: record.trip.toName, roundTrip: record.trip.isRoundTrip)
        let day = Format.relativeDay(record.startedAt)
        let when = (day == "Heute" || day == "Gestern" ? day.lowercased() : "\(day)") + ", \(Format.time(record.startedAt))"
        return "Deine Fahrt \(route) von \(when) ist beendet, aber noch nicht gespeichert. Wert: \(Format.euroPrecise(record.trip.totalValue))."
    }
}
