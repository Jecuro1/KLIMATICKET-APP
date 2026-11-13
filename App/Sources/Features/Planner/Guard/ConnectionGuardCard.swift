import SwiftUI
import KlimaCore

// MARK: anschluss – the Anschluss-Wächter card at the top of the follow sheet (docs/CONNECTION_GUARD.md §8–9): the spare minutes
// in big digits, the state chip (glyph and word, never colour alone), the trend, both trains at the transfer station joined by
// the walk, the notes, the status line, „Alternativen ansehen“, „Jetzt prüfen“, „Wecker fürs Umsteigen“ and the menu with
// „Wächter aus“. VoiceOver reads the card as one sentence with custom actions. Draws nothing without a guard for this follow.

/// Colours and glyphs of a state (tokens only).
enum GuardStyle {
    static func color(_ state: GuardState) -> Color {
        switch state {
        case .safe: Theme.positive
        case .tighter, .shaky: Theme.summit
        case .likelyMissed, .missed, .cancelled: Theme.negative
        case .scheduled: Theme.textSecondary
        case .over: Theme.textTertiary
        }
    }

    /// Text on a light fill of `color` (≥ 4.5 : 1).
    static func textColor(_ state: GuardState) -> Color {
        switch state {
        case .safe: Theme.positiveText
        case .tighter, .shaky: Theme.summitText
        case .likelyMissed, .missed, .cancelled: Theme.negativeText
        case .scheduled, .over: Theme.textSecondary
        }
    }

    static func glyph(_ state: GuardState) -> String {
        switch state {
        case .safe: "checkmark.circle.fill"
        case .tighter: "arrow.down.right.circle.fill"
        case .shaky: "exclamationmark.triangle.fill"
        case .likelyMissed: "xmark.circle"
        case .missed: "xmark.circle.fill"
        case .cancelled: "nosign"
        case .scheduled: "calendar"
        case .over: "checkmark.circle"
        }
    }

    static func trendGlyph(_ trend: GuardTrend) -> String {
        switch trend {
        case .falling: "arrow.down.right"
        case .steady: "arrow.right"
        case .rising: "arrow.up.right"
        }
    }

    /// Colour of a time with its delay (as the planner: on time green, late amber, five and more red, no realtime plain).
    static func timeColor(_ f: GuardLegFigure) -> Color {
        if f.isCancelled { return Theme.negativeText }
        guard f.hasRealtime, let delay = f.delayMinutes else { return Theme.textPrimary }
        if delay <= 0 { return Theme.positiveText }
        return delay < 5 ? Theme.summitText : Theme.negativeText
    }
}

