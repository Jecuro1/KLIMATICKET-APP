import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – the ways into the Verspätungs-Tagebuch (docs/DELAY_DIARY.md §1): the Statistik card (zooms into the
// screen), the link in Fahrgastrechte and klimabilanz://delays (a sheet over whatever is open).

/// Statistik: „Verspätungs-Tagebuch“ for the ticket year the screen shows.
struct DelayDiaryEntryCard: View {
    let period: TicketPeriod

    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }, sort: \TripEntity.date)
    private var trips: [TripEntity]

    static let zoomID = "delayDiary.entry"

    var body: some View {
        let year = DelayDiaryMemo.year(trips: trips, start: period.start, end: max(period.start, period.end), now: Date(),
                                       options: DelayDiarySettings.shared.options)
        NavigationLink {
            DelayDiaryView(period: period)
                .zoomDestination(id: Self.zoomID)
        } label: {
            GlassCard(padding: Theme.Spacing.m + 2) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .top, spacing: Theme.Spacing.s + 2) {
                        DelayDiaryTile(isLate: year.lateCount > 0 || year.isEmpty)
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker(text: DelayDiaryText.title)
                            Text(headline(year))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail(year))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                    }
                    if !year.isEmpty {
                        StatsGrowOnView { grow in
                            DelayShareBar(onTime: year.onTimeCount, late: year.lateCount, grow: grow)
                                .frame(height: 8)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .zoomSource(id: Self.zoomID, cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DelayDiaryText.title)
        .accessibilityValue("\(headline(year)). \(detail(year))")
        .accessibilityHint("Öffnet deine erfassten Verspätungen pro Gültigkeitsmonat")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("delayDiary.entry")
    }

    private func headline(_ year: DelayDiaryYear) -> String {
        if let share = year.onTimeShare { return "\(DelayDiaryText.percent(share)) pünktlich · persönlich" }
        if year.recordedCount > 0 { return "\(DelayDiaryText.fahrten(year.recordedCount)) eingetragen" }
        return "Waren deine Züge pünktlich?"
    }

    private func detail(_ year: DelayDiaryYear) -> String {
        if year.isEmpty { return "Halte fest, welche Fahrten verspätet waren – dein eigenes Tagebuch, mit PDF zum Teilen." }
        var text = "\(year.lateCount) verspätet ab \(year.threshold)\u{00A0}Min. · \(year.recordedCount) von \(DelayDiaryText.fahrten(year.tripCount)) erfasst"
        if year.onTimeShare == nil { text += " · \(DelayDiaryText.tooFewForShare)" }
        return text
    }
}

/// On time (pine) and late (hatched dawn) side by side – the Statistik card's bar.
struct DelayShareBar: View {
    let onTime: Int
    let late: Int
    var grow: Double = 1

    var body: some View {
        GeometryReader { geo in
            let total = max(onTime + late, 1)
            let width = geo.size.width
            let onTimeWidth = width * CGFloat(onTime) / CGFloat(total)
            let gap: CGFloat = onTime > 0 && late > 0 ? 3 : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textTertiary.opacity(0.14))
                HStack(spacing: gap) {
                    if onTime > 0 {
                        Capsule().fill(Theme.pine).frame(width: max(0, onTimeWidth - gap / 2))
                    }
                    if late > 0 {
                        DelayHatch(color: Theme.dawn).clipShape(Capsule()).frame(width: max(0, width - onTimeWidth - gap / 2))
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: width * CGFloat(min(max(grow, 0), 1)))
                }
            }
        }
    }
}

/// Fahrgastrechte: „Mein Verspätungs-Tagebuch“ – pushes the diary inside the presenter's NavigationStack.
struct DelayDiaryRightsLink: View {
    var body: some View {
        NavigationLink {
            DelayDiaryView()
        } label: {
            GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
                HStack(spacing: Theme.Spacing.s) {
                    DelayDiaryTile(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mein Verspätungs-Tagebuch")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Deine Verspätungen pro Gültigkeitsmonat festhalten – mit PDF, falls du nachfragen willst.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet dein Verspätungs-Tagebuch")
        .accessibilityIdentifier("delayDiary.rightsLink")
    }
}

// MARK: - Deep link

/// klimabilanz://delays opens the diary in a sheet (RootView: `.delayDiaryLinkHost()`), with the same rules as
/// klimabilanz://timebalance: app-level sheets close first, a trip editor, a required update and the Jahresrückblick are never
/// covered, nothing during the onboarding.
@Observable
@MainActor
final class DelayDiaryLink {
    static let shared = DelayDiaryLink()
    var isPresented = false

    func open(closing app: AppState, afterSheet: Bool = false) {
        guard DelayDiaryRelease.isLive, !isPresented, app.tripDraft == nil, app.yearReviewRequest == nil,
              app.settings.onboardingCompleted || LaunchMode.isSandboxed else { return }
        if app.updates.isPresentingSheet && app.updates.isRequired { return }
        guard afterSheet || app.isShowingSettings || app.isShowingAchievements || app.updates.isPresentingSheet
                || TimeBalanceLink.shared.isPresented else {
            isPresented = true
            return
        }
        app.isShowingSettings = false
        app.isShowingAchievements = false
        app.updates.isPresentingSheet = false
        TimeBalanceLink.shared.isPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // the sheet's dismissal animation (as for klimabilanz://year)
            if app.tripDraft == nil, app.yearReviewRequest == nil { self.isPresented = true }
        }
    }
}

extension View {
    /// Presents the Verspätungs-Tagebuch when klimabilanz://delays arrives.
    func delayDiaryLinkHost() -> some View {
        modifier(DelayDiaryLinkHost())
    }
}

private struct DelayDiaryLinkHost: ViewModifier {
    @Bindable private var link = DelayDiaryLink.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $link.isPresented) {
            NavigationStack {
                DelayDiaryView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .close) {
                                link.isPresented = false
                            }
                            .accessibilityLabel("Schließen")
                        }
                    }
            }
        }
    }
}
