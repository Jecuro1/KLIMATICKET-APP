import SwiftUI
import SwiftData
import KlimaCore

/// "Gipfelbuch" – the achievements screen (DESIGN §5.6). Header "6 von 17" with a segmented collection ring,
/// tier tallies and the next summit; then the sections "Erreicht" and "Als Nächstes" (closest first).
/// Works pushed, as a NavigationStack root (screenshots) or as a sheet; shows a close button only when presented.
///
/// Owns only the data: the body re-runs when the queries, the selected ticket or the catalog change. The entrance,
/// the bounce and the detail selection live in `AchBookScreen`, so they no longer re-run the analytics pipeline
/// (three passes in the first 600 ms, one more per opened or closed medallion).
struct AchievementsView: View {
    /// CI screenshot "achievementDetail": opens the detail sheet of the first (highest) earned medal.
    var opensDetailForScreenshot = false

    @Environment(AppState.self) private var app

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]

    var body: some View {
        let snap = Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
            .map { Analytics.make(ticket: $0, trips: trips, catalog: app.catalog) }
        AchBookScreen(book: snap.map { AchBook($0.achievements) },
                      year: snap.map { AchFormat.ticketYear($0.ticket) } ?? "",
                      opensDetailForScreenshot: opensDetailForScreenshot)
            .equatable()
    }
}

/// The Gipfelbuch itself (header, summary card, sections, detail sheet) for an already evaluated book.
private struct AchBookScreen: View, Equatable {
    let book: AchBook?
    let year: String
    var opensDetailForScreenshot = false

    nonisolated static func == (lhs: AchBookScreen, rhs: AchBookScreen) -> Bool {
        lhs.year == rhs.year && lhs.book?.all == rhs.book?.all && lhs.opensDetailForScreenshot == rhs.opensDetailForScreenshot
    }

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: AchSelection?
    @State private var appeared = LaunchMode.isScreenshot
    @State private var bounceTick = 0
    /// Medals earned since the last visit (`AchUnlockMemory`) and the tick that plays their unlock moment.
    @State private var fresh: Set<String> = []
    @State private var unlockTick = 0
    /// Latched once presented, so the chrome (✕, pale sky, paddings) doesn't flip while a dismiss animates out.
    @State private var wasPresented = false
    @Namespace private var zoom

    private var showsSheetChrome: Bool { isPresented || wasPresented }
    /// Final state from the first frame under Reduce Motion – the `.animation(_:value:)` modifiers below
    /// would otherwise still play the entrance when `appeared` flips in `onAppear` (DESIGN §6).
    private var revealed: Bool { appeared || reduceMotion }

    @ScaledMetric(relativeTo: .body) private var scaledMedal: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var scaledColumn: CGFloat = 100

