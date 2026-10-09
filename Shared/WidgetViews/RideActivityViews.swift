import SwiftUI
import WidgetKit
import AppIntents
import KlimaCore

// "Unterwegs" Live Activity designs (Lock Screen + Dynamic Island). Shared by the widget extension, which renders the real
// activity (Widgets/Sources/RideLiveActivity.swift), and the app, which shows the same views in its preview screen.
// Fixed point sizes like the widgets: the Lock Screen presentation is capped at 160 pt height.

// MARK: - Formatting

enum RideFormat {
    /// "+ € 49,80"
    static func plusEuro(_ value: Double) -> String { "+ " + WidFormat.euroPrecise(value) }

    /// "+€ 49,80" – the narrow compact island; whole euros from € 100 ("+€ 124").
    static func compactPlusEuro(_ value: Double) -> String {
        "+" + (value >= 100 ? WidFormat.euroWhole(value) : WidFormat.euroPrecise(value))
    }

    /// "77 %" or, when needed to show a gain, "77,4 %". Never "100 %" before the summit is reached.
    static func percent(_ fraction: Double, decimals: Bool = false) -> String {
        guard decimals else { return "\(RidePayoff.percent(fraction)) %" }
        var value = (max(0, fraction.isFinite ? fraction : 0) * 1000).rounded() / 10
        if fraction < 1, value >= 100 { value = 99.9 }
        return "\(WidFormat.number(value, decimals: 1)) %"
    }

    /// "07:42"
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(WidFormat.locale))
    }
}

/// Wording shared by all presentations.
enum RideCopy {
    /// Line under the route: status, phase or "Unterwegs seit 07:42".
    static func caption(_ attributes: RideActivityAttributes, _ state: RideActivityAttributes.ContentState, isStale: Bool) -> String {
        switch state.phase {
        case .saved:
            return "Gespeichert um \(RideFormat.time(state.endedAt ?? Date()))"
        case .ended:
            return "Beendet um \(RideFormat.time(state.endedAt ?? Date()))"
        case .arrived:
            return "Angekommen in \(RideNames.short(attributes.toName))"
        case .riding:
            if isStale { return "Noch nicht gespeichert" }
            if let status = state.status, !status.text.isEmpty { return status.text }
            var parts: [String] = []
            if let line = attributes.lineLabel, !line.isEmpty { parts.append(line) }
            if let arrival = state.expectedArrival {
                parts.append("an \(RideFormat.time(arrival))")
            } else {
                parts.append("Unterwegs seit \(RideFormat.time(attributes.startedAt))")
            }
            return parts.joined(separator: " · ")
        }
    }

    /// VoiceOver summary of the whole activity.
    static func spokenSummary(_ attributes: RideActivityAttributes, _ state: RideActivityAttributes.ContentState, isStale: Bool) -> String {
        var parts = ["\(attributes.mode.displayName) von \(RideNames.short(attributes.fromName)) nach \(RideNames.short(attributes.toName))"]
        parts.append(caption(attributes, state, isStale: isStale))
        parts.append("Wert dieser Fahrt \(WidFormat.euroPrecise(state.valueEUR))")
        if let payoff = state.payoff {
            if payoff.isPaidOffBefore {
                parts.append("dein Ticket hat sich schon rentiert")
            } else if payoff.reachesSummit {
                parts.append("damit hat sich dein Ticket rentiert")
            } else {
                parts.append("danach \(RideFormat.percent(payoff.after, decimals: payoff.needsDecimals)) amortisiert")
            }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Lock Screen

/// Lock Screen / banner presentation: route + elapsed time, the value of this ride, "73 % → 77 %" with the mini summit,
/// and the glass "Fahrt speichern" / "Beenden" buttons. Draws the widgets' brand sky as its background.
struct RideLockScreenView: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var isStale: Bool = false
    /// False in the in-app preview: the buttons are shown but run nothing.
    var isInteractive: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var payoff: RidePayoff? { state.payoff }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RideHeader(attributes: attributes, state: state, isStale: isStale, onDark: false)
            Spacer(minLength: 7)
            HStack(alignment: .bottom, spacing: 10) {
                RideValueBlock(state: state, onDark: false)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                RideSummitArt(climb: attributes.climb, payoff: payoff, onDark: false)
                    .frame(width: 112, height: 50)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unterwegs")
            .accessibilityValue(RideCopy.spokenSummary(attributes, state, isStale: isStale))
            Spacer(minLength: 9)
            RideActionRow(attributes: attributes, state: state, onDark: false, isInteractive: isInteractive)
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RideSkyBackdrop() }
        .activityBackgroundTint(Theme.background)
        .activitySystemActionForegroundColor(Theme.textPrimary)
    }
}

/// The widgets' sky ("Morgendämmerung" / "Blaue Stunde"), flat while the display is dimmed (Always-On).
struct RideSkyBackdrop: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            Theme.background
        } else {
            WidSkyBackground(family: .systemMedium)
        }
    }
}

