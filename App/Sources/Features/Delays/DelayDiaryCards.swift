import SwiftUI
import KlimaCore

// MARK: delaydiary – the cards of the Verspätungs-Tagebuch (docs/DELAY_DIARY.md §3)

// MARK: - Hero

/// „Deine Pünktlichkeit · persönlich“: the share of recorded Fahrten that arrived on time (counts in once), a ring with both
/// parts, three counts in words, the mark and the AGB caveat.
struct DelayDiaryHeroCard: View {
    let year: DelayDiaryYear
    var onOptions: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if typeSize.isAccessibilitySize {
                    // The ring only repeats the counts below in shape: at accessibility sizes the words carry it.
                    figure
                } else {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        figure
                        Spacer(minLength: 0)
                        ring.frame(width: 96, height: 96)
                    }
                }
                counts
                caveat
                thresholdRow
            }
        }
        .accessibilityIdentifier("delayDiary.hero")
    }

    // MARK: Figure

    private var figure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(text: "Persönliche Quote")
            if let share = year.onTimeShare {
                CountUpText(value: share * 100, delay: 0.1) { DelayDiaryText.percent($0 / 100) }
                    .font(.system(size: numeralSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("deiner erfassten Fahrten waren pünktlich")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            } else {
                Text("–")
                    .font(.system(size: numeralSize, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(DelayDiaryText.tooFewForShare.prefix(1).uppercased())\(DelayDiaryText.tooFewForShare.dropFirst()) – eine gibt es ab \(DelayDiaryRules.minimumRecordedForShare) erfassten Fahrten.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deine persönliche Pünktlichkeit")
        .accessibilityValue(year.onTimeShare.map { "\(DelayDiaryText.percent($0)) deiner \(year.recordedCount) erfassten Fahrten waren pünktlich" }
                            ?? "Zu wenig erfasste Fahrten für eine Quote")
    }

    private var ring: some View {
        StatsGrowOnView(delay: Motion.Stagger.delay(2)) { grow in
            DelayShareRing(onTime: year.onTimeCount, late: year.lateCount, grow: grow)
        }
        .accessibilityHidden(true)
    }

    // MARK: Counts

    private var counts: some View {
        // One line where the three fit, else two and one, else one under the other.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { recordedPill; latePill; openPill }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) { recordedPill; latePill }
                openPill
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { recordedPill; latePill; openPill }
        }
    }

    private var recordedPill: some View {
        DelayCountPill(value: year.recordedCount, word: "erfasst", symbol: "checklist", tint: Theme.accentText)
    }

    private var latePill: some View {
        DelayCountPill(value: year.lateCount, word: "verspätet", symbol: "clock.badge.exclamationmark", tint: Theme.summitText)
    }

    private var openPill: some View {
        DelayCountPill(value: year.notRecordedCount, word: "ohne Eintrag", symbol: "questionmark.circle", tint: Theme.textSecondary)
    }

    // MARK: Caveat and mark

    private var caveat: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            Text(DelayDiaryText.caveat)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("delayDiary.caveat")
    }

    private var thresholdRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                thresholdText
                Spacer(minLength: Theme.Spacing.xs)
                changeButton
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                thresholdText
                changeButton
            }
        }
    }

    private var thresholdText: some View {
        Text(year.options.scope == .rail ? "\(DelayDiaryText.thresholdLine(year.threshold)) Nur Zug und S-Bahn."
                                         : DelayDiaryText.thresholdLine(year.threshold))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var changeButton: some View {
        Button("Ändern", action: onOptions)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .buttonStyle(.plain)
            .accessibilityLabel("Grenze und Fahrten ändern")
    }
}

/// „42 erfasst“ – a count with its word and symbol (never colour alone).
struct DelayCountPill: View {
    let value: Int
    let word: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .numericValue(Double(value))
            Text(word)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surfaceSecondary.opacity(0.7), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// The share as a ring: the on-time part solid in pine, the late part hatched in dawn (two textures, not two colours only).
struct DelayShareRing: View {
    let onTime: Int
    let late: Int
    var grow: Double = 1

