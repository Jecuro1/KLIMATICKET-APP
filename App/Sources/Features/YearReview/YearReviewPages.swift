import SwiftUI
import KlimaCore

// The pages of the year story (docs/YEAR_REVIEW.md). Every figure comes from `YearReview` (KlimaCore) and is formatted
// through `YearReviewText` / `Format.*` / `SummitFigures`; every page is one accessibility element with a spoken summary.

/// What a page needs besides its own payload.
@MainActor
struct YearReviewPageContext {
    let review: YearReview
    let store: YearReviewStore
    let number: Int
    let total: Int

    /// Where a count-up starts: 0 on the first visit, the value itself when the page was seen before.
    func start(_ kind: YearReviewPageKind, _ value: Double) -> Double { store.hasPlayed(kind) ? value : 0 }
}

/// Dispatches a page to its view and gives it the one-element accessibility summary.
struct YearReviewPageView: View {
    let page: YearReview.Page
    let ctx: YearReviewPageContext

    var body: some View {
        content
            .revealScope()
            .onAppear { ctx.store.markPlayed(page.kind) }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .intro(let intro):
            YearReviewIntroPage(intro: intro, ctx: ctx).storySummary(page, ctx)
        case .savings(let savings):
            YearReviewSavingsPage(savings: savings, ctx: ctx).storySummary(page, ctx)
        case .distance(let distance):
            YearReviewDistancePage(distance: distance, ctx: ctx).storySummary(page, ctx)
        case .favoriteRoute(let favorite):
            YearReviewFavoritePage(favorite: favorite, ctx: ctx).storySummary(page, ctx)
        case .rhythm(let rhythm):
            YearReviewRhythmPage(rhythm: rhythm, ctx: ctx).storySummary(page, ctx)
        case .onTheRoad(let road):
            YearReviewRoadPage(road: road, ctx: ctx).storySummary(page, ctx)
        case .purpose(let purpose):
            YearReviewPurposePage(purpose: purpose, ctx: ctx).storySummary(page, ctx)
        case .climate(let climate):
            YearReviewClimatePage(climate: climate, ctx: ctx).storySummary(page, ctx)
        case .finale(let finale):
            YearReviewFinalePage(finale: finale, ctx: ctx)
        }
    }
}

private extension View {
    /// "Seite 3 von 8: Du bist 4.812 Kilometer gefahren" – the whole page as one element.
    func storySummary(_ page: YearReview.Page, _ ctx: YearReviewPageContext) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(YearReviewText.spoken(page, review: ctx.review, number: ctx.number, total: ctx.total))
    }
}

// MARK: - 1 Intro

struct YearReviewIntroPage: View {
    let intro: YearReview.Intro
    let ctx: YearReviewPageContext

    @ScaledMetric(relativeTo: .largeTitle) private var yearSize: CGFloat = 104

    var body: some View {
        ZStack(alignment: .bottom) {
            StoryRidge()
            StoryPageScaffold {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    StoryKicker(kind: .intro, symbol: "sparkles")
                        .reveal(.fade)
                    Text(ctx.review.period.kind == .ticket ? "Dein Ticket-Jahr" : "Dein Kalenderjahr")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Theme.Spacing.l)
                        .reveal(order: 1)
                    Text(ctx.review.period.yearLabel())
                        .font(.system(size: yearSize, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(Theme.routeGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .reveal(.focus, order: 2)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        CountUpText(value: Double(intro.tripCount), from: ctx.start(.intro, Double(intro.tripCount)), delay: 0.3) { Format.number($0) }
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(intro.tripCount == 1 ? "Fahrt" : "Fahrten")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.top, Theme.Spacing.l)
                    .reveal(order: 4)
                    StoryCaption(caption)
                        .reveal(order: 5)
                }
                .padding(.bottom, Theme.Spacing.xxl * 3)
            }
        }
    }

    private var caption: String {
        var text = "an \(Format.days(intro.travelDays)) unterwegs"
        if let name = intro.ticketName { text += " mit deinem \(name)" }
        return text
    }
}