// MARK: - Building blocks

/// Mode badge, "St. Anton → Innsbruck Hbf", caption and the running timer.
struct RideHeader: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var isStale: Bool
    var onDark: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            WidModeBadge(symbol: attributes.mode.symbolName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(attributes.routeTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RidePalette.primary(onDark))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 5) {
                    if let tone = toneColor {
                        Circle().fill(tone).frame(width: 6, height: 6)
                    }
                    Text(RideCopy.caption(attributes, state, isStale: isStale))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RidePalette.secondary(onDark))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if !state.phase.isFinal {
                RideTimer(attributes: attributes, onDark: onDark, size: 15)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Live tone dot (planner) or the stale warning.
    private var toneColor: Color? {
        if state.phase == .saved { return Theme.positive }
        if state.phase != .riding { return nil }
        if isStale { return Theme.dawn }
        switch state.status?.tone {
        case .onTime: return Theme.positive
        case .delayed: return Theme.gold
        case .disrupted: return Theme.negative
        case .neutral, .none: return nil
        }
    }
}

/// Elapsed time ("42:17", "1:05:09") – updated by the system every second.
struct RideTimer: View {
    var attributes: RideActivityAttributes
    var onDark: Bool
    var size: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "stopwatch")
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundStyle(RidePalette.secondary(onDark))
            Text(timerInterval: attributes.timerRange, countsDown: false)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(RidePalette.primary(onDark))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: size * 3.9, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unterwegs seit \(RideFormat.time(attributes.startedAt))")
    }
}

/// "+ € 49,80" and "73 % → 77 % amortisiert".
struct RideValueBlock: View {
    var state: RideActivityAttributes.ContentState
    var onDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RideFormat.plusEuro(state.valueEUR))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(RidePalette.value(onDark))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            payoffLine
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(RidePalette.secondary(onDark))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var payoffLine: Text {
        guard let payoff = state.payoff else { return Text("Wert dieser Fahrt") }
        let emphasis = RidePalette.emphasis(onDark)
        if payoff.isPaidOffBefore {
            let profit = Text(verbatim: "+ " + WidFormat.euroWhole(max(0, payoff.profitAfter)))
                .fontWeight(.bold)
                .foregroundStyle(RidePalette.profit(onDark))
            return Text("Reiner Gewinn · \(profit) im Plus")
        }
        if payoff.reachesSummit {
            let flag = Text(Image(systemName: "flag.fill")).foregroundStyle(Theme.gold)
            return Text("\(flag) Damit ist dein Ticket rentiert")
        }
        let after = Text(verbatim: RideFormat.percent(payoff.after, decimals: payoff.needsDecimals))
            .fontWeight(.bold)
            .foregroundStyle(emphasis)
        if state.phase == .saved {
            return Text("Jetzt \(after) amortisiert")
        }
        let before = Text(verbatim: RideFormat.percent(payoff.before, decimals: payoff.needsDecimals))
        return Text("\(before) → \(after) amortisiert")
    }
}