    private var medalSize: CGFloat { min(scaledMedal, 112) }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: min(scaledColumn, 160)), spacing: Theme.Spacing.xxs, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(year: year)
                if let book {
                    self.book(book, year: year)
                } else {
                    EmptyStateView(symbol: "book.closed",
                                   title: "Dein Gipfelbuch ist noch leer",
                                   message: "Lege dein KlimaTicket an und erfasse Fahrten – jeder erreichte Gipfel wird hier eingetragen.",
                                   actionTitle: "Zum Ticket") {
                        app.isShowingAchievements = false
                        app.selectedTab = .ticket
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .padding(.top, showsSheetChrome ? Theme.Spacing.l : Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .accessibilityIdentifier("perf.scroll.gipfelbuch") // MARK: perf – KlimaBilanzPerfTests
        .revealScope()
        .background { backdrop }
        .overlay(alignment: .topTrailing) { closeButton }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: isPresented, initial: true) { _, presented in
            if presented { wasPresented = true }
        }
        .sheet(item: $selection) { item in
            // Grows out of the medal that was tapped (Reduce Motion: the standard sheet).
            AchDetailSheet(achievement: item.achievement, ticketYear: item.ticketYear)
                .zoomDestination(id: item.sourceID, in: zoom)
        }
        .haptic(.selection, trigger: selection?.id, when: { _, new in new != nil })
        // One haptic for the unlock moment, however many medals were earned since the last visit.
        .haptic(.milestone, trigger: unlockTick, when: { _, new in new > 0 })
        .onAppear(perform: startEntrance)
        .task { await bounceAfterEntrance() }
        .task { await celebrateFreshUnlocks() }
        .task {
            guard opensDetailForScreenshot, LaunchMode.isScreenshot, let first = book?.unlocked.first ?? book?.upcoming.first else { return }
            try? await Task.sleep(for: .milliseconds(700))
            showDetail(first, sourceID: first.id, year: year)
        }
    }

    // MARK: Header

    private func header(year: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: year.isEmpty ? "Erfolge" : "Erfolge · Ticketjahr \(year)")
            Text("Gipfelbuch")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.leading, Theme.Spacing.screen - Theme.Spacing.cardGutter)
        .padding(.trailing, showsSheetChrome ? 56 : 0)
    }

    // MARK: Content

    @ViewBuilder
    private func book(_ book: AchBook, year: String) -> some View {
        AchSummaryCard(book: book, appeared: revealed, zoom: zoom) { achievement, sourceID in
            showDetail(achievement, sourceID: sourceID, year: year)
        }

        section(title: "Erreicht", note: nil, items: book.unlocked, indexOffset: 0, year: year) {
            AchNoteCard(symbol: "flag",
                        title: "Noch kein Gipfel erreicht",
                        message: "Erfasse deine erste Fahrt – „Eingestiegen“ ist dein erster Eintrag im Gipfelbuch.",
                        actionTitle: "Erste Fahrt erfassen") {
                // Closes the Gipfelbuch first when it is a sheet; the editor follows.
                app.presentAddTripFromOutside()
            }
        }

        section(title: "Als Nächstes", note: "Am nächsten zuerst", items: book.upcoming,
                indexOffset: book.unlocked.count, year: year) {
            AchNoteCard(symbol: "checkmark.seal.fill",
                        title: "Alle Gipfel erreicht",
                        message: "Gratulation – dein Gipfelbuch ist für dieses Ticketjahr komplett.")
        }
    }

    private func section<Empty: View>(title: String, note: String?, items: [Achievement], indexOffset: Int, year: String,
                                      @ViewBuilder empty: () -> Empty) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AchSectionHeader(title: title, count: items.count, note: items.isEmpty ? nil : note)
            if items.isEmpty {
                empty()
            } else {
                GlassCard(padding: Theme.Spacing.s) {
                    LazyVGrid(columns: columns, alignment: .center, spacing: Theme.Spacing.xxs) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, achievement in
                            AchBadgeCell(achievement: achievement,
                                         index: indexOffset + index,
                                         appeared: revealed,
                                         bounceTick: bounceTick,
                                         isFresh: fresh.contains(achievement.id),
                                         unlockTick: unlockTick,
                                         medalSize: medalSize,
                                         zoom: zoom) {
                                showDetail(achievement, sourceID: achievement.id, year: year)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Chrome

    private var backdrop: some View {
        ZStack {
            Theme.sheetBackground
            // Sheets stay calm (pale sky); full-screen (screenshots / pushed) gets the full alpine sky.
            AmbientBackground(style: .standard, glow: 0.6)
                .opacity(showsSheetChrome ? 0.55 : 1)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var closeButton: some View {
        if showsSheetChrome {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Schließen")
            .padding(.top, Theme.Spacing.m)
            .padding(.trailing, Theme.Spacing.cardGutter)
        }
    }

    // MARK: Actions

    private func showDetail(_ achievement: Achievement, sourceID: String, year: String) {
        selection = AchSelection(achievement: achievement, sourceID: sourceID, ticketYear: year)
    }

    private func startEntrance() {
        guard !appeared else { return }
        if reduceMotion {
            appeared = true
        } else {
            withMotion(Motion.reveal) { appeared = true }
        }
    }

    /// One celebratory bounce of all unlocked symbols once the medallions have landed.
    private func bounceAfterEntrance() async {
        guard !reduceMotion, !MotionPolicy.isStatic else { return }
        try? await Task.sleep(for: .milliseconds(560))
        bounceTick += 1
    }

    /// Medals earned since the last visit get their moment once the grid has landed: a band of light, a pop with a
    /// ring and a "Neu" tag, one milestone haptic. Reduce Motion: the flash and the tag only.
    private func celebrateFreshUnlocks() async {
        guard let book, !MotionPolicy.isStatic else { return }
        let earned = AchUnlockMemory.takeFresh(unlocked: book.unlocked.map(\.id), ticketYear: year)
        guard !earned.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 700))
        withMotion(Motion.bouncy) {
            fresh = earned
            unlockTick += 1
        }
    }
}

// MARK: - Model

/// Sheet item: which achievement, and which view it zooms out of.
private struct AchSelection: Identifiable {
    let achievement: Achievement
    let sourceID: String
    let ticketYear: String
    var id: String { sourceID }
}

/// The achievements split and ordered for the Gipfelbuch.
private struct AchBook {
    let all: [Achievement]
    /// Highest tier first, then engine order.
    let unlocked: [Achievement]
    /// Closest to completion first, then engine order.
    let upcoming: [Achievement]
    /// Mean progress over all achievements (partial progress counts).
    let meanProgress: Double

    init(_ achievements: [Achievement]) {
        all = achievements
        let indexed = Array(achievements.enumerated())
        unlocked = indexed
            .filter { $0.element.isUnlocked }
            .sorted { lhs, rhs in
                let l = AchTierStyle.rank(lhs.element.tier)
                let r = AchTierStyle.rank(rhs.element.tier)
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map { $0.element }
        upcoming = indexed
            .filter { !$0.element.isUnlocked }
            .sorted { lhs, rhs in
                let l = lhs.element.progress
                let r = rhs.element.progress
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map { $0.element }
        let sum = achievements.reduce(0.0) { $0 + min(max($1.progress, 0), 1) }
        meanProgress = achievements.isEmpty ? 0 : sum / Double(achievements.count)
    }

    var total: Int { all.count }
    /// Share of achievements unlocked (6 of 17 → 0.35) – what the ring centre shows, matching the big count.
    var unlockedShare: Double { all.isEmpty ? 0 : Double(unlocked.count) / Double(all.count) }
    /// Any open achievement already started – only then does the ring carry thin partial lines (and a legend).
    var hasPartialProgress: Bool { upcoming.contains { $0.progress > 0 } }
    /// Ring order: unlocked first, then upcoming.
    var ordered: [Achievement] { unlocked + upcoming }

    func tally(_ tier: Achievement.Tier) -> (done: Int, total: Int) {
        let inTier = all.filter { $0.tier == tier }
        return (inTier.filter(\.isUnlocked).count, inTier.count)
    }
}

// MARK: - Summary card

private struct AchSummaryCard: View {
    let book: AchBook
    let appeared: Bool
    let zoom: Namespace.ID
    let onOpen: (Achievement, String) -> Void

    @ScaledMetric(relativeTo: .body) private var scaledRing: CGFloat = 96
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                topRow
                tierRow
                if let next = book.upcoming.first {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                    spotlight(next)
                }
            }
        }
    }


    private var caption: String {
        if book.unlocked.isEmpty { return "Dein erster Gipfel wartet" }
        if book.upcoming.isEmpty { return "Alle Gipfel erreicht – Gratulation!" }
        return "Gipfel in diesem Ticketjahr"
    }

    private var topRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    countBlock
                    ring
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    countBlock
                    Spacer(minLength: Theme.Spacing.xs)
                    ring
                }
            }
        }
        .motionAnimation(Motion.gentle, value: appeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gipfelbuch")
        .accessibilityValue(accessibilitySummary)
    }

    /// Same wording as on screen: share unlocked first, the average incl. partial progress only as the legend says it.
    private var accessibilitySummary: String {
        var value = "\(book.unlocked.count) von \(book.total) Erfolgen erreicht, \(AchFormat.percent(book.unlockedShare))"
        if showsLegend {
            value += ". Durchschnittlich \(AchFormat.percent(book.meanProgress)) inklusive Teilfortschritt"
        }
        return value
    }

    private var showsLegend: Bool { book.hasPartialProgress && !book.upcoming.isEmpty }

    private var ring: some View {
        AchCollectionRing(items: book.ordered, reveal: appeared, share: book.unlockedShare, size: min(scaledRing, 132))
    }

    private var countBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: "Erreicht")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The screen's hero value: counts up once with the ring, then rolls on every change.
                CountUpText(value: Double(book.unlocked.count), delay: 0.12) { String(Int($0.rounded())) }
                    .font(Theme.Typography.priceNumeral)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("von \(book.total)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(caption)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsLegend {
                legend
                    .padding(.top, 2)
            }
        }
    }

    /// Teaches the ring: thick metal = erreicht (centre), thin glacier line = partial progress of open achievements.
    private var legend: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            AchPartialKey()
            Text("Ø \(AchFormat.percent(book.meanProgress)) inkl. Teilfortschritt")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tierRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { tierItems }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: Theme.Spacing.s) { tierItems }
        }
    }

    private var tierItems: some View {
        ForEach(AchTierStyle.ordered, id: \.self) { tier in
            let tally = book.tally(tier)
            AchTierTally(tier: tier, done: tally.done, total: tally.total)
        }
    }

    private func spotlight(_ next: Achievement) -> some View {
        let sourceID = "spotlight-" + next.id
        let isClose = next.progress >= 0.75
        let kicker = isClose ? "Fast geschafft" : "Nächstes Ziel"
        return Button {
            onOpen(next, sourceID)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                let medal = AchMedallion(achievement: next, size: 40, ringProgress: appeared ? next.progress : 0, showsPercentBadge: false)
                medal
                    .zoomSource(id: sourceID, cornerRadius: medal.outerSize / 2, in: zoom)
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: kicker, color: isClose ? Theme.summitText : Theme.textSecondary)
                    Text(AchText.title(next))
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(next.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text(AchFormat.percent(next.progress))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .numericValue(next.progress)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("\(kicker): \(next.title)")
        .accessibilityValue("\(AchFormat.percent(next.progress)), \(next.progressLabel)")
        .accessibilityHint("Zeigt Details zu diesem Erfolg")
    }
}

