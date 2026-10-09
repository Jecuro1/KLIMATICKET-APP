import SwiftUI
import SwiftData
import WidgetKit
import KlimaCore

/// "Widgets" (CI screenshots `widgets`, `widgets2`, `widgets3`): every widget design at real size on a home-screen
/// wallpaper, the lock-screen set on a dark stage, the two controls, Siri & Kurzbefehle and how to add them.
/// Uses the live ticket data (same builder the app uses for the real widgets), else the stored snapshot, else `.sample`.
/// The previews' favourite buttons are live for show: a tap logs the favourite *in the preview* (figures roll, "+"
/// turns into a checkmark) – nothing is saved.
struct WidgetGalleryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    /// Built outside `body` (fetch + analytics): on appear, after every save (trips, favourites, tickets, sync merges)
    /// and when another ticket is selected – not on each render pass.
    @State private var snapshot: WidgetSnapshot?
    /// "Probier's aus": the snapshot with the favourites tapped in the previews applied (never saved).
    @State private var preview: WidgetSnapshot?
    @State private var previewLogs = 0
    @State private var condense = ScrollCondense()
    @State private var topic: WidGuideTopic = .home
    /// Captured on first appearance (see `backdrop`), so the background does not flip while Settings closes.
    @State private var isInSettingsSheet: Bool?
    /// CI screenshots of the lower part of the gallery ("widgets2" … "widgets4") start scrolled to this section.
    var screenshotSection: WidGallerySection? = nil
    /// CI screenshot "widgetsTryOut": the first favourite is tapped in the previews right away.
    var screenshotTriesFavorite = false

    var body: some View {
        let shown = preview ?? snapshot ?? .sample
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                        .reveal(order: 0)
                    WidHomeStage(snapshot: shown, isPreviewing: preview != nil, onReset: resetPreview)
                    WidLockStage(snapshot: shown)
                        .reveal(order: 6)
                        .scrollCardTransition()
                        .id(WidGallerySection.lock)
                    WidStandByStage(snapshot: shown)
                        .reveal(order: 7)
                        .scrollCardTransition()
                    WidControlCenterSection(favorite: shown.favorites.first) { openAddTrip() }
                        .reveal(order: 8)
                        .scrollCardTransition()
                    WidSiriSection(snapshot: shown)
                        .reveal(order: 8)
                        .scrollCardTransition()
                        .id(WidGallerySection.siri)
                    WidGuideSection(topic: $topic, snapshot: shown)
                        .reveal(order: 8)
                        .scrollCardTransition()
                }
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .tracksScrollCondense(condense, distance: 64)
            .revealScope()
            .task {
                guard let screenshotSection else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(screenshotSection, anchor: .top)
                if screenshotTriesFavorite, let favorite = (snapshot ?? .sample).favorites.first {
                    logInPreview(favorite)
                }
            }
        }
        .environment(\.widPreviewAction, WidPreviewAction(logFavorite: logInPreview))
        .haptic(.success, trigger: previewLogs)
        .background { backdrop }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                WidGalleryTitle(condense: condense)
            }
        }
        .onAppear {
            if isInSettingsSheet == nil { isInSettingsSheet = app.isShowingSettings }
            if snapshot == nil { reloadSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            reloadSnapshot()
        }
        .onChange(of: app.settings.selectedTicketID) { reloadSnapshot() }
    }

    // MARK: Background & actions

    /// Inside the Settings sheet: the calm sheet surface with a pale sky (DESIGN.md §2 – no full sky mesh in sheets),
    /// otherwise (e.g. the CI screenshot) the alpine sky like every other screen.
    @ViewBuilder
    private var backdrop: some View {
        if isInSettingsSheet ?? app.isShowingSettings {
            ZStack(alignment: .top) {
                Theme.sheetBackground
                AmbientBackground(style: .standard, glow: 0.6)
                    .opacity(0.55)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black.opacity(0.65), location: 0.22),
                                               .init(color: .clear, location: 0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            AmbientBackground()
        }
    }

    /// "Ausprobieren" behaves like the real control: the add-trip sheet is RootView's, which cannot show it while the
    /// Settings sheet (where this screen is pushed) is up – `presentAddTripFromOutside` closes it first.
    private func openAddTrip() {
        app.presentAddTripFromOutside()
    }

    /// A favourite tapped in a preview: the widget's own optimistic update, applied to the preview only. The figures
    /// roll to their new values and the button confirms; the checkmark goes back to "+" after a moment (on the
    /// Home Screen after a minute).
    private func logInPreview(_ favorite: WidgetSnapshot.Favorite) {
        var next = preview ?? snapshot ?? .sample
        next.apply(favorite: favorite, date: Date())
        withMotion(Motion.bouncy) { preview = next }
        previewLogs += 1
        guard !MotionPolicy.isStatic else { return }   // CI screenshot: keep the confirmation
        let log = next.recentLog
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard preview?.recentLog == log else { return }   // a newer tap keeps its own confirmation
            withMotion(Motion.smooth) { preview?.recentLog = nil }
        }
    }

    private func resetPreview() {
        withMotion(Motion.smooth) { preview = nil }
    }

    // MARK: Data

    /// The ticket's period trips only (not every ticket year) – the same inputs `Repository.refreshWidgets()` uses.
    private func reloadSnapshot() {
        let repo = Repository(context: context, app: app)
        guard let ticket = Analytics.activeTicket(in: repo.liveTickets(), selectedID: app.settings.selectedTicketID) else {
            snapshot = WidgetSnapshot.load() ?? .sample
            return
        }
        let fresh = WidgetSnapshotBuilder.make(ticket: ticket, trips: repo.periodTrips(ticket), lastTrip: repo.lastTrip(),
                                               favorites: repo.liveFavorites(), catalog: app.catalog)
        // `generatedAt` is the only field that differs on every build – keep the old value so the views stay put.
        if var current = snapshot {
            current.generatedAt = fresh.generatedAt
            if current == fresh { return }
        }
        snapshot = fresh
        preview = nil   // real data changed: the try-out starts over from it
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: "Für Home- & Sperrbildschirm")
            Text("Widgets")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Dein Ticket auf einen Blick – und Lieblingsfahrten mit einem Tipp erfassen, ohne die App zu öffnen.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
    }
}

/// Inline navigation title that fades in over the last part of the header's scroll distance. Reads the quantised
/// `ScrollCondense` itself, so only this view re-renders while scrolling.
private struct WidGalleryTitle: View {
    let condense: ScrollCondense

    var body: some View {
        let visible = condense.value > 0.5
        Text("Widgets")
            .font(.headline)
            .opacity(Double(min(max((condense.value - 0.5) * 2, 0), 1)))
            .accessibilityHidden(!visible)
    }
}

/// Scroll anchors inside the gallery (used by the CI screenshots of its lower part).
enum WidGallerySection: Hashable {
    /// The large Amortisation widget and the medium Schnellerfassung below it.
    case large
    /// Lock screen, Control Center and the how-to guide.
    case lock
    /// Siri & Kurzbefehle and the how-to guide.
    case siri
}