/// Buttons while riding; a confirmation once saved.
struct RideActionRow: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var onDark: Bool
    var isInteractive: Bool
    var height: CGFloat = 32

    var body: some View {
        switch state.phase {
        case .saved:
            RideConfirmationPill(text: "In deinen Fahrten gespeichert", onDark: onDark, height: height)
        case .ended:
            RideConfirmationPill(text: "Ohne Speichern beendet", symbol: "xmark.circle.fill", tint: RidePalette.secondary(onDark),
                                 onDark: onDark, height: height)
        case .riding, .arrived:
            HStack(spacing: 8) {
                saveButton
                discardButton
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        let label = RideSaveLabel(height: height)
        if isInteractive {
            Button(intent: RideSaveIntent(rideID: attributes.rideID)) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Fahrt speichern")
                .accessibilityValue(WidFormat.euroPrecise(state.valueEUR))
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fahrt speichern")
                .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private var discardButton: some View {
        let label = RideDiscardLabel(onDark: onDark, size: height)
        if isInteractive {
            Button(intent: RideDiscardIntent(rideID: attributes.rideID)) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Beenden, ohne zu speichern")
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Beenden, ohne zu speichern")
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// Prominent glass capsule in the CTA gradient with a specular rim: "✓ Fahrt speichern".
struct RideSaveLabel: View {
    var height: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: height * 0.38, weight: .bold))
            Text("Fahrt speichern")
                .font(.system(size: height * 0.45, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.onAccent)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            Capsule()
                .fill(Theme.ctaGradient)
                .overlay {
                    // Liquid-glass sheen: bright top edge fading into the tint.
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                             startPoint: .top, endPoint: .center))
                        .padding(1)
                }
                .overlay {
                    Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.08), Color.white.opacity(0.3)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing),
                                           lineWidth: 0.8)
                }
                .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 3)
        }
        .widgetAccentable()
        .contentShape(.capsule)
    }
}

/// Clear glass circle with "✕".
struct RideDiscardLabel: View {
    var onDark: Bool
    var size: CGFloat = 32

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = onDark || colorScheme == .dark
        Image(systemName: "xmark")
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(RidePalette.primary(onDark).opacity(0.8))
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(dark ? Color.white.opacity(0.14) : Color.white.opacity(0.6))
                    .overlay {
                        Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.45 : 0.95), Color.white.opacity(dark ? 0.06 : 0.3)],
                                                             startPoint: .top, endPoint: .bottom),
                                              lineWidth: 0.8)
                    }
            }
            .contentShape(.circle)
    }
}

/// "✓ In deinen Fahrten gespeichert"
struct RideConfirmationPill: View {
    var text: String
    var symbol: String = "checkmark.circle.fill"
    var tint: Color = Theme.positive
    var onDark: Bool
    var height: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: height * 0.44, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: height * 0.42, weight: .semibold))
                .foregroundStyle(RidePalette.primary(onDark))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Capsule().fill(tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dynamic Island

/// Expanded, leading: the mode badge beside the camera.
struct RideIslandLeading: View {
    var attributes: RideActivityAttributes

    var body: some View {
        WidModeBadge(symbol: attributes.mode.symbolName, size: 38)
            .padding(.leading, 2)
            .padding(.top, 2)
            .accessibilityLabel(attributes.mode.displayName)
    }
}

/// Expanded, trailing: value of this ride and the timer.
struct RideIslandTrailing: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(RideFormat.plusEuro(state.valueEUR))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(RidePalette.value(true))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if state.phase.isFinal {
                Text("Wert")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RidePalette.secondary(true))
            } else {
                RideTimer(attributes: attributes, onDark: true, size: 12.5)
            }
        }
        .padding(.trailing, 2)
        .padding(.top, 2)
        .environment(\.colorScheme, .dark)
    }
}

/// Expanded, center (below the camera): route and caption.
struct RideIslandCenter: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(attributes.routeTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RidePalette.primary(true))
            Text(RideCopy.caption(attributes, state, isStale: isStale))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RidePalette.secondary(true))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// Expanded, bottom: "73 % ▬▬▬▓▓░░ 77 %" and the buttons.
struct RideIslandBottom: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var isStale: Bool
    var isInteractive: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            if let payoff = state.payoff {
                payoffRow(payoff)
            }
            RideActionRow(attributes: attributes, state: state, onDark: true, isInteractive: isInteractive, height: 34)
        }
        .padding(.top, 6)
        .padding(.horizontal, 2)
        .environment(\.colorScheme, .dark)
    }

    private func payoffRow(_ payoff: RidePayoff) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dawn)
            Text(verbatim: RideFormat.percent(payoff.before, decimals: payoff.needsDecimals))
                .foregroundStyle(RidePalette.secondary(true))
            RidePayoffRail(payoff: payoff, onDark: true, height: 7)
            Text(verbatim: RideFormat.percent(payoff.after, decimals: payoff.needsDecimals))
                .fontWeight(.bold)
                .foregroundStyle(payoff.isPaidOffAfter ? RidePalette.profit(true) : RidePalette.emphasis(true))
        }
        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisation")
        .accessibilityValue("von \(RideFormat.percent(payoff.before, decimals: payoff.needsDecimals)) auf \(RideFormat.percent(payoff.after, decimals: payoff.needsDecimals))")
    }
}