// MARK: - 2 Ersparnis

struct YearReviewSavingsPage: View {
    let savings: YearReview.Savings
    let ctx: YearReviewPageContext

    @State private var sealPop = false
    @State private var showsConfetti = false

    var body: some View {
        let verdict = YearReviewText.verdict(savings)
        ZStack {
            StoryPageScaffold {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    StoryKicker(kind: .savings, symbol: "eurosign.circle.fill")
                        .reveal(.fade)
                    Text(headline(verdict))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Theme.Spacing.m)
                        .reveal(order: 1)
                    numeral(verdict)
                        .reveal(.focus, order: 2)
                    if savings.breakEvenDate != nil { breakEvenPill.reveal(.pop, order: 3) }
                    if savings.hasTicketCost || savings.totalValue > 0 { comparison.reveal(order: 4) }
                    if savings.hasInducedTrips { induced.reveal(order: 5) }
                    if !savings.hasTicketCost {
                        StoryCaption("Für diesen Zeitraum ist kein Ticketpreis hinterlegt – darum zeigt die Story den Fahrtwert, aber keinen Gewinn.")
                            .reveal(order: 5)
                    }
                }
            }
            if showsConfetti {
                ConfettiView(colors: Theme.celebrationColors)
                    .ignoresSafeArea()
            }
        }
        .onAppear(perform: celebrateOnce)
    }

    private func headline(_ verdict: YearReviewText.Verdict) -> String {
        switch verdict {
        case .profit(let amount): amount >= 1 ? "Dein Ticket hat sich gelohnt" : "Dein Ticket hat sich bezahlt"
        case .remaining: "Dein Stand"
        case .valueOnly: "Der Wert deiner Fahrten"
        }
    }

    @ViewBuilder
    private func numeral(_ verdict: YearReviewText.Verdict) -> some View {
        switch verdict {
        case .profit(let amount):
            VStack(alignment: .leading, spacing: 0) {
                StoryNumeral(value: amount, from: ctx.start(.savings, amount), style: AnyShapeStyle(Theme.positiveText)) { "+ " + SummitFigures.euro($0) }
                Text(amount >= 1 ? "Gewinn" : "Punktlandung")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        case .remaining(let amount):
            VStack(alignment: .leading, spacing: 0) {
                StoryNumeral(value: amount, from: ctx.start(.savings, amount), style: AnyShapeStyle(Theme.summitText)) { SummitFigures.euro($0) }
                Text(savings.costIsPartial ? "noch bis zu den anteiligen Ticketkosten" : "noch bis zum Break-even")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .valueOnly(let value):
            VStack(alignment: .leading, spacing: 0) {
                StoryNumeral(value: value, from: ctx.start(.savings, value)) { SummitFigures.euro($0) }
                Text("Fahrtwert")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var breakEvenPill: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.onAccent, Theme.positive.gradient)
                .celebrate(trigger: sealPop, haptic: .milestone)
                .celebrationRing(trigger: sealPop, color: Theme.positive)
                .celebrationBurst(trigger: sealPop)
                .accessibilityHidden(true)
            if let date = savings.breakEvenDate {
                Text("\(savings.breakEvenTicketName ?? "Dein Ticket") rentiert seit \(Format.dayMonth(date))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    /// Value of the trips against the ticket cost – two bars with text labels.
    private var comparison: some View {
        let scale = max(savings.hasTicketCost ? savings.realValue : savings.totalValue, savings.ticketCost, 1)
        let value = savings.hasTicketCost ? savings.realValue : savings.totalValue
        return GlassCard(padding: Theme.Spacing.m) {
            StoryDraw { drawn in
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    barRow(title: "Wert deiner Fahrten", amount: YearReviewText.valueText(savings), fraction: value / scale, tint: AnyShapeStyle(Theme.progressGradient), drawn: drawn)
                    if savings.hasTicketCost {
                        barRow(title: savings.costIsPartial ? "Ticket (anteilig)" : "Ticket", amount: YearReviewText.costText(savings),
                               fraction: savings.ticketCost / scale, tint: AnyShapeStyle(Theme.summit), drawn: drawn)
                    }
                }
            }
        }
    }

    private func barRow(title: String, amount: String, fraction: Double, tint: AnyShapeStyle, drawn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(amount)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            StoryBar(fraction: fraction, tint: tint, height: 10, isDrawn: drawn)
        }
    }

    private var induced: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.dusk)
                .accessibilityHidden(true)
            Text(YearReviewText.inducedLine(savings))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.s)
        .background(Theme.dusk.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
    }

    /// The existing celebration (pop, ring, burst, confetti), once per story.
    private func celebrateOnce() {
        guard savings.breakEvenDate != nil, !ctx.store.hasCelebrated else { return }
        ctx.store.markCelebrated()
        guard !MotionPolicy.isStatic else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            sealPop = true
            showsConfetti = true
        }
    }
}

