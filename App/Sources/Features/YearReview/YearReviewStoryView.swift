import SwiftUI
import SwiftData
import KlimaCore

/// Initial state for CI screenshots (`ScreenshotRouter`: yearReview, yearReview2 … yearReviewShare, yearReviewEmpty).
struct YearReviewScreenshotSetup {
    var page: YearReviewPageKind?
    var share = YearReviewShareOptions()
    /// Pretend there are no trips (the friendly empty state).
    var forceEmpty = false
    /// Start on the ticket year (the demo ticket is running) whatever the date: the screenshots stay comparable in December.
    var prefersTicketPeriod = true
}

/// "Dein Jahr" – the full-screen story (docs/YEAR_REVIEW.md): segmented progress bars on top, one page at a time, tap the
/// right two thirds for the next page and the left third for the previous one, hold to pause, swipe down to close, 6 s per
/// page. The story does not advance on its own with VoiceOver, Switch Control, Reduce Motion or accessibility text sizes
/// (manual only, cross-fade instead of movement); the Close and Zurück / Weiter buttons are always there.
struct YearReviewStoryView: View {
    let request: YearReviewRequest
    var setup: YearReviewScreenshotSetup?
    let onClose: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date) private var trips: [TripEntity]

    @State private var store: YearReviewStore
    @State private var areaWidth: CGFloat = 390
    @State private var dragOffset: CGFloat = 0
    @State private var isTouching = false
    @State private var holdTask: Task<Void, Never>?

    init(request: YearReviewRequest, setup: YearReviewScreenshotSetup? = nil, onClose: @escaping () -> Void) {
        self.request = request
        self.setup = setup
        self.onClose = onClose
        _store = State(initialValue: YearReviewStore(request: request))
    }

    // MARK: Body

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                topBar
                pageArea
                bottomBar
            }
        }
        .offset(y: dragOffset)
        .opacity(1 - min(dragOffset / 600, 0.5))
        .onAppear(perform: load)
        .onChange(of: dataStamp) { _, _ in load() }
        .task(id: driverKey) {
            guard driverKey.runs else { return }
            await store.runClock()
        }
        .haptic(.selection, trigger: store.manualSteps)
        .accessibilityAction(.escape) { onClose() }
    }

    // MARK: Data

    /// A cheap fingerprint of the stored data: a sync or an edit while the story is open rebuilds it.
    private var dataStamp: Int {
        var hasher = Hasher()
        hasher.combine(trips.count)
        hasher.combine(tickets.count)
        hasher.combine(trips.last?.updatedAt)
        return hasher.finalize()
    }

    private func load() {
        let wasLoaded = store.isLoaded
        store.reload(makeInputs())
        guard !wasLoaded, let setup else { return }
        if setup.prefersTicketPeriod, let ticket = store.choices.first(where: { $0.kind == .ticket }) { store.select(ticket) }
        store.shareOptions = setup.share
        if let page = setup.page { store.go(to: page) }
    }

    private func makeInputs() -> YearReviewInputs {
        let live = Array(tickets)
        let active = Analytics.activeTicket(in: live, selectedID: app.settings.selectedTicketID)
        let stations = app.stations
        return YearReviewInputs(records: setup?.forceEmpty == true ? [] : trips.map(\.record), tickets: live.map(\.period),
                                preferredTicket: active?.period, holderName: active?.holderName ?? "", catalog: app.catalog,
                                stations: { stations.station(id: $0) }, now: Date())
    }

    // MARK: Auto-advance

    /// The story moves on by itself only when nothing needs more time: not with VoiceOver, Switch Control, Reduce Motion,
    /// accessibility text sizes or in CI screenshots.
    private var advancesAutomatically: Bool {
        !(voiceOverEnabled || switchControlEnabled || reduceMotion || typeSize.isAccessibilitySize || MotionPolicy.isStatic)
    }

    private struct DriverKey: Hashable {
        var index: Int
        var runs: Bool
    }

    private var driverKey: DriverKey {
        let runs = advancesAutomatically && !store.isHolding && scenePhase == .active && store.isLoaded && !store.isLast
            && store.pageCount > 0 && dragOffset == 0
        return DriverKey(index: store.index, runs: runs)
    }

    // MARK: Background

    private var backdrop: some View {
        ZStack {
            AmbientBackground(style: .standard, glow: 0.55, animated: false)
                .ignoresSafeArea()
            YearReviewGlow(kind: store.current?.kind ?? .intro)
                .id(store.current?.kind)
                .transition(.opacity)
                .motionAnimation(Motion.gentle, value: store.current?.kind)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if store.pageCount > 0 {
                YearReviewProgressBar(store: store, advancesAutomatically: advancesAutomatically)
            }
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Kicker(text: "Dein Jahr")
                    if let period = store.period {
                        Text(period.title())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                if store.pageCount > 0 {
                    Text("\(store.index + 1) / \(store.pageCount)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Schließen")
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: Pages

    private var pageArea: some View {
        ZStack {
            if let page = store.current, let review = store.review {
                YearReviewPageView(page: page, ctx: YearReviewPageContext(review: review, store: store,
                                                                         number: store.index + 1, total: store.pageCount))
                    .id(page.id)
                    .motionTransition(stepTransition)
            } else if store.isLoaded {
                emptyState
                    .motionTransition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .gesture(storyGesture, including: gesturesEnabled ? .all : .none)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { areaWidth = $0 }
    }

    /// The new page enters from the side it is reached from; Reduce Motion cross-fades (`motionTransition`).
    private var stepTransition: AnyTransition {
        let dx: CGFloat = store.movedForward ? 28 : -28
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: dx)), removal: .opacity.combined(with: .offset(x: -dx)))
    }

    private var emptyState: some View {
        let missing = store.period.map { "Für \($0.title()) gibt es noch keine Fahrten." }
        return ScrollView {
            EmptyStateView(symbol: "mountain.2", title: "Dein Jahr beginnt mit der ersten Fahrt",
                           message: (missing.map { $0 + " " } ?? "") + "Sobald du Fahrten erfasst, bekommst du hier deinen Rückblick: Ersparnis, Strecke, Rekorde und Klima.",
                           actionTitle: "Fahrt erfassen") {
                app.closeYearReviewAndAddTrip()
            }
            .padding(.top, Theme.Spacing.xxl)
        }
    }

    // MARK: Gestures

    /// Tap right two thirds = next, left third = back, hold = pause, swipe down = close. Off for the last page (its
    /// controls are buttons and switches), for accessibility text sizes (the page scrolls) and for the empty state.
    private var gesturesEnabled: Bool {
        guard let page = store.current else { return false }
        return page.kind != .finale && !typeSize.isAccessibilitySize
    }

    private var storyGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTouching {
                    isTouching = true
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        if !Task.isCancelled { store.isHolding = true }
                    }
                }
                if value.translation.height > 12, abs(value.translation.height) > abs(value.translation.width) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                isTouching = false
                let wasHolding = store.isHolding
                store.isHolding = false
                let dx = value.translation.width, dy = value.translation.height
                if dy > 90, abs(dy) > abs(dx) * 1.5 {
                    onClose()
                    return
                }
                if dragOffset != 0 { withMotion(Motion.smooth) { dragOffset = 0 } }
                // A tap: short, and the finger stayed put.
                guard !wasHolding, abs(dx) < 12, abs(dy) < 12 else { return }
                if value.location.x < areaWidth / 3 {
                    store.back(manual: true)
                } else {
                    store.next(manual: true)
                }
            }
    }

    // MARK: Bottom bar

    private var showsPeriodChips: Bool {
        store.choices.count > 1 && (store.current == nil || store.current?.kind == .intro)
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if showsPeriodChips { periodChips }
            if store.pageCount > 0 {
                HStack(spacing: Theme.Spacing.s) {
                    Button { store.back(manual: true) } label: {
                        Label("Zurück", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isFirst)
                    if store.isLast {
                        Button(action: onClose) {
                            Label("Fertig", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.prominentTint)
                    } else {
                        Button { store.next(manual: true) } label: {
                            HStack(spacing: 6) {
                                Text("Weiter")
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.prominentTint)
                    }
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// "Ticket-Jahr 2026/27" · "Kalenderjahr 2026" · … – what the first page offers.
    private var periodChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(store.choices) { period in
                    Chip(title: period.title(), symbol: period.kind == .ticket ? "ticket.fill" : "calendar",
                         isSelected: period.id == store.selectedPeriodID) {
                        withMotion(Motion.snappy) { store.select(period) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .haptic(.selection, trigger: store.selectedPeriodID)
    }
}