/// Compact, leading: "⛰ 77 %" (after this ride).
struct RideIslandCompactLeading: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            if let payoff = state.payoff {
                Image(systemName: payoff.isPaidOffAfter ? "flag.fill" : "mountain.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(payoff.isPaidOffAfter ? Theme.gold : Theme.dawn)
                Text(verbatim: RideFormat.percent(payoff.after))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: attributes.mode.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.modeColor(attributes.mode))
            }
        }
        .lineLimit(1)
        .padding(.leading, 2)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.payoff.map { "Danach \(RideFormat.percent($0.after)) amortisiert" } ?? attributes.mode.displayName)
    }
}

/// Compact, trailing: "+€ 49,80".
struct RideIslandCompactTrailing: View {
    var state: RideActivityAttributes.ContentState

    var body: some View {
        Text(verbatim: RideFormat.compactPlusEuro(state.valueEUR))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(RidePalette.value(true))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.trailing, 2)
            .environment(\.colorScheme, .dark)
            .accessibilityLabel("Wert dieser Fahrt \(WidFormat.euroPrecise(state.valueEUR))")
    }
}

/// Minimal: progress ring (before in the route colours, this ride in dawn) around a tiny summit.
struct RideIslandMinimal: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState

    var body: some View {
        Group {
            if let payoff = state.payoff {
                RideMiniRing(payoff: payoff)
            } else {
                Image(systemName: attributes.mode.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.modeColor(attributes.mode))
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.payoff.map { "Danach \(RideFormat.percent($0.after)) amortisiert" } ?? attributes.mode.displayName)
    }
}

struct RideMiniRing: View {
    var payoff: RidePayoff
    var lineWidth: CGFloat = 3

