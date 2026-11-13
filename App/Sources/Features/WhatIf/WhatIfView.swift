import SwiftUI
import SwiftData
import KlimaCore

/// „Was wäre wenn?“ – which ticket pays off for me, and what if I travel more or less? Works before the purchase (own
/// assumptions) and on the real trips (slider ×0,5 … ×2). No network, no ÖBB access: everything is calculated on the device
/// from the bundled tariffs (docs/WHATIF.md).
///
/// This view only owns the queries and turns them into a `WhatIfSource` once per change of the stored data; the screen below
/// keeps the inputs, so dragging a slider never rebuilds the source.
struct WhatIfView: View {
    var launch: WhatIfLaunch = .automatic
    /// CI screenshots: saved scenarios shown without touching the device's defaults.
    var scenarios: [WhatIfScenario]? = nil

    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]

    var body: some View {
        let source = WhatIfSource.make(trips: trips, tickets: tickets, selectedTicketID: app.settings.selectedTicketID)
        WhatIfScreen(source: source, launch: launch, scenarios: scenarios)
    }
}

/// The screen itself.
struct WhatIfScreen: View {
    let source: WhatIfSource
    @State private var model: WhatIfModel
    @State private var pick: WhatIfPick?
    @State private var titleChrome = TktTitleChrome()
    /// The first result of the screen is not announced – only changes the user makes.
    @State private var hasAnnounced = false

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    init(source: WhatIfSource, launch: WhatIfLaunch, scenarios: [WhatIfScenario]? = nil) {
        self.source = source
        _model = State(initialValue: WhatIfModel(source: source, launch: launch, scenarios: scenarios))
    }

    var body: some View {
        @Bindable var model = model
        let calculator = WhatIfCalculator(catalog: app.catalog, relations: app.relations, stations: app.stations)
        let result = model.result(using: calculator, source: source)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                    .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
                    .reveal(order: 0)
                modePicker(selection: $model.mode)
                    .reveal(order: 1)
                content(result: result)
                    .reveal(order: 2)
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .revealScope()
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .tktInlineTitleTracking(titleChrome)
        .ambientBackground(.standard, glow: 0.5)
        .navigationTitle("Was wäre wenn?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TktInlineTitle(title: "Was wäre wenn?", chrome: titleChrome)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(item: $pick) { target in
            NavigationStack {
                StationPickerView(title: target.isFrom ? "Von" : "Nach") { station in
                    model.setStation(station, routeID: target.routeID, isFrom: target.isFrom)
                    // A new route asks for both ends in a row.
                    if target.isFrom, let route = model.assumptions.routes.first(where: { $0.id == target.routeID }), route.toStationID.isEmpty {
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            pick = WhatIfPick(routeID: target.routeID, isFrom: false)
                        }
                    }
                }
            }
        }
        .task(id: announcement(result)) {
            guard !MotionPolicy.isScreenshot else { return }   // MARK: review-themes – Bewegung „Aus“ keeps VoiceOver announcements
            guard hasAnnounced else {
                hasAnnounced = true
                return
            }
            // Debounced: while a slider is dragged the task restarts with every value, only the pause is announced.
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(announcement(result)).post()
        }
    }

    // MARK: Mode

    /// The glass segments; at the accessibility text sizes two full-width buttons (the titles do not fit side by side).
    @ViewBuilder
    private func modePicker(selection: Binding<WhatIfModel.Mode>) -> some View {
        if typeSize.isAccessibilitySize {
            WhatIfStackedChoice(selection: selection, options: WhatIfModel.Mode.allCases) { $0.title }
        } else {
            GlassSegmentedPicker(selection: selection, options: WhatIfModel.Mode.allCases) { Text($0.title) }
                .accessibilityLabel("Rechnen mit")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Rechenhilfe · keine Beratung")
            Text("Was wäre wenn?")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Rechne durch, welches Ticket sich lohnt – wenn du mehr oder weniger fährst, auch ohne eigene Fahrten.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Content

    @ViewBuilder
    private func content(result: WhatIfResult) -> some View {
        @Bindable var model = model
        switch model.mode {
        case .history:
            if source.history == nil {
                WhatIfNoHistoryCard { withMotion(Motion.smooth) { model.mode = .assumptions } }
                    .motionTransition(.rise)
            } else {
                if result.state == .noTrips || result.state == .ready {
                    WhatIfResultCard(result: result, usesHistory: true)
                }
                WhatIfHistoryControls(model: model, source: source, result: result)
                rankingAndMore(result: result)
            }
        case .assumptions:
            if model.assumptions.routes.isEmpty {
                WhatIfInviteCard(onPreset: { preset in withMotion(Motion.smooth) { model.apply(preset) } },
                                 onCustom: addRoute)
                    .motionTransition(.rise)
            } else {
                if result.state != .needsRoutes {
                    WhatIfResultCard(result: result, usesHistory: false)
                }
                WhatIfAssumptionsControls(model: model, result: result, onPick: { pick = $0 }, onAddRoute: addRoute)
                rankingAndMore(result: result)
            }
        }
    }

    @ViewBuilder
    private func rankingAndMore(result: WhatIfResult) -> some View {
        if result.state == .ready {
            WhatIfRankingCard(result: result)
        }
        WhatIfScenariosCard(model: model, result: result,
                            basis: WhatIfText.historyBasis(baseline: source.baseline, tripCount: source.tripCount))
        WhatIfFootnote(result: result, usesHistory: model.mode == .history)
            .padding(.horizontal, Theme.Spacing.xxs)
            .padding(.top, Theme.Spacing.xxs)
    }

    private func addRoute() {
        var created: UUID?
        withMotion(Motion.smooth) { created = model.addRoute() }
        if let created { pick = WhatIfPick(routeID: created, isFrom: true) }
    }

    // MARK: Announcement

    /// What VoiceOver hears after the user changed something: the sentence and the yearly difference.
    private func announcement(_ result: WhatIfResult) -> String {
        var text = WhatIfText.headline(result, usesHistory: model.mode == .history)
        if let delta = WhatIfText.delta(result) { text += ". \(delta.sentence)" }
        return text
    }
}