    var body: some View {
        let total = max(onTime + late, 1)
        let onTimeEnd = Double(onTime) / Double(total)
        let reach = min(max(grow, 0), 1)
        ZStack {
            Circle()
                .stroke(Theme.textTertiary.opacity(0.16), lineWidth: 12)
            Circle()
                .trim(from: 0, to: onTimeEnd * reach)
                .stroke(Theme.pine, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if late > 0 {
                Circle()
                    .trim(from: onTimeEnd * reach, to: reach)
                    .stroke(Theme.dawn, style: StrokeStyle(lineWidth: 12, lineCap: .butt, dash: [3, 2]))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: late == 0 ? "checkmark" : "clock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(late == 0 ? Theme.positiveText : Theme.textSecondary)
        }
        .padding(6)
    }
}

// MARK: - Month chart

/// The validity months as bars: on time (solid pine) under late (hatched dawn), the Fahrten without a record as a dashed cap
/// on top; a tap opens the month below. Drawn by hand (at most 12 bars), grows once.
struct DelayMonthChartCard: View {
    let year: DelayDiaryYear
    let selected: Set<Int>
    var onSelect: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let maxTrips = max(year.months.map(\.tripCount).max() ?? 0, 1)
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker(text: "Pro Gültigkeitsmonat")
                    Text("Fahrten mit und ohne Eintrag")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
                StatsGrowOnView(delay: Motion.Stagger.delay(3)) { grow in
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(year.months) { month in
                            bar(month, maxTrips: maxTrips, grow: grow)
                        }
                    }
                    .frame(height: 132)
                }
                legend
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fahrten pro Gültigkeitsmonat")
        .accessibilityIdentifier("delayDiary.chart")
    }

    private func bar(_ month: DelayMonth, maxTrips: Int, grow: Double) -> some View {
        let isSelected = selected.contains(month.index)
        return Button {
            onSelect(month.index)
        } label: {
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let unit = geo.size.height / CGFloat(maxTrips)
                    let reach = CGFloat(min(max(grow, 0), 1))
                    VStack(spacing: 1.5) {
                        Spacer(minLength: 0)
                        if month.notRecordedCount > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .frame(height: max(3, unit * CGFloat(month.notRecordedCount) - 1.5))
                        }
                        if month.lateCount > 0 {
                            DelayHatch(color: Theme.dawn)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .frame(height: max(3, unit * CGFloat(month.lateCount) - 1.5))
                        }
                        if month.onTimeCount > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.pine)
                                .frame(height: max(3, unit * CGFloat(month.onTimeCount)))
                        }
                    }
                    .scaleEffect(x: 1, y: reach, anchor: .bottom)
                    .opacity(month.tripCount == 0 ? 0 : 1)
                }
                .overlay(alignment: .bottom) {
                    if month.tripCount == 0 {
                        Capsule().fill(Theme.textTertiary.opacity(0.3)).frame(height: 2)
                    }
                }
                Text(DelayDiaryFormat.shortMonth(month.start))
                    .font(.caption2.weight(isSelected || month.isCurrent ? .bold : .medium))
                    .foregroundStyle(isSelected || month.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 3)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(DelayDiaryFormat.monthTitle(month))
        .accessibilityValue(DelayMonthCard.spokenSummary(month))
        .accessibilityHint("Öffnet den Monat unten")
    }

    private var legend: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
        return layout {
            legendItem("pünktlich") {
                RoundedRectangle(cornerRadius: 2).fill(Theme.pine)
            }
            legendItem("verspätet") {
                DelayHatch(color: Theme.dawn).clipShape(RoundedRectangle(cornerRadius: 2))
            }
            legendItem("ohne Eintrag") {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }

    private func legendItem<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 12, height: 12)
            Text(title)
        }
    }
}

/// Diagonal hatching on a pale fill – the „verspätet“ texture.
struct DelayHatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.35)))
            var path = Path()
            let step: CGFloat = 5
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }
}

// MARK: - Month

/// A validity month: title, counts in words, its share (or „zu wenig Fahrten für eine Quote“); opens to the late Fahrten and
/// „… nachtragen“.
struct DelayMonthCard: View {
    let month: DelayMonth
    let threshold: Int
    let isExpanded: Bool
    var onToggle: () -> Void
    var onEdit: (DelayDiaryEntry) -> Void
    var onBackfill: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    static func scrollID(_ index: Int) -> String { "delay.month.\(index)" }