// MARK: - 3 Strecke

struct YearReviewDistancePage: View {
    let distance: YearReview.Distance
    let ctx: YearReviewPageContext

    var body: some View {
        StoryPageScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .distance, symbol: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .reveal(.fade)
                Text("Du bist")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.m)
                    .reveal(order: 1)
                // Same rounding as Statistik (`Format.km`): one decimal below 10 km, whole kilometres above.
                StoryNumeral(value: distance.km, from: ctx.start(.distance, distance.km), unit: "km") { Format.number($0, decimals: distance.km < 10 ? 1 : 0) }
                    .reveal(.focus, order: 2)
                Text("gefahren")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .reveal(order: 3)
                if let reference = distance.reference {
                    referenceCard(reference).reveal(order: 4)
                }
            }
        }
    }

    private func referenceCard(_ reference: ReferenceComparison) -> some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryDraw(delay: 0.35) { drawn in
                    VStack(spacing: 4) {
                        StoryRouteArc(isDrawn: drawn)
                            .frame(height: 70)
                        HStack {
                            Text(reference.fromLabel)
                            Spacer()
                            Text(reference.toLabel)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                Text(YearReviewText.referenceLine(reference).capitalizedFirst)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(YearReviewText.referenceNote(reference))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// An arc from one dot to another that draws itself – the route of the comparison.
private struct StoryRouteArc: View {
    let isDrawn: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let start = CGPoint(x: 8, y: size.height - 8)
            let end = CGPoint(x: size.width - 8, y: size.height - 8)
            ZStack {
                ArcShape()
                    .stroke(Theme.textTertiary.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                ArcShape()
                    .trim(from: 0, to: isDrawn ? 1 : 0)
                    .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle()
                    .strokeBorder(Theme.glacier, lineWidth: 3)
                    .background(Circle().fill(Theme.background))
                    .frame(width: 14, height: 14)
                    .position(start)
                Circle()
                    .fill(Theme.summit)
                    .frame(width: 14, height: 14)
                    .position(end)
                    .opacity(isDrawn ? 1 : 0.3)
            }
        }
        .accessibilityHidden(true)
    }

    private struct ArcShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 8, y: rect.height - 8))
            path.addQuadCurve(to: CGPoint(x: rect.width - 8, y: rect.height - 8), control: CGPoint(x: rect.width / 2, y: -rect.height * 0.5))
            return path
        }
    }
}

// MARK: - 4 Lieblingsroute

struct YearReviewFavoritePage: View {
    let favorite: YearReview.FavoriteRoute
    let ctx: YearReviewPageContext

