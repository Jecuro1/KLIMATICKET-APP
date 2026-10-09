import SwiftUI
import SwiftData
import WidgetKit
import KlimaCore

/// "Widgets" (CI screenshot `widgets`): every widget design at real size on a home-screen wallpaper,
/// the lock-screen set on a dark stage, the Control Center button and how to add them.
/// Uses the live ticket data (same builder the app uses for the real widgets), else the stored snapshot, else `.sample`.
struct WidgetGalleryView: View {
    @Environment(AppState.self) private var app
    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date, order: .reverse)
    private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    /// Already in the end state for CI screenshots.
    @State private var appeared = LaunchMode.isScreenshot
    @State private var showsNavigationTitle = false
    @State private var topic: WidGuideTopic = .home
    /// Captured on first appearance (see `backdrop`), so the background does not flip while Settings closes.
    @State private var isInSettingsSheet: Bool?
    /// CI screenshots of the lower part of the gallery ("widgets2", "widgets3") start scrolled to this section.
    var screenshotSection: WidGallerySection? = nil

    var body: some View {
        let snapshot = gallerySnapshot
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                        .widAppear(0, appeared)
                    WidHomeStage(snapshot: snapshot, appeared: appeared)
                    WidLockStage(snapshot: snapshot)
                        .widAppear(6, appeared)
                        .id(WidGallerySection.lock)
                    WidControlCenterSection { openAddTrip() }
                        .widAppear(7, appeared)
                    WidGuideSection(topic: $topic, snapshot: snapshot)
                        .widAppear(8, appeared)
                }
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 64
            } action: { _, isPastHeader in
                withAnimation(.easeInOut(duration: 0.2)) { showsNavigationTitle = isPastHeader }
            }
            .task {
                guard let screenshotSection else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(screenshotSection, anchor: .top)
            }
        }
        .background { backdrop }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Widgets")
                    .font(.headline)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavigationTitle)
            }
        }
        .onAppear {
            if isInSettingsSheet == nil { isInSettingsSheet = app.isShowingSettings }
            appeared = true
        }
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

    /// The add-trip sheet is presented by RootView, which cannot show it while the Settings sheet (where this
    /// screen is pushed) is up – SwiftUI presents one sheet at a time. Close Settings first, like FavoritesManagerView.
    private func openAddTrip() {
        guard app.isShowingSettings else {
            app.presentAddTrip()
            return
        }
        app.isShowingSettings = false
        let appState = app
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            appState.presentAddTrip()
        }
    }

    // MARK: Data

    private var gallerySnapshot: WidgetSnapshot {
        if let ticket = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID) {
            return WidgetSnapshotBuilder.make(ticket: ticket, trips: trips, favorites: favorites, catalog: app.catalog)
        }
        return WidgetSnapshot.load() ?? .sample
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

/// Scroll anchors inside the gallery (used by the CI screenshots of its lower part).
enum WidGallerySection: Hashable {
    /// The large Amortisation widget and the medium Schnellerfassung below it.
    case large
    /// Lock screen, Control Center and the how-to guide.
    case lock
}

// MARK: - Entrance motion

/// Staggered rise-in (settles within ~1.2 s). Opacity only with Reduce Motion; the screenshot
/// mode starts with `appeared == true`, so nothing animates there.
struct WidAppearModifier: ViewModifier {
    let index: Int
    let appeared: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 18)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.97, anchor: .top)
            .animation(animation, value: appeared)
    }

    private var animation: Animation {
        if reduceMotion { return .easeOut(duration: 0.3) }
        return .spring(duration: 0.6, bounce: 0.18).delay(Double(index) * 0.07)
    }
}

extension View {
    func widAppear(_ index: Int, _ appeared: Bool) -> some View {
        modifier(WidAppearModifier(index: index, appeared: appeared))
    }
}