    /// „12 Fahrten, 9 erfasst, 2 verspätet, 78 Prozent pünktlich“ – what VoiceOver says for a month.
    static func spokenSummary(_ month: DelayMonth) -> String {
        var text = DelayDiaryText.monthSummary(trips: month.tripCount, recorded: month.recordedCount, late: month.lateCount)
            .replacingOccurrences(of: " · ", with: ", ")
        text += ", " + DelayDiaryText.shareLine(month.onTimeShare).replacingOccurrences(of: "%", with: "Prozent")
        return text
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    details
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.bottom, Theme.Spacing.m)
                        .motionTransition(.rise)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Kicker(text: DelayDiaryFormat.monthKicker(month))
                        if month.isCurrent {
                            Text("läuft")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.accentText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.14), in: .capsule)
                        }
                    }
                    Text(DelayDiaryFormat.monthTitle(month))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(DelayDiaryText.monthSummary(trips: month.tripCount, recorded: month.recordedCount, late: month.lateCount))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if month.onTimeShare == nil, month.tripCount > 0 {
                        Text(DelayDiaryText.tooFewForShare)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if typeSize.isAccessibilitySize, let share = month.onTimeShare {
                        Text(DelayDiaryText.shareLine(share))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                Spacer(minLength: Theme.Spacing.xs)
                if !typeSize.isAccessibilitySize, let share = month.onTimeShare {
                    shareFigure(share)
                }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DelayDiaryFormat.monthTitle(month))
        .accessibilityValue("\(Self.spokenSummary(month)). \(isExpanded ? "Aufgeklappt" : "Zugeklappt")")
        .accessibilityHint(isExpanded ? "Klappt den Monat zu" : "Zeigt die verspäteten Fahrten")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("delay.month.\(month.index)")
    }

    private func shareFigure(_ share: Double) -> some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
            Text(DelayDiaryText.percent(share))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
                .numericValue(share)
            Text("pünktlich")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            if month.lateEntries.isEmpty {
                Label(month.recordedCount > 0 ? "Keine Verspätung ab \(threshold)\u{00A0}Min. in diesem Monat." : "In diesem Monat ist noch nichts eingetragen.",
                      systemImage: month.recordedCount > 0 ? "checkmark.seal" : "tray")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Kicker(text: month.lateCount == 1 ? "1 verspätete Fahrt" : "\(month.lateCount) verspätete Fahrten")
                ForEach(month.lateEntries.reversed()) { entry in
                    DelayEntryRow(entry: entry) { onEdit(entry) }
                }
            }
            if month.notRecordedCount > 0 {
                Button(action: onBackfill) {
                    Label(month.notRecordedCount == 1 ? "1 Fahrt ohne Eintrag nachtragen" : "\(month.notRecordedCount) Fahrten ohne Eintrag nachtragen",
                          systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("delay.month.backfill")
            }
        }
    }
}

/// A late Fahrt: when, route, train, „+12 Min.“ and where the minutes came from; a tap edits it.
struct DelayEntryRow: View {
    let entry: DelayDiaryEntry
    var onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onTap) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.s))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DelayDiaryFormat.when(entry.date))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Text(DelayDiaryFormat.route(entry))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DelayDiaryFormat.train(entry))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.xs) }
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    Text(DelayDiaryText.minutes(entry.minutes ?? 0))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.summitText)
                    if let source = entry.source {
                        DelaySourceBadge(source: source)
                    }
                }
            }
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSecondary.opacity(0.45), in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DelayDiaryFormat.when(entry.date)), \(DelayDiaryFormat.route(entry).replacingOccurrences(of: "→", with: "nach").replacingOccurrences(of: "⇄", with: "und zurück nach")), \(DelayDiaryFormat.train(entry))")
        .accessibilityValue(DelayDiaryText.spokenRow(minutes: entry.minutes, source: entry.source))
        .accessibilityHint("Ändert den Eintrag")
    }
}

/// „von Hand“ / „live“ with its symbol.
struct DelaySourceBadge: View {
    let source: TripDelaySource

    var body: some View {
        Label(DelayDiaryText.sourceName(source), systemImage: source == .manual ? "hand.point.up.left" : "dot.radiowaves.left.and.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.surfaceSecondary, in: .capsule)
    }
}

// MARK: - Method

/// „So führst du das Tagebuch“: how a Fahrt gets into the share and what the AGB measure instead.
struct DelayDiaryMethodCard: View {
    let threshold: Int

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "So führst du das Tagebuch")
                row("hand.tap", "Bei jeder Fahrt", "Im Fahrt-Detail auf „Verspätung“ tippen: Minuten eintragen oder „Pünktlich“.")
                row("questionmark.circle", "Ohne Eintrag zählt nichts", "Fahrten ohne Eintrag sind weder pünktlich noch verspätet – sie bleiben aus der Quote.")
                row("clock.badge.exclamationmark", "Verspätet ab \(threshold)\u{00A0}Min.", "Deine eigene Grenze, einstellbar. Eine Quote gibt es ab \(DelayDiaryRules.minimumRecordedForShare) erfassten Fahrten.")
                row("point.topleft.down.to.point.bottomright.curvepath", "Eine Reise ist eine Fahrt", "Bei Etappen zählt die letzte erfasste Ankunft – wie in der Zeitbilanz.")
                row("building.columns", "Was die AGB messen", "Punkt 24.2: die Pünktlichkeit jeder Bahn pro Gültigkeitsmonat, gemessen und veröffentlicht von der Bahn selbst.")
                row("lock.fill", "Bleibt auf deinem iPhone", "Nichts davon wird hochgeladen. Nur das PDF, das du selbst teilst, verlässt das Gerät.")
            }
        }
        .accessibilityIdentifier("delayDiary.method")
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
