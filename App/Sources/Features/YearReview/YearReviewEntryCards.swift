import SwiftUI
import SwiftData
import KlimaCore

// Two of the four ways into the year story: the Statistik card and the seasonal card on the Übersicht (the other two are
// the deep link klimabilanz://year[/2026] and the tap on the Jahresrückblick widget). Both zoom into the story.

/// Statistik: "Dein Jahr" – shown once at least one trip exists (the caller shows it only then).
struct YearReviewEntryCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.yearReviewZoom) private var zoom

    var body: some View {
        Button {
            app.presentYearReview(source: .statistics)
        } label: {
            GlassCard(padding: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s + 2) {
                    YearReviewTile()
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Dein Jahr")
                        Text("Dein KlimaTicket-Jahr als Story")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Ersparnis, Strecke, Rekorde und Klima – zum Durchtippen.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: YearReviewZoom.id(for: .statistics), cornerRadius: Theme.Radius.card, in: zoom)
        .accessibilityLabel("Dein Jahr: Rückblick als Story")
        .accessibilityHint("Öffnet deinen Jahresrückblick im Vollbild")
        .accessibilityIdentifier("yearReview.entry.statistics")
    }
}

/// Übersicht: 1 Dec – 31 Jan, once the year has trips; dismissible per year (UserDefaults, one key per year).
struct YearReviewSeasonalCard: View {
    let trips: [TripEntity]
    /// CI only: pretends it is the season of this year (the card is otherwise invisible outside 1 Dec – 31 Jan).
    var seasonOverride: Int? = nil

    @Environment(AppState.self) private var app
    @Environment(\.yearReviewZoom) private var zoom
    @State private var justDismissed = false

    static func dismissedKey(_ year: Int) -> String { "yearReview.dismissed.\(year)" }

    var body: some View {
        if let year = seasonOverride ?? YearReviewPeriods.seasonalYear(now: Date()), !justDismissed,
           !UserDefaults.standard.bool(forKey: Self.dismissedKey(year)) {
            let records = trips.filter { Calendar.vienna.component(.year, from: $0.date) == year }.map(\.record)
            if !records.isEmpty {
                card(year: year, records: records)
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.top, Theme.Spacing.xs)
                    .motionTransition(.rise)
            }
        }
    }

    private func card(year: Int, records: [TripRecord]) -> some View {
        let count = JourneySummary.tripCount(records)
        let value = records.reduce(0) { $0 + $1.totalValue }
        return GlassCard(padding: Theme.Spacing.m, tint: Theme.dawn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s + 2) {
                    YearReviewTile()
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Jahresrückblick")
                        Text("Dein \(String(year)) ist da")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(StatsNames.trips(count)) · \(SummitFigures.euro(value)) Fahrtwert – als Story zum Durchtippen und Teilen.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        UserDefaults.standard.set(true, forKey: Self.dismissedKey(year))
                        withMotion(Motion.smooth) { justDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.surfaceSecondary, in: .circle)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Jahresrückblick ausblenden")
                    .haptic(.selection, trigger: justDismissed)
                }
                Button {
                    app.presentYearReview(year: year, source: .overview)
                } label: {
                    Text("Rückblick ansehen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("yearReview.entry.overview")
            }
        }
        .zoomSource(id: YearReviewZoom.id(for: .overview), cornerRadius: Theme.Radius.card, in: zoom)
    }
}

/// The small tile in front of both cards: the route gradient with a summit.
struct YearReviewTile: View {
    var body: some View {
        Image(systemName: "mountain.2.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: 52, height: 52)
            .background(Theme.ctaGradient, in: .rect(cornerRadius: Theme.Radius.chip + 2, style: .continuous))
            .accessibilityHidden(true)
    }
}
