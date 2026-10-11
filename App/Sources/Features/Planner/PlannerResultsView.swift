import SwiftUI
import KlimaCore

/// The connections of one search (docs/OEBB_LIVE.md §E3 „Results“, UX §4.2, mock 11): the search card on top, connection
/// cards with realtime and the KlimaTicket footer, „Früher“ / „Später“, and every state the live layer can be in.
struct PlannerResultsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var pausedUntil = Date.distantPast

    var body: some View {
        let model = app.planner
        ScrollView {
            VStack(spacing: Theme.Spacing.s) {
                RouteSlotsCard(origin: slot(model, "origin", "Von", model.origin),
                               vias: model.vias.enumerated().map { slot(model, "via-\($0.offset)", "Über", $0.element) },
                               destination: slot(model, "destination", "Nach", model.destination),
                               onTap: { tap($0, model) }, onSwap: { model.swap() },
                               onRemoveVia: { id in if let i = Int(id.dropFirst(4)) { model.removeVia(at: i) } },
                               onAddVia: { model.addVia() }) {
                    resultsFooter(model)
                }
                .reveal(order: 0)
                content(model)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .revealScope()
        .refreshable { await model.search() }
        .ambientBackground(.standard, glow: 0.4)
        .navigationTitle("Verbindungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.showsOptions = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Optionen")
            }
        }
        .onAppear { if model.phase == .idle { model.restartSearch() } }
        .task(id: model.rows.count) { await refreshLoop(model) }
        .onChange(of: model.phase) { _, phase in
            if phase == .failed(.rateLimited) { pausedUntil = Date().addingTimeInterval(120) }
        }
    }

    // MARK: States

    @ViewBuilder
    private func content(_ model: PlannerModel) -> some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading where model.rows.isEmpty:
            PlannerSkeletonList().padding(.top, Theme.Spacing.xs)
        case .failed(.unavailable(let reason)):
            PlannerUnavailableView(reason: reason) { app.isShowingSettings = true }.padding(.top, Theme.Spacing.xs)
        case .failed(.noConnection):
            PlannerNoConnectionView(isKlimaTicketOnly: model.isKlimaTicketOnly, onTomorrow: { tomorrowMorning(model) }, onWiden: { widen(model) })
                .padding(.top, Theme.Spacing.xs)
        case .failed(let failure) where model.rows.isEmpty:
            PlannerErrorBanner(failure: failure) { model.restartSearch() }.padding(.top, Theme.Spacing.xs)
        default:
            list(model)
        }
    }

    @ViewBuilder
    private func list(_ model: PlannerModel) -> some View {
        let stale: Bool = { if case .failed = model.phase { return true } else { return false } }()
        if stale, case .failed(let failure) = model.phase {
            if failure == .offline {
                PlannerOfflinePill(since: model.resultsUpdatedAt).padding(.top, Theme.Spacing.xxs)
            } else {
                PlannerErrorBanner(failure: failure) { model.restartSearch() }
            }
        }
        if model.canLoadEarlier {
            earlierLater("Früher", symbol: "chevron.up", model: model, earlier: true)
        }
        let visible = model.visibleRows
        VStack(spacing: Theme.Spacing.s) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                NavigationLink(value: PlannerRoute.detail(row.id)) {
                    ConnectionCard(summary: row.summary, badges: row.badges, coverage: row.coverage, ticketName: model.ticketName,
                                   price: row.price, priceText: priceText(row))
                }
                .buttonStyle(.pressableCard)
                .zoomSource(id: row.id, cornerRadius: Theme.Radius.card)
                .reveal(order: min(index + 1, 6))
                .onAppear {
                    if index >= visible.count - 2, model.canLoadLater { Task { await model.loadMore(earlier: false) } }
                }
            }
        }
        .opacity(stale ? 0.72 : 1)
        .motionAnimation(Motion.smooth, value: visible.map(\.id))
        if model.canLoadLater {
            earlierLater("Später", symbol: "chevron.down", model: model, earlier: false)
        }
        if model.hiddenByKlimaTicketCount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash").font(.system(size: 13, weight: .semibold))
                Text(model.hiddenByKlimaTicketCount == 1 ? "1 Verbindung ohne KlimaTicket ausgeblendet" : "\(model.hiddenByKlimaTicketCount) Verbindungen ohne KlimaTicket ausgeblendet")
                    .font(.footnote)
                Button("Filter aus") { widen(model) }.font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xs)
        }
        PlannerAttribution()
    }

    private func earlierLater(_ title: String, symbol: String, model: PlannerModel, earlier: Bool) -> some View {
        Button {
            Task { await model.loadMore(earlier: earlier) }
        } label: {
            HStack(spacing: 6) {
                if model.isLoadingMore { ProgressView().controlSize(.small) } else { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .disabled(model.isLoadingMore)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func priceText(_ row: ConnectionRow) -> String? {
        guard let quote = row.price.quote else { return nil }
        let euro = Format.euroPrecise(quote.amountEUR)
        switch row.coverage?.overall {
        case .covered?, .surcharge?: return "Mit KlimaTicket 0 Euro, Normalpreis \(euro)"
        case .notCovered?: return "Nicht im KlimaTicket enthalten, Ticket \(euro)"
        case .partial?: return "Teilweise im KlimaTicket, Teilstrecke \(euro)"
        default: return "Normalpreis \(euro), Gültigkeit prüfen"
        }
    }

    // MARK: Search card

    private func resultsFooter(_ model: PlannerModel) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button { model.showsTimeSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 15, weight: .semibold))
                    Text("\(model.isArrival ? "An" : "Ab") \(PlannerTimeText.chip(model.when ?? Date()))")
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .layoutPriority(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surfaceSecondary, in: .capsule)
            }
            .buttonStyle(.plain)
            Button { model.showsOptions = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isKlimaTicketOnly ? "ticket.fill" : "tram.fill").font(.system(size: 15, weight: .semibold))
                    Text(model.isKlimaTicketOnly ? "KlimaTicket" : "Alle")
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(model.isKlimaTicketOnly ? Theme.accentText : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(model.isKlimaTicketOnly ? Theme.accent.opacity(0.14) : Theme.surfaceSecondary, in: .capsule)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func slot(_ model: PlannerModel, _ id: String, _ caption: String, _ place: PlannerPlace?) -> RouteSlot {
        guard let place else { return RouteSlot(id: id, caption: caption, title: "Wählen", subtitle: nil, isPlaceholder: true) }
        if case .currentLocation = place {
            let stop = (id == "origin" ? model.resolvedOrigin : model.resolvedDestination) ?? model.hereStop?.location
            return RouteSlot(id: id, caption: caption, title: stop.map { DisplayNames.name($0.name) } ?? place.title,
                         subtitle: "Aktueller Standort", isPlaceholder: false, showsLocationArrow: true)
        }
        return RouteSlot(id: id, caption: caption, title: place.title, subtitle: place.subtitle, isPlaceholder: false)
    }

    private func tap(_ id: String, _ model: PlannerModel) {
        switch id {
        case "origin": model.beginSearch(.origin)
        case "destination": model.beginSearch(.destination)
        default: if id.hasPrefix("via-"), let i = Int(id.dropFirst(4)) { model.beginSearch(.via(i)) }
        }
        // The search field belongs to the tab: leave the results so it can take over.
        model.path = []
    }

    // MARK: Empty-state actions

    private func tomorrowMorning(_ model: PlannerModel) {
        let cal = Calendar.vienna
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        model.setWhen(cal.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow) ?? tomorrow, arrival: false)
        model.restartSearch()
    }

    private func widen(_ model: PlannerModel) {
        var options = model.options
        if model.isKlimaTicketOnly { options.klimaTicketOnly = false } else { options.products = .all; options.maxChanges = nil }
        model.options = options
        model.restartSearch()
    }

    // MARK: Refresh

    /// Realtime refresh of the listed connections every 60 s while this screen is visible (paused in the background, in
    /// Low Power Mode and for two minutes after a rate limit).
    private func refreshLoop(_ model: PlannerModel) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, scenePhase == .active, !ProcessInfo.processInfo.isLowPowerModeEnabled, Date() >= pausedUntil else { continue }
            await model.refreshRows()
        }
    }
}
