import SwiftUI
import KlimaCore

// MARK: uebersicht – „Ziele“: up to three own goals, each with a ring, the state in words (the ring is never the only sign), what is
// left with a pace that is a fact („etwa 1 pro Woche“) and a projection only when it is called „Prognose“. Reaching a goal pops its ring
// once per goal and period with one .success haptic (ledger `goals.ledger.v1`), only while the Übersicht is in view – no confetti.

/// Format.* for KlimaCore's goal texts.
enum DashGoalFormat {
    static let formatter = GoalFormatter(euro: { Format.euro($0, decimals: 0) }, kg: { Format.kg($0) },
                                         day: { Format.dayMonth($0) })
}

enum DashGoalEvaluation {
    @MainActor
    static func progress(_ goals: [Goal], snapshot: AnalyticsSnapshot, catalog: TariffCatalog, now: Date = Date()) -> [GoalProgress] {
        goals.map {
            GoalEvaluator.evaluate($0, trips: snapshot.trips, ticket: snapshot.ticket, summary: snapshot.summary, now: now,
                                   emissions: catalog.emissions)
        }
    }
}

struct DashGoalsSection: View {
    let snapshot: AnalyticsSnapshot

    @Environment(AppState.self) private var app
    private var store: DashLayoutStore { .shared }

    var body: some View {
        let goals = store.goals.goals
        if !goals.isEmpty {
            let progress = DashGoalEvaluation.progress(goals, snapshot: snapshot, catalog: app.catalog)
            VStack(alignment: .leading, spacing: DashStyle.cardSpacing) {
                SectionHeader(title: "Ziele", actionTitle: "Anpassen") { store.openEditor(at: .goals) }
                    .padding(.horizontal, DashStyle.headerInset)
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(progress) { item in
                            if item.id != progress.first?.id {
                                Rectangle()
                                    .fill(Theme.separator)
                                    .frame(height: 1)
                                    .padding(.leading, Theme.Spacing.m + DashGoalRing.size + Theme.Spacing.m)
                                    .accessibilityHidden(true)
                            }
                            DashGoalRow(progress: item, isVisible: isVisible)
                                .padding(.horizontal, Theme.Spacing.m)
                                .padding(.vertical, Theme.Spacing.s)
                                .motionTransition(.rise)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                }
                .motionAnimation(Motion.smooth, value: goals)
            }
            .motionTransition(.rise)
        }
    }

    /// The Übersicht is on screen and nothing covers it – a pop behind a sheet would be lost.
    private var isVisible: Bool {
        app.selectedTab == .overview && !store.isEditing
            && !(app.isShowingSettings || app.isShowingAchievements || app.tripDraft != nil || app.updates.isPresentingSheet)
    }
}

/// One goal: ring, title, state, numbers, what is left, Prognose. One VoiceOver element.
struct DashGoalRow: View {
    let progress: GoalProgress
    var isVisible = true

    @State private var popTick = 0

    var body: some View {
        let format = DashGoalFormat.formatter
        let projection = GoalText.projection(progress, format: format)
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            DashGoalRing(progress: progress)
                .celebrate(trigger: popTick, haptic: .success)
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        title(format)
                        Spacer(minLength: Theme.Spacing.xxs)
                        DashGoalStateLabel(state: progress.state)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        title(format)
                        DashGoalStateLabel(state: progress.state)
                    }
                }
                Text(GoalText.status(progress, format: format))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(progress.actual)
                Text(GoalText.remaining(progress, format: format))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let projection {
                    Label(projection, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .labelStyle(DashGoalCaptionLabelStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ziel: " + GoalText.title(progress.goal, format: format))
        .accessibilityValue([GoalText.status(progress, format: format), Format.percent(progress.progress),
                             GoalText.stateLabel(progress.state), GoalText.remaining(progress, format: format), projection]
            .compactMap { $0 }.joined(separator: ", "))
        .onChange(of: celebrationKey, initial: true) { _, _ in
            guard isVisible, progress.state == .reached, DashLayoutStore.shared.shouldCelebrate(progress) else { return }
            popTick += 1
        }
    }

    private func title(_ format: GoalFormatter) -> some View {
        Text(GoalText.title(progress.goal, format: format))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var celebrationKey: String { "\(progress.state.rawValue)|\(progress.periodKey)|\(isVisible)" }
}

/// „Auf Kurs“ · „Hinter Plan“ · „Geschafft“ · „Nicht geschafft“ with a symbol – text, never colour alone.
struct DashGoalStateLabel: View {
    let state: GoalState

    var body: some View {
        Label(GoalText.stateLabel(state), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(DashGoalCaptionLabelStyle())
            .lineLimit(1)
    }

    private var symbol: String {
        switch state {
        case .reached: "checkmark.circle.fill"
        case .onTrack: "arrow.up.right"
        case .behind: "arrow.down.right"
        case .missed: "flag.slash"
        }
    }

    private var color: Color {
        switch state {
        case .reached, .onTrack: Theme.positiveText
        case .behind: Theme.summitText
        case .missed: Theme.textSecondary
        }
    }
}

/// Symbol and text close together, aligned on the first line.
private struct DashGoalCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// The ring: route gradient while on the way, pine once reached, dawn while behind. It fills when it first scrolls into view; the
/// percentage in the middle says it in numbers (over 100 % too).
struct DashGoalRing: View {
    static let size: CGFloat = 56
    let progress: GoalProgress

    var body: some View {
        DrawInReader { isDrawn in
            ZStack {
                Circle()
                    .stroke(Theme.textTertiary.opacity(0.22), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: isDrawn ? max(0.015, progress.ringFraction) : 0)
                    .stroke(stroke, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Format.percent(progress.progress))
                    .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
                    .numericValue(progress.progress)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .motionAnimation(Motion.gentle, value: progress.ringFraction)
        .accessibilityHidden(true)
    }

    private var stroke: AnyShapeStyle {
        switch progress.state {
        case .reached: AnyShapeStyle(Theme.positive)
        case .behind, .missed: AnyShapeStyle(Theme.summit)
        case .onTrack: AnyShapeStyle(Theme.routeGradient)
        }
    }
}