/// The state chip: glyph and word on a light fill of the state colour. Wraps at accessibility sizes, never truncates.
struct GuardStateChip: View {
    let state: GuardState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: GuardStyle.glyph(state))
                .font(.footnote.weight(.bold))
                .symbolReplaceTransition()
            Text(GuardText.chip(state))
                .font(.footnote.weight(state == .shaky ? .heavy : .bold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(GuardStyle.textColor(state))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(GuardStyle.color(state).opacity(state == .shaky ? 0.26 : 0.16), in: .capsule)
        .overlay {
            if state == .shaky { Capsule().strokeBorder(GuardStyle.color(state).opacity(0.55), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConnectionGuardCard: View {
    let target: LiveFollowTarget
    let snapshot: LiveFollowSnapshot?
    /// „Wecker fürs Umsteigen“: the follow sheet opens the Aussteige-Wecker on the transfer stop.
    var onAlarm: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismissFollowSheet
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 34
    @State private var showsAlternatives = false
    @State private var pulsing = false
    private var service: ConnectionGuardService { .shared }

    var body: some View {
        if let engine = service.engine, engine.record.followTripID == target.tripID, let a = engine.assessment {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                card(a, engine: engine, now: service.scriptedNow ?? context.date)
            }
            .sheet(isPresented: $showsAlternatives) {
                GuardAlternativesSheet(onPlanner: {
                    showsAlternatives = false
                    dismissFollowSheet()   // the Fahrplan opens under the follow sheet
                })
            }
            .onChange(of: service.wantsAlternatives, initial: true) { _, wants in
                guard wants else { return }
                showsAlternatives = true
                service.alternativesShown()
            }
            .onChange(of: service.shakyPulse) { _, _ in pulse() }
            .task { service.attach(app: app) }
            .motionTransition(.rise)
        }
    }

    private var isLarge: Bool { typeSize.isAccessibilitySize }

    // MARK: Card

    private func card(_ a: GuardAssessment, engine: GuardEngine, now: Date) -> some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                main(a, engine: engine, now: now)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(GuardText.accessibility(a, now: now))
                    .accessibilityActions {
                        if let next = engine.continuation?.target {
                            Button(GuardText.continueSpoken(next.lineName)) { continueFollow() }
                        }
                        Button(GuardText.alternativesButton) { openAlternatives() }
                        if a.state != .over, !engine.record.switchedOff {
                            Button(GuardText.checkButton) { service.checkNow() }
                        }
                        Button(GuardText.alarmButton) { onAlarm() }
                        if a.state != .over {
                            Button(engine.record.switchedOff ? GuardText.switchOn : GuardText.switchOff) {
                                service.setSwitchedOff(!engine.record.switchedOff)
                            }
                        }
                    }
                footer
            }
        }
    }

    private func main(_ a: GuardAssessment, engine: GuardEngine, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header(a)
            headline(a)
                .scaleEffect(pulsing ? 1.04 : 1, anchor: .leading)
            if let trend = GuardText.trend(a, now: now) { trendLine(trend, a) }
            legs(a, engine: engine)
            notes(a)
            status(engine: engine, now: now)
            actions(a, engine: engine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The rail runs the full height of the card's content (a background is offered the content's size); at accessibility
        // sizes the text needs the width, and the chip carries the state.
        .padding(.leading, isLarge ? 0 : 28 + Theme.Spacing.s)
        .background(alignment: .leading) { if !isLarge { rail(a.state) } }
        .motionAnimation(Motion.smooth, value: a.state)
    }

    /// The vertical „Umstieg“ glyph in the state colour.
    private func rail(_ state: GuardState) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(GuardStyle.color(state))
                .rotationEffect(.degrees(90))
                .frame(width: 28, height: 28)
            Capsule()
                .fill(GuardStyle.color(state).opacity(0.35))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 28)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func header(_ a: GuardAssessment) -> some View {
        let title = Text(GuardText.title(a.stationName))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if isLarge {
            VStack(alignment: .leading, spacing: 6) {
                title
                GuardStateChip(state: a.state)
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                title
                Spacer(minLength: 4)
                GuardStateChip(state: a.state)
            }
        }
    }

    @ViewBuilder
    private func headline(_ a: GuardAssessment) -> some View {
        let h = GuardText.headline(a)
        let words = Font.title3.weight(.semibold)
        if let number = h.number {
            let digits = Text(number)
                // The number stays the largest thing on the card, also at accessibility sizes (where the words grow past it).
                .font(.system(size: min(numberSize * (isLarge ? 1.4 : 1), 96), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(a.state.isWarning ? GuardStyle.textColor(a.state) : Theme.textPrimary)
                .contentTransition(.numericText(value: Double(a.bufferMinutes ?? 0)))
                .motionAnimation(Motion.number, value: a.bufferMinutes)
            if isLarge {
                VStack(alignment: .leading, spacing: 0) {
                    if let prefix = h.prefix { Text(prefix).font(words).foregroundStyle(Theme.textPrimary) }
                    digits
                    Text(h.suffix).font(words).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let prefix = h.prefix { Text(prefix).font(words).foregroundStyle(Theme.textPrimary) }
                    digits
                    Text(h.suffix).font(words).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(h.full)
                .font(.title2.weight(.bold))
                .foregroundStyle(a.state == .cancelled ? Theme.negativeText : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trendLine(_ text: String, _ a: GuardAssessment) -> some View {
        let color: Color = a.trend == .falling ? Theme.summitText : (a.trend == .rising ? Theme.positiveText : Theme.textSecondary)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: GuardStyle.trendGlyph(a.trend)).font(.subheadline.weight(.bold))
            Text(text).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }

    // MARK: Both trains and the walk

    private func legs(_ a: GuardAssessment, engine: GuardEngine) -> some View {
        let indices = ConnectionGuard.legIndices(engine.record.journey, feederRide: engine.record.feederRide)
        let feederLine = indices.flatMap { engine.record.journey.legs[$0.feeder].line }
        let connectionLine = indices.flatMap { engine.record.journey.legs[$0.connection].line }
        return VStack(alignment: .leading, spacing: 0) {
            legRow("Ankunft", line: feederLine, figure: a.feeder)
            connector(GuardText.walk(a))
            legRow("Abfahrt", line: connectionLine, figure: a.connection)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func legRow(_ kind: String, line: Line?, figure: GuardLegFigure) -> some View {
        let plate = Group {
            if let line { PlannerLinePlate(line: line, size: .m) } else { Text(figure.lineName).font(.footnote.weight(.bold)) }
        }
        let time = HStack(spacing: 6) {
            if figure.isCancelled, let planned = figure.planned {
                Text(RealtimePresentation.time(planned)).strikethrough(true, color: Theme.negativeText)
                Text("fällt aus")
            } else {
                Text(GuardText.legTime(figure))
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(GuardStyle.timeColor(figure))
        let platform = GuardText.platform(figure).map { text in
            Text(text)
                .font(.subheadline.weight(figure.platformChanged ? .bold : .regular))
                .foregroundStyle(figure.platformChanged ? Theme.summitText : Theme.textSecondary)
        }
        if isLarge {
            VStack(alignment: .leading, spacing: 4) {
                plate
                Text(kind).font(.caption).foregroundStyle(Theme.textSecondary)
                time
                if let platform { platform }
            }
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .center, spacing: 10) {
                plate.frame(minWidth: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind).font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        time
                        if let platform {
                            Text("·").foregroundStyle(Theme.textTertiary)
                            platform
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    /// The dotted „Fußweg“ line between the two trains.
    private func connector(_ text: String) -> some View {
        HStack(spacing: 10) {
            GuardDottedLine()
                .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 6]))
                .frame(width: 3, height: 26)
                .frame(width: isLarge ? 12 : 56)
            Label(text, systemImage: "figure.walk")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Notes, status, actions

    @ViewBuilder
    private func notes(_ a: GuardAssessment) -> some View {
        if let change = GuardText.platformChange(a.connection) {
            noteRow(change, symbol: "signpost.right.and.left.fill", color: Theme.summitText, fill: Theme.summit)
        }
        if let missed = GuardText.missedNote(a) {
            noteRow(missed, symbol: "clock.badge.xmark", color: Theme.negativeText, fill: Theme.negative)
        }
        if a.flaggedUnreachable {
            noteRow(GuardText.unreachableNote, symbol: "info.circle", color: Theme.textSecondary, fill: nil)
        }
        if a.basedOnPlan {
            noteRow(GuardText.noRealtimeNote, symbol: "calendar", color: Theme.textSecondary, fill: nil)
        }
        if a.state == .over {
            noteRow(GuardText.overNote, symbol: "checkmark.circle", color: Theme.textSecondary, fill: nil)
        }
        ForEach(Array(a.laterTransfers.enumerated()), id: \.offset) { _, later in
            noteRow(GuardText.laterTransfer(later), symbol: "arrow.triangle.swap", color: Theme.textSecondary, fill: nil)
        }
    }

    private func noteRow(_ text: String, symbol: String, color: Color, fill: Color?) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote.weight(fill == nil ? .regular : .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, fill == nil ? 0 : 10)
        .padding(.vertical, fill == nil ? 0 : 6)
        .background {
            if let fill { RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous).fill(fill.opacity(0.13)) }
        }
    }

    private func status(engine: GuardEngine, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let status = service.status(now: now) {
                Text(GuardText.status(status, now: now))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = service.manualNote {
                Text(note).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// „Alternativen ansehen“ across the card when it matters; „Jetzt prüfen“, „Wecker fürs Umsteigen“ and the menu below, side by
    /// side (stacked at accessibility sizes).
    private func actions(_ a: GuardAssessment, engine: GuardEngine) -> some View {
        let off = engine.record.switchedOff || a.state == .over
        let showsAlternativesButton = a.state.rank >= GuardState.shaky.rank
        return VStack(alignment: .leading, spacing: 8) {
            if let next = engine.continuation?.target {
                Button { continueFollow() } label: {
                    Label(GuardText.continueButton(next.lineName), systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.prominentTint)
                .accessibilityLabel(GuardText.continueSpoken(next.lineName))
            }
            if showsAlternativesButton {
                Button { openAlternatives() } label: {
                    Label(GuardText.alternativesButton, systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.prominentTint)
            }
            if a.state == .over {
                EmptyView()   // the change is behind you: only „weiter verfolgen“
            } else if isLarge {
                checkButton(off: off)
                alarmButton
                menu(alternatives: showsAlternativesButton, off: engine.record.switchedOff)
            } else {
                HStack(spacing: 8) {
                    checkButton(off: off)
                    alarmButton
                    menu(alternatives: showsAlternativesButton, off: engine.record.switchedOff)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func checkButton(off: Bool) -> some View {
        if !off {
            Button { service.checkNow() } label: { tileLabel(GuardText.checkButton, symbol: "arrow.clockwise") }
                .buttonStyle(.glass)
        }
    }

    private var alarmButton: some View {
        Button { onAlarm() } label: { tileLabel(GuardText.alarmButton, symbol: "bell.badge") }
            .buttonStyle(.glass)
    }

    /// Symbol over the words in the narrow side-by-side buttons (the words wrap instead of being cut); symbol beside them at
    /// accessibility sizes, where the buttons stack.
    @ViewBuilder
    private func tileLabel(_ title: String, symbol: String) -> some View {
        if isLarge {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
    }

    private func menu(alternatives: Bool, off: Bool) -> some View {
        Menu {
            if !alternatives {
                Button { openAlternatives() } label: { Label(GuardText.alternativesButton, systemImage: "arrow.triangle.branch") }
            }
            Button { service.setSwitchedOff(!off) } label: {
                Label(off ? GuardText.switchOn : GuardText.switchOff, systemImage: off ? "eye" : "eye.slash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(minWidth: 24, minHeight: 24)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Mehr zum Wächter")
        .haptic(.selection, trigger: off)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GuardText.footerOpenOnly)
            Text(GuardText.footerNoWaiting)
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
    }

    // MARK: Behaviour

    private func continueFollow() {
        guard let target = service.continueFollow(live: app.live) else { return }
        app.showToast("location.fill", "Live verfolgen", target.lineName, haptic: .start)
    }

    private func openAlternatives() {
        service.searchAlternatives()
        showsAlternatives = true
    }

    /// „Wackelt“ gets one gentle scale pulse on change (none under Reduce Motion or in screenshots).
    private func pulse() {
        guard !reduceMotion, !MotionPolicy.isStatic else { return }
        withMotion(Motion.bouncy) { pulsing = true } completion: {
            withMotion(Motion.smooth) { pulsing = false }
        }
    }
}

/// A vertical line through the middle of its frame (dashed by the stroke style).
struct GuardDottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}
