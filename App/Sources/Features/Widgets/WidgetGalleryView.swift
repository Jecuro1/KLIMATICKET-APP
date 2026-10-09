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

    var body: some View {
        let snapshot = gallerySnapshot
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                    .widAppear(0, appeared)
                WidHomeStage(snapshot: snapshot, appeared: appeared)
                WidLockStage(snapshot: snapshot)
                    .widAppear(6, appeared)
                WidControlCenterSection { app.presentAddTrip() }
                    .widAppear(7, appeared)
                WidGuideSection(topic: $topic, snapshot: snapshot)
                    .widAppear(8, appeared)
            }
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ambientBackground()
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
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, isPastHeader in
            withAnimation(.easeInOut(duration: 0.2)) { showsNavigationTitle = isPastHeader }
        }
        .onAppear { appeared = true }
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