    var body: some View {
        let before = CGFloat(min(max(payoff.before, 0), 1))
        let after = CGFloat(min(max(payoff.after, 0), 1))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(before, 0.02))
                .stroke(payoff.isPaidOffBefore ? AnyShapeStyle(Theme.positive) : AnyShapeStyle(Theme.glacier),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if after > before {
                Circle()
                    .trim(from: before, to: max(after, before + 0.02))
                    .stroke(payoff.reachesSummit ? Theme.gold : Theme.dawn, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Payoff rail

/// "73 % → 77 %" as a rail: current progress (glacier → dusk, pine when paid off) and this ride as a striped, glowing
/// dawn segment (gold when it reaches the summit) – the same language as the trip editor's impact card.
struct RidePayoffRail: View {
    var payoff: RidePayoff
    var onDark: Bool
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let before = CGFloat(min(max(payoff.before, 0), 1))
            let after = CGFloat(min(max(payoff.after, 0), 1))
            let start = max(0, width * before - height)
            let end = max(start + height, width * after)
            let segment = payoff.reachesSummit ? Theme.gold : Theme.dawn
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(onDark ? Color.white.opacity(0.16) : Theme.textTertiary.opacity(0.2))
                if after > before {
                    Capsule()
                        .fill(segment)
                        .overlay {
                            RideHatchShape(spacing: 4)
                                .stroke(Color.white.opacity(0.45), lineWidth: 1.2)
                                .clipShape(Capsule())
                        }
                        .shadow(color: segment.opacity(0.6), radius: 4)
                        .frame(width: end - start)
                        .offset(x: start)
                }
                Capsule()
                    .fill(payoff.isPaidOffBefore ? AnyShapeStyle(Theme.positive)
                                                 : AnyShapeStyle(LinearGradient(colors: [Theme.glacier, Theme.dusk],
                                                                                startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(height, width * before))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Diagonal stripes (the "new" part of a progress rail).
struct RideHatchShape: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += max(spacing, 1)
        }
        return path
    }
}

// MARK: - Mini summit

/// "Dein Weg zum Gipfel" in miniature: ridges, the ticket's value route so far, this ride as a glowing dawn segment up to
/// the climber, a dotted forecast to the summit (= ticket price) and the flag (gold once paid off).
struct RideSummitArt: View {
    var climb: [Double]
    var payoff: RidePayoff?
    /// On the black Dynamic Island: light strokes, translucent ridges.
    var onDark: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let layout = RideSummitLayout(size: geo.size, climb: climb, payoff: payoff)
            ZStack(alignment: .topLeading) {
                ridges(layout)
                if payoff != nil {
                    forecast(layout)
                    route(layout)
                    rideSegment(layout)
                }
                markers(layout)
            }
        }
        .accessibilityHidden(true)
    }

    private var isDark: Bool { onDark || colorScheme == .dark }

    private func ridges(_ l: RideSummitLayout) -> some View {
        let summit = l.unit(l.summit)
        let left = CGPoint(x: max(0.1, summit.x - 0.46), y: min(0.95, summit.y + (1 - summit.y) * 0.38))
        let right = CGPoint(x: min(0.99, summit.x + 0.16), y: min(0.95, summit.y + (1 - summit.y) * 0.26))
        let front = WidRidgeShape(peak: summit, seed: 7, drop: 0.86, roughness: 1)
        return ZStack {
            WidRidgeShape(peak: right, seed: 3, drop: 0.7, roughness: 1.2)
                .fill(isDark ? Theme.glacier.opacity(onDark ? 0.22 : 0.18) : Theme.glacier.opacity(0.16))
            WidRidgeShape(peak: left, seed: 11, drop: 0.8, roughness: 1.1)
                .fill(isDark ? Theme.dusk.opacity(onDark ? 0.34 : 0.3) : Theme.dusk.opacity(0.2))
            front.fill(LinearGradient(colors: frontColors, startPoint: .top, endPoint: .bottom))
            front.stroke(LinearGradient(colors: rimColors, startPoint: .leading, endPoint: .trailing), lineWidth: 1)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                   .init(color: .black.opacity(0.25), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var frontColors: [Color] {
        if onDark { return [Color.white.opacity(0.2), Color.white.opacity(0.03)] }
        if isDark { return [Theme.glacier2.opacity(0.26), Theme.glacier2.opacity(0.03)] }
        return [Color.white.opacity(0.9), Color.white.opacity(0.25)]
    }

    private var rimColors: [Color] {
        if onDark { return [Color.white.opacity(0.25), Theme.dawn2.opacity(0.7)] }
        if isDark { return [Theme.glacier2.opacity(0.28), Theme.dawn2.opacity(0.8)] }
        return [Color.white.opacity(0.75), Color.white]
    }

    private func route(_ l: RideSummitLayout) -> some View {
        ZStack(alignment: .topLeading) {
            WidRoutePath(points: l.route)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .blur(radius: 3.5)
                .opacity(isDark ? 0.5 : 0.35)
            WidRoutePath(points: l.route)
                .stroke(Theme.routeGradient, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            if l.isPaidOffBefore {
                // Above the summit line every trip is profit: the route turns pine.
                WidRoutePath(points: l.route)
                    .stroke(Theme.positive, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .mask(alignment: .top) { Rectangle().frame(height: max(l.priceY, 0)) }
            }
        }
    }

    private func rideSegment(_ l: RideSummitLayout) -> some View {
        let color = l.reachesSummit ? Theme.gold : Theme.dawn
        let path = Path { p in
            p.move(to: l.now)
            p.addQuadCurve(to: l.rideEnd, control: CGPoint(x: (l.now.x + l.rideEnd.x) / 2, y: l.now.y + (l.rideEnd.y - l.now.y) * 0.2))
        }
        return ZStack {
            path.stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).blur(radius: 3).opacity(0.7)
            path.stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    private func forecast(_ l: RideSummitLayout) -> some View {
        Group {
            if !l.isPaidOffAfter {
                Path { p in
                    p.move(to: l.rideEnd)
                    p.addLine(to: l.summit)
                }
                .stroke(onDark ? Color.white.opacity(0.55) : Theme.textSecondary.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1.4, 4]))
            }
        }
    }

    private func markers(_ l: RideSummitLayout) -> some View {
        let flagColor = l.isPaidOffAfter ? Theme.gold : Theme.dawn
        return ZStack(alignment: .topLeading) {
            WidFlagShape()
                .fill(flagColor)
                .frame(width: 9, height: 14)
                .position(x: l.summit.x + 3.5, y: l.summit.y - 7)
            Circle()
                .fill(flagColor)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.2))
                .frame(width: 5.5, height: 5.5)
                .position(l.summit)
            if payoff != nil {
                ZStack {
                    Circle()
                        .fill(Theme.accentSecondary.opacity(0.3))
                        .frame(width: 15, height: 15)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7.5, height: 7.5)
                        .overlay(Circle().stroke(Theme.accentSecondary, lineWidth: 2.2))
                }
                .position(l.rideEnd)
            }
        }
    }
}

/// Geometry of `RideSummitArt` in view coordinates.
struct RideSummitLayout {
    let size: CGSize
    let rect: CGRect
    /// Value route up to now (before this ride).
    let route: [CGPoint]
    let now: CGPoint
    let rideEnd: CGPoint
    let summit: CGPoint
    let priceY: CGFloat
    let isPaidOffBefore: Bool
    let isPaidOffAfter: Bool
    let reachesSummit: Bool

    init(size: CGSize, climb: [Double], payoff: RidePayoff?) {
        self.size = size
        rect = CGRect(x: 3, y: 15, width: max(size.width - 10, 1), height: max(size.height - 17, 1))
        let before = payoff?.before ?? 0
        let after = payoff?.after ?? before
        isPaidOffBefore = payoff?.isPaidOffBefore ?? false
        isPaidOffAfter = payoff?.isPaidOffAfter ?? false
        reachesSummit = payoff?.reachesSummit ?? false

        var values = climb.filter { $0.isFinite }.map { max(0, $0) }
        if values.isEmpty || (values.first ?? 0) > 0.02 { values.insert(0, at: 0) }
        if abs((values.last ?? 0) - before) > 0.005 { values.append(before) }
        if values.count == 1 { values.append(values[0]) }
        let top = max(1.18, after * 1.06, (values.max() ?? 0) * 1.06)

        let frame = rect
        func y(_ fraction: Double) -> CGFloat { frame.maxY - CGFloat(fraction / top) * frame.height }
        let xNow: CGFloat = isPaidOffAfter ? 0.66 : 0.56
        let xRide: CGFloat = xNow + 0.15
        let steps = CGFloat(max(values.count - 1, 1))
        let points = values.enumerated().map { index, value in
            CGPoint(x: frame.minX + frame.width * xNow * CGFloat(index) / steps, y: y(value))
        }
        route = points
        now = points.last ?? CGPoint(x: frame.minX, y: frame.maxY)
        rideEnd = CGPoint(x: frame.minX + frame.width * xRide, y: y(after))
        priceY = y(1)

        // The summit sits where the climb crosses the ticket price – ahead of the climber while below it.
        var summitX: CGFloat = 0.88
        if reachesSummit, after > before {
            summitX = xNow + (xRide - xNow) * CGFloat((1 - before) / (after - before))
        } else if isPaidOffBefore, let index = values.firstIndex(where: { $0 >= 1 }) {
            if index > 0 {
                let v0 = values[index - 1], v1 = values[index]
                let t = v1 > v0 ? (1 - v0) / (v1 - v0) : 1
                summitX = xNow * (CGFloat(index - 1) + CGFloat(t)) / steps
            } else {
                summitX = 0.04
            }
        }
        summit = CGPoint(x: frame.minX + frame.width * min(max(summitX, 0.04), 0.94), y: priceY)
    }

    /// A point in unit coordinates of the whole view (for the ridge shapes).
    func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
    }
}

// MARK: - Palette

/// Colours of the ride designs – on the black Dynamic Island the dark variants are forced.
enum RidePalette {
    static func primary(_ onDark: Bool) -> Color { onDark ? Color.white : Theme.textPrimary }
    static func secondary(_ onDark: Bool) -> Color { onDark ? Color.white.opacity(0.66) : Theme.textSecondary }
    /// "+ € 49,80" – dawn, like the new segment of the rail.
    static func value(_ onDark: Bool) -> Color { onDark ? Color(hex: "#FFAD85") : Theme.summitText }
    /// The percentage after this ride.
    static func emphasis(_ onDark: Bool) -> Color { onDark ? Color(hex: "#9DD3FF") : Theme.accentText }
    static func profit(_ onDark: Bool) -> Color { onDark ? Color(hex: "#6BD6A9") : Theme.positiveText }
}
