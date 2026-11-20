import SwiftUI
import SwiftData
import KlimaCore

// MARK: uebersicht – the Übersicht between the hero and the bottom padding, in the order of `DashLayoutStore` (docs/DASHBOARD_LAYOUT.md
// §2). Every card is built exactly as DashboardView built it before the layout existed (same views, paddings, reveal orders, feature
// gates and the wave-1 hooks), so the default layout looks as it did; only the gap above a card that left its old neighbour follows its
// new one. A card with nothing to show renders nothing, whatever the layout says; a switched-off feature (Funktionen) never shows.

/// What the cards read – one snapshot for the whole screen (DashboardView's body).
struct DashSectionContext {
    let ticket: TicketEntity
    let snapshot: AnalyticsSnapshot
    /// Every live trip, newest first (the Übersicht's @Query).
    let trips: [TripEntity]
    let favorites: [FavoriteRouteEntity]
    /// MARK: tripdetect – pending proposals.
    let candidates: [TripCandidateEntity]
    let isRecording: Bool

    var hasTrips: Bool { snapshot.summary.tripCount > 0 }
}

struct DashSectionList: View {
    let context: DashSectionContext

    @Environment(AppState.self) private var app
    private var store: DashLayoutStore { .shared }

    var body: some View {
        let visible = store.layout.visibleOrder
        let ranks = revealRanks(visible)
        ForEach(Array(visible.enumerated()), id: \.element) { index, id in
            DashSectionView(id: id, context: context, previous: index > 0 ? visible[index - 1] : nil,
                            revealOrder: ranks[id] ?? 2)
                .motionTransition(.opacity)
        }
    }

    /// Reveal orders in reading order (docs/MOTION.md §4). Only the cards that reveal themselves count, Ziele and Kennzahlen only once
    /// they have content – so the default layout keeps its old orders (Bilanz 2, Schnell erfassen 3, Vorschläge 4, Letzte Fahrten 5,
    /// Erfolg 6, Woche 7, Vorteile 8).
    private func revealRanks(_ visible: [DashSectionID]) -> [DashSectionID: Int] {
        var ranks: [DashSectionID: Int] = [:]
        var next = 2
        for id in visible {
            switch id {
            case .balance, .quickLog, .suggestions, .recentTrips, .achievements, .week, .perks:
                ranks[id] = next
                next += 1
            case .goals where !store.goals.goals.isEmpty, .kpis where !store.kpis.kinds.isEmpty:
                ranks[id] = next
                next += 1
            default:
                break
            }
        }
        return ranks
    }
}

/// One card of the Übersicht.
private struct DashSectionView: View {
    let id: DashSectionID
    let context: DashSectionContext
    /// The section above in the layout (nil: directly under the hero).
    let previous: DashSectionID?
    let revealOrder: Int

    @Environment(AppState.self) private var app

    var body: some View {
        let snapshot = context.snapshot
        let hasTrips = context.hasTrips
        switch id {
        case .balance:
            if hasTrips {
                VStack(spacing: 0) {
                    // Under the hero it overlaps the faded valley of the summit chart by a few points (spec §8.1); the route starts above it.
                    DashBalanceCard(snapshot: snapshot, catalog: app.catalog)
                        .celebrate(trigger: app.detection.acceptTick, haptic: nil)   // MARK: tripdetect – an accepted proposal: the counter pops
                        .celebrationBurst(trigger: app.detection.acceptTick)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, previous == nil ? -Theme.Spacing.xs : DashStyle.sectionSpacing)
                        .reveal(order: revealOrder)
                    // MARK: ai – "Warum lohnt sich mein Ticket?" (docs/LOCAL_AI.md §3.2)
                    AssistantWhyTicketButton(snapshot: snapshot)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .padding(.top, Theme.Spacing.xs)
                }
            } else {
                DashEmptyInviteCard(hasFavorites: !context.favorites.isEmpty) { app.presentAddTrip() }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, previous == nil ? Theme.Spacing.xs : DashStyle.sectionSpacing)
                    .reveal(order: revealOrder)
            }