    var body: some View {
        let top = favorite.top
        StoryPageScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .favoriteRoute, symbol: "star.fill")
                    .reveal(.fade)
                Text("Deine Lieblingsroute")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.m)
                    .reveal(order: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(top.fromName)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.dusk)
                        .accessibilityHidden(true)
                    Text(top.toName)
                }
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(.focus, order: 2)
                StoryNumeral(value: Double(top.trips), from: ctx.start(.favoriteRoute, Double(top.trips)), delay: 0.3,
                             unit: top.trips == 1 ? "Fahrt" : "Fahrten") { Format.number($0) }
                    .reveal(order: 3)
                StoryCaption(caption(top))
                    .reveal(order: 4)
                if !favorite.runnersUp.isEmpty { leaderboard.reveal(order: 5) }
            }
        }
    }

    private func caption(_ top: RouteStat) -> String {
        var text = "zusammen \(SummitFigures.euro(top.value)) Fahrtwert · \(Format.km(top.distanceKm))"
        if top.legs > top.trips { text += ". Hin und zurück zählt als eine Fahrt." }
        return text
    }

    private var leaderboard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            StoryDraw(delay: 0.4) { drawn in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(Array(favorite.runnersUp.enumerated()), id: \.element.id) { offset, route in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(offset + 2).")
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                                Text(YearReviewText.routeTitle(route))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Spacer(minLength: Theme.Spacing.xs)
                                Text("\(route.trips)×")
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            StoryBar(fraction: Double(route.trips) / Double(max(favorite.top.trips, 1)), tint: AnyShapeStyle(Theme.dusk.opacity(0.8)),
                                     height: 6, isDrawn: drawn)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(offset + 2). \(YearReviewText.routeTitle(route)), \(StatsNames.trips(route.trips))")
                    }
                }
            }
        }
    }
}

// MARK: - 5 Rhythmus

struct YearReviewRhythmPage: View {
    let rhythm: YearReview.Rhythm
    let ctx: YearReviewPageContext