/// Segmented ring: one segment per achievement. Unlocked segments are full-width metal in their tier colours – together
/// they equal the share in the centre ("35 % erreicht" next to "6 von 17"). Open achievements keep a quiet track with a
/// thin glacier line for their partial progress, so the partial fills never read as earned.
private struct AchCollectionRing: View {
    let items: [Achievement]
    let reveal: Bool
    let share: Double
    let size: CGFloat

    var body: some View {
        let lineWidth = max(6, size * 0.095)
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                AchRingSegment(index: index, count: items.count, item: item, reveal: reveal, lineWidth: lineWidth)
            }
            VStack(spacing: 0) {
                Text(AchFormat.percent(reveal ? share : 0))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(reveal ? share : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("erreicht")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(lineWidth * 1.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct AchRingSegment: View {
    let index: Int
    let count: Int
    let item: Achievement
    let reveal: Bool
    let lineWidth: CGFloat

    var body: some View {
        let n = Double(max(count, 1))
        let gap = count > 1 ? 0.014 : 0.0
        let start = Double(index) / n + gap / 2
        let end = max(start, Double(index + 1) / n - gap / 2)
        let fill = reveal ? min(max(item.progress, 0), 1) : 0
        ZStack {
            Circle()
                .trim(from: start, to: end)
                .stroke(Theme.textTertiary.opacity(0.2), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            if item.isUnlocked {
                // Metal sweep along the segment itself (a ring-wide gradient left the pale end on white segments).
                Circle()
                    .trim(from: start, to: start + (end - start) * fill)
                    .stroke(AngularGradient(colors: AchTierStyle.strokeColors(item.tier), center: .center,
                                            startAngle: .degrees(360 * start), endAngle: .degrees(360 * end)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            } else if fill > 0 {
                Circle()
                    .trim(from: start, to: start + (end - start) * fill)
                    .stroke(Theme.glacier, style: StrokeStyle(lineWidth: AchPartialKey.thinWidth(lineWidth), lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
        // Segments fill one after another around the ring (drawn once, Motion.gentle).
        .motionAnimation(Motion.gentle.delay(0.12 + Motion.Duration.standard * Double(index) / n), value: reveal)
    }
}

/// Legend key for the ring's partial lines: a short track with the thin glacier line inside.
private struct AchPartialKey: View {
    static func thinWidth(_ lineWidth: CGFloat) -> CGFloat { max(2, lineWidth * 0.36) }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.textTertiary.opacity(0.2))
                .frame(width: 18, height: 7)
            Capsule().fill(Theme.glacier)
                .frame(width: 11, height: 2.5)
                .padding(.leading, 2)
        }
        .accessibilityHidden(true)
    }
}

private struct AchTierTally: View {
    let tier: Achievement.Tier
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AchTierCoin(tier: tier, size: 20, muted: done == 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(done)/\(total)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(AchTierStyle.name(tier))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AchTierStyle.name(tier))
        .accessibilityValue("\(done) von \(total) erreicht")
    }
}

// MARK: - Sections

private struct AchSectionHeader: View {
    let title: String
    let count: Int
    let note: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(String(count))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 2)
                .background(Theme.surfaceSecondary, in: .capsule)
                .accessibilityLabel("\(count) Erfolge")
            Spacer(minLength: Theme.Spacing.xs)
            if let note, !dynamicTypeSize.isAccessibilitySize {
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, Theme.Spacing.screen - Theme.Spacing.cardGutter)
    }
}

private struct AchBadgeCell: View {
    let achievement: Achievement
    let index: Int
    let appeared: Bool
    let bounceTick: Int
    /// Earned since the last visit: celebrated when `unlockTick` fires, tagged "Neu" for this visit.
    let isFresh: Bool
    let unlockTick: Int
    let medalSize: CGFloat
    let zoom: Namespace.ID
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let celebration = isFresh ? unlockTick : 0
        let medal = AchMedallion(achievement: achievement,
                                 size: medalSize,
                                 ringProgress: appeared ? achievement.progress : 0,
                                 bounceTick: bounceTick,
                                 shineTick: celebration)
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.xs) {
                medal
                    .celebrate(trigger: celebration, haptic: nil)
                    .celebrationRing(trigger: celebration, color: AchTierStyle.strokeColors(achievement.tier).last ?? Theme.gold)
                    .overlay(alignment: .topTrailing) {
                        if isFresh {
                            AchNewTag()
                                .offset(x: 6, y: -2)
                                .motionTransition(.pop)
                        }
                    }
                    .zoomSource(id: achievement.id, cornerRadius: medal.outerSize / 2, in: zoom)
                // Caption hugs the name (no reserved second line → no hole under one-line names); cells are
                // top-aligned, so leftover row height falls below the caption.
                VStack(spacing: 3) {
                    Text(AchText.title(achievement))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(titleLines(isLarge: isLarge))
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    subtitle
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        // Medals pop in once, staggered in reading order; rows that arrive later (scrolled in) are simply there.
        .reveal(.pop, order: index + 2)
        .accessibilityLabel(achievement.title)
        .accessibilityValue(voiceOverValue)
        .accessibilityHint("Zeigt Details zu diesem Erfolg")
    }

    /// Single words ("Klimaschützer:in") stay on one line and shrink a touch rather than split mid-word;
    /// phrases wrap at spaces/hyphens. Accessibility sizes wrap freely (soft hyphens keep the joints clean).
    private func titleLines(isLarge: Bool) -> Int {
        if isLarge { return 5 }
        return AchText.isSingleWord(achievement) ? 1 : 2
    }

    @ViewBuilder
    private var subtitle: some View {
        if achievement.isUnlocked {
            HStack(spacing: Theme.Spacing.xxs) {
                AchTierCoin(tier: achievement.tier, size: 10)
                Text(AchTierStyle.name(achievement.tier))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text(achievement.progressLabel)
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var voiceOverValue: String {
        let tier = AchTierStyle.name(achievement.tier)
        if achievement.isUnlocked { return isFresh ? "Neu erreicht, Stufe \(tier)" : "Erreicht, Stufe \(tier)" }
        return "\(AchFormat.percent(achievement.progress)) geschafft, \(achievement.progressLabel), Stufe \(tier)"
    }
}

private struct AchNoteCard: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                note
                if let actionTitle, let action {
                    Button(actionTitle, systemImage: "plus", action: action)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var note: some View {
        Group {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Neu" on a medal earned since the last visit (this visit only).
private struct AchNewTag: View {
    var body: some View {
        Text("Neu")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.summit, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.onAccent.opacity(0.8), lineWidth: 1))
            .shadow(color: Theme.summit.opacity(0.35), radius: 4, y: 1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