        // MARK: yearreview – 1 Dec – 31 Jan, dismissible per year; also when a new ticket has no trip yet but the year has
        case .yearReview:
            YearReviewSeasonalCard(trips: context.trips)

        case .commute:
            CommuteCardSection(trips: context.trips, savedRoutes: context.favorites)   // MARK: commute – Pendel-Modus (docs/COMMUTE.md §1)

        case .quickLog:
            if hasTrips || !context.favorites.isEmpty {
                // No second "Neue Fahrt" button in the content – the header's "+" and the favourites do that (DESIGN.md §5.1 · 5).
                DashQuickLogSection(favorites: context.favorites, summary: snapshot.summary, ticketID: context.ticket.id,
                                    ticketIsCurrent: context.ticket.isActive, showsNewTripButton: false)
                    // The chip row carries 8 pt of vertical breathing room for glass and shadows → 10 pt below the card.
                    .padding(.top, 2)
                    .padding(.bottom, -Theme.Spacing.xs)
                    .reveal(order: revealOrder)
            }

        case .suggestions:   // MARK: tripdetect
            if !context.candidates.isEmpty || context.isRecording {
                TripInboxSection(candidates: context.candidates, isRecording: context.isRecording)
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, DashStyle.sectionSpacing)
                    .reveal(order: revealOrder)
                    .motionTransition(.rise)
            }

        case .calendarSuggestions:
            CalendarSuggestionsSection(trips: context.trips)   // MARK: calendarsuggestions – „Termine mit Zugfahrt?“ (docs/CALENDAR_SUGGESTIONS.md §2)

        case .recentTrips:
            if !context.trips.isEmpty {
                DashRecentTripsSection(trips: Array(context.trips.prefix(5)))
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, context.candidates.isEmpty ? Theme.Spacing.m : DashStyle.sectionSpacing)
                    .reveal(order: revealOrder)
                    .scrollCardTransition()
            }

        case .goals:
            DashGoalsSection(snapshot: snapshot)
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, DashStyle.sectionSpacing)
                .reveal(order: revealOrder)

        case .kpis:
            DashKpiSection(snapshot: snapshot, trips: context.trips)
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, DashStyle.sectionSpacing)
                .reveal(order: revealOrder)

        case .achievements:
            if hasTrips {
                DashAchievementTeaser(next: snapshot.nextAchievement,
                                      unlockedCount: snapshot.unlockedAchievements.count,
                                      totalCount: snapshot.achievements.count) {
                    app.isShowingAchievements = true
                }
                .zoomSource(id: DashZoomID.gipfelbuch, cornerRadius: Theme.Radius.card)
                .reveal(order: revealOrder)
                .scrollCardTransition()
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, DashStyle.sectionSpacing)
                .featureGated(.achievementsTeaser)   // MARK: funktionen
            }

        case .week:
            if hasTrips {
                DashWeekInsightCard(stats: DashWeekStats.make(fromNewestFirst: context.trips))
                    .reveal(order: revealOrder)
                    .scrollCardTransition()
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    // Directly under „Nächster Erfolg“ the two read as one block (card spacing); otherwise a section gap.
                    .padding(.top, previous == .achievements && FeatureCenter.shared.isOn(.achievementsTeaser, app: app)
                             ? DashStyle.cardSpacing : DashStyle.sectionSpacing)
                    .featureGated(.weekInsight)   // MARK: funktionen
            }

        // MARK: benefits
        case .perks:
            PerkSummaryCard()
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, hasTrips && (previous == .week || previous == .achievements)
                         ? DashStyle.cardSpacing : DashStyle.sectionSpacing)
                .reveal(order: revealOrder)
                .scrollCardTransition()
                .featureGated(.perksCard)   // MARK: funktionen
        }
    }
}