    var body: some View {
        StoryPageScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .rhythm, symbol: "waveform.path.ecg")
                    .reveal(.fade)
                if let best = rhythm.bestMonth {
                    Text("Dein stärkster Monat")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Theme.Spacing.m)
                        .reveal(order: 1)
                    Text(StatsNames.wideMonth(best.month))
                        .font(.system(size: 60, weight: .light, design: .rounded))
                        .foregroundStyle(Theme.routeGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .reveal(.focus, order: 2)
                    StoryCaption("\(SummitFigures.euro(best.value)) Fahrtwert in \(StatsNames.trips(best.trips))")
                        .reveal(order: 3)
                }
                chart.reveal(order: 4)
                tiles.reveal(order: 5)
            }
        }
    }

    private var chart: some View {
        let maxValue = max(rhythm.months.map(\.value).max() ?? 0, 1)
        let best = rhythm.bestMonth?.month
        return GlassCard(padding: Theme.Spacing.m) {
            StoryDraw(delay: 0.3) { drawn in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(rhythm.months) { month in
                        let isBest = month.month == best
                        VStack(spacing: 4) {
                            // The best month carries its value as text: the chart never relies on colour or height alone.
                            Text(isBest ? SummitFigures.euro(month.value) : " ")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.summitText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Capsule()
                                .fill(isBest ? AnyShapeStyle(LinearGradient(colors: [Theme.dusk, Theme.dawn], startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(Theme.glacier.opacity(month.value > 0 ? 0.55 : 0.16)))
                                .frame(height: max(4, 84 * CGFloat(month.value / maxValue)))
                                .scaleEffect(y: drawn ? 1 : 0.02, anchor: .bottom)
                            Text(StatsNames.narrowMonth(month.month))
                                .font(.caption2.weight(isBest ? .bold : .medium))
                                .foregroundStyle(isBest ? Theme.textPrimary : Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 118, alignment: .bottom)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fahrtwert pro Monat")
            .accessibilityValue(rhythm.months.map { "\(StatsNames.wideMonth($0.month)) \(SummitFigures.euro($0.value))" }.joined(separator: ", "))
        }
    }

    private var tiles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) { weekdayTile; streakTile }
            VStack(spacing: Theme.Spacing.s) { weekdayTile; streakTile }
        }
    }

    @ViewBuilder
    private var weekdayTile: some View {
        if let day = rhythm.busiestWeekday {
            tile(symbol: "calendar", title: "Lieblingstag", value: StatsNames.wideWeekday(day.weekday), detail: StatsNames.trips(day.trips))
        }
    }

    private var streakTile: some View {
        tile(symbol: "flame.fill", title: "Längste Serie", value: YearReviewText.streakText(rhythm.longestStreakDays),
             detail: rhythm.longestStreakDays == 1 ? "kein Tag in Folge" : "in Folge unterwegs")
    }

    private func tile(symbol: String, title: String, value: String, detail: String) -> some View {
        GlassCard(padding: Theme.Spacing.s + 2, cornerRadius: Theme.Radius.tile) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - 6 Unterwegs

struct YearReviewRoadPage: View {
    let road: YearReview.OnTheRoad
    let ctx: YearReviewPageContext

    var body: some View {
        StoryPageScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .onTheRoad, symbol: "map.fill")
                    .reveal(.fade)
                Text("Du warst in")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.m)
                    .reveal(order: 1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountUpText(value: Double(road.stateCount), from: ctx.start(.onTheRoad, Double(road.stateCount)), delay: 0.2) { Format.number($0) }
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("von \(YearReview.OnTheRoad.totalStates) Bundesländern")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .reveal(.focus, order: 2)
                stateGrid.reveal(order: 3)
                records.reveal(order: 4)
            }
        }
    }

    private var stateGrid: some View {
        let all = FederalState.allCases.filter { $0 != .foreign }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
            ForEach(all) { state in
                let visited = road.states.contains(state)
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: visited ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(visited ? Theme.positive : Theme.textTertiary)
                        Text(state.rawValue)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(visited ? Theme.textPrimary : Theme.textSecondary)
                    }
                    Text(state.displayName)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(visited ? Theme.positive.opacity(0.14) : Theme.textTertiary.opacity(0.08), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(visited ? Theme.positive.opacity(0.4) : Theme.textTertiary.opacity(0.25),
                                      style: StrokeStyle(lineWidth: 1, dash: visited ? [] : [3, 3]))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(state.displayName), \(visited ? "besucht" : "nicht besucht")")
            }
        }
    }

    @ViewBuilder
    private var records: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let trip = road.longestTrip {
                recordRow(symbol: "ruler", title: "Längste Fahrt", route: YearReviewText.tripTitle(trip), value: Format.km(trip.totalDistanceKm))
            }
            if let trip = road.mostValuableTrip, trip.id != road.longestTrip?.id {
                recordRow(symbol: "eurosign.circle", title: "Wertvollste Fahrt", route: YearReviewText.tripTitle(trip), value: SummitFigures.euro(trip.totalValue))
            }
        }
    }

    private func recordRow(symbol: String, title: String, route: String, value: String) -> some View {
        GlassCard(padding: Theme.Spacing.s + 2, cornerRadius: Theme.Radius.tile) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(route)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Text(value)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

// MARK: - Wofür (optional)

struct YearReviewPurposePage: View {
    let purpose: YearReview.Purpose
    let ctx: YearReviewPageContext

    var body: some View {
        let buckets = Array(purpose.buckets.prefix(5))
        let top = buckets.first
        StoryPageScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .purpose, symbol: "tag.fill")
                    .reveal(.fade)
                Text("Wofür du am meisten gefahren bist")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.m)
                    .reveal(order: 1)
                if let category = top?.category {
                    Label(category.displayName, systemImage: category.symbolName)
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .foregroundStyle(Theme.routeGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .reveal(.focus, order: 2)
                }
                GlassCard(padding: Theme.Spacing.m) {
                    StoryDraw(delay: 0.3) { drawn in
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            ForEach(buckets) { bucket in
                                row(bucket, maxTrips: buckets.first?.trips ?? 1, drawn: drawn)
                            }
                        }
                    }
                }
                .reveal(order: 3)
                StoryCaption("\(StatsNames.trips(purpose.categorisedTrips)) mit Zweck – Fahrten ohne Zweck sind hier nicht gezählt.")
                    .reveal(order: 4)
            }
        }
    }

    private func row(_ bucket: CategoryBucket, maxTrips: Int, drawn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(bucket.category?.displayName ?? "", systemImage: bucket.category?.symbolName ?? "tag")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                Text("\(StatsNames.trips(bucket.trips)) · \(Format.percent(bucket.tripShare))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            StoryBar(fraction: Double(bucket.trips) / Double(max(maxTrips, 1)), tint: AnyShapeStyle(Theme.dusk.opacity(0.85)), height: 8, isDrawn: drawn)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bucket.category?.displayName ?? ""): \(StatsNames.trips(bucket.trips))")
    }
}

// MARK: - 7 Klima

struct YearReviewClimatePage: View {
    let climate: YearReview.Climate
    let ctx: YearReviewPageContext

    var body: some View {
        let parts = StatsCalc.co2Parts(climate.co2SavedKg)
        StoryPageScaffold {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StoryKicker(kind: .climate, symbol: "leaf.fill")
                    .reveal(.fade)
                Text("Du hast gespart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.Spacing.m)
                    .reveal(order: 1)
                StoryNumeral(value: climate.co2SavedKg >= 1000 ? climate.co2SavedKg / 1000 : climate.co2SavedKg,
                             from: ctx.start(.climate, climate.co2SavedKg >= 1000 ? climate.co2SavedKg / 1000 : climate.co2SavedKg),
                             unit: "\(parts.unit) CO₂", style: AnyShapeStyle(Theme.positiveText)) { value in
                    Format.number(value, decimals: climate.co2SavedKg >= 1000 ? 1 : 0)
                }
                .reveal(.focus, order: 2)
                HStack(spacing: Theme.Spacing.xs) {
                    StoryPill(text: "Schätzung", symbol: "info.circle.fill", tint: Theme.pine)
                    Text("gegenüber dem Auto")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .reveal(.pop, order: 3)
                comparison.reveal(order: 4)
                equivalents.reveal(order: 5)
                Text("Schätzung gegenüber derselben Strecke allein im Pkw: Straßenkilometer und Emissionsfaktoren des Umweltbundesamts, wie in „Öffis vs. Auto“.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .reveal(order: 6)
            }
        }
    }

    private var comparison: some View {
        let maxKg = max(climate.co2CarKg, climate.co2TransitKg, 0.001)
        return GlassCard(padding: Theme.Spacing.m) {
            StoryDraw(delay: 0.35) { drawn in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    barRow(symbol: "car.fill", title: "Mit dem Auto", kg: climate.co2CarKg, fraction: climate.co2CarKg / maxKg,
                           tint: AnyShapeStyle(Theme.dawn), drawn: drawn)
                    barRow(symbol: "tram.fill", title: "Mit den Öffis", kg: climate.co2TransitKg, fraction: climate.co2TransitKg / maxKg,
                           tint: AnyShapeStyle(Theme.positive), drawn: drawn)
                }
            }
        }
    }

    private func barRow(symbol: String, title: String, kg: Double, fraction: Double, tint: AnyShapeStyle, drawn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(YearReviewText.co2Text(kg))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            StoryBar(fraction: fraction, tint: tint, height: 10, isDrawn: drawn)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(YearReviewText.co2Text(kg))
    }

    private var equivalents: some View {
        VStack(alignment: .leading, spacing: 6) {
            equivalent(symbol: "airplane", text: "ca. \(StatsCalc.friendlyCount(climate.co2SavedKg / StatsCalc.kgPerFlight)) Flüge Wien–Paris")
            equivalent(symbol: "tree.fill", text: "ca. \(StatsCalc.friendlyCount(climate.co2SavedKg / StatsCalc.kgPerTreeYear)) Bäume ein Jahr lang")
        }
    }

    private func equivalent(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .labelStyle(.titleAndIcon)
    }
}
