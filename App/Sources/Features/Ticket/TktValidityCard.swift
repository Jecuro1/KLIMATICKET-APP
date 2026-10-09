import SwiftUI
import KlimaCore

/// „Gültigkeit“ (DESIGN.md §5.5, synthesis §8.16): big days-left numeral, "Tag 223 von 365" pill, timeline
/// start → heute → ende with the break-even flag, and a footer "€ 52 vor Plan · Break-even 48 Tage vor Ablauf".
struct TktValidityCard: View {
    var start: Date
    var end: Date
    var summary: SavingsSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownDays: Double = 0

    /// Read when the body runs – a stored `now = Date()` would differ on every parent update and defeat SwiftUI's diffing.
    private var now: Date { Date() }

    var body: some View {
        GlassCard(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                TktValidityRail(progress: progress,
                                showsToday: phase == .active,
                                flag: flag,
                                startLabel: Format.dayMonth(start),
                                endLabel: Format.dayMonth(end),
                                accessibilityText: railAccessibilityText)
                    .padding(.top, Theme.Spacing.xs)
                TktHairline()
                    .padding(.top, Theme.Spacing.xxs)
                footer
            }
        }
        .onAppear { reveal(animated: !(reduceMotion || LaunchMode.isScreenshot)) }
        .onChange(of: numeral) { _, _ in reveal(animated: !reduceMotion) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Gültigkeit")
                numeralRow
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(pillText)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xs + 2)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.surfaceSecondary, in: .capsule)
                .fixedSize()
        }
    }

    private var numeralRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Text(Format.number(shownDays))
                .font(Theme.Typography.priceNumeral)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: shownDays))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(numeral) \(unit)")
    }

    // MARK: Footer

    private var footer: some View {
        footerText
            .font(.footnote.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(footerAccessibilityText)
    }

    /// Same content as the footer, with forecasts spelled out ("≈" → "voraussichtlich") and without the arrow glyph.
    private var footerAccessibilityText: String {
        switch phase {
        case .upcoming:
            return "Startet am \(Format.date(start, .long)), \(Format.days(summary.daysTotal)) gültig"
        case .expired:
            return summary.isPaidOff
                ? "Ticketjahr beendet, \(SummitFigures.euro(summary.shownProfitEuro)) gespart"
                : "Ticketjahr beendet, \(SummitFigures.euro(summary.shownRemainingEuro)) gefehlt"
        case .active:
            guard summary.tripCount > 0 else { return "Erfasse deine Fahrten für eine Prognose." }
            let delta = planDelta
            let plan = delta >= 0 ? "\(Format.euro(delta, decimals: 0)) vor Plan" : "\(Format.euro(-delta, decimals: 0)) hinter Plan"
            return "\(plan), \(breakEvenPhrase.replacingOccurrences(of: "≈", with: "voraussichtlich"))"
        }
    }

    private var footerText: Text {
        switch phase {
        case .upcoming:
            return Text("Startet am \(Format.date(start, .long)) · \(Format.days(summary.daysTotal)) gültig")
                .foregroundStyle(Theme.textSecondary)
        case .expired:
            // Whole euros from the same rounded figures as the Übersicht ("– € 0" can never appear).
            let paidOff = summary.isPaidOff
            let result = paidOff ? "+ \(SummitFigures.euro(summary.shownProfitEuro)) gespart"
                                 : "\(SummitFigures.euro(summary.shownRemainingEuro)) gefehlt"
            let color = paidOff ? Theme.positiveText : Theme.summitText
            return Text("Ticketjahr beendet · \(Text(result).foregroundStyle(color).fontWeight(.semibold))")
                .foregroundStyle(Theme.textSecondary)
        case .active:
            guard summary.tripCount > 0 else {
                return Text("Erfasse deine Fahrten – dann zeigen wir dir hier, wann sich dein Ticket rentiert.")
                    .foregroundStyle(Theme.textSecondary)
            }
            let delta = planDelta
            let ahead = delta >= 0
            let symbol = ahead ? "arrow.up.right" : "arrow.down.right"
            let amount = Format.euro(abs(delta), decimals: 0)
            let plan = ahead ? "\(amount) vor Plan" : "\(amount) hinter Plan"
            let color = ahead ? Theme.positiveText : Theme.summitText
            let lead = Text("\(Image(systemName: symbol)) \(plan)").foregroundStyle(color).fontWeight(.semibold)
            return Text("\(lead) · \(breakEvenPhrase)")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var breakEvenPhrase: String {
        if let paid = summary.paidOffDate { return "rentiert seit \(Format.dayMonth(paid))" }
        if let date = summary.forecastBreakEvenDate, date <= end {
            let buffer = Self.dayDistance(from: date, to: end)
            return buffer > 0 ? "Break-even ≈ \(Format.days(buffer)) vor Ablauf" : "Break-even ≈ am letzten Tag"
        }
        return "Break-even bei diesem Tempo erst nach Ablauf"
    }

    /// Value minus the pro-rata share of the ticket price ("Soll") for the days elapsed.
    private var planDelta: Double {
        let plan = summary.ticketPrice * Double(summary.daysElapsed) / Double(max(summary.daysTotal, 1))
        return summary.totalValue - plan
    }

    // MARK: State

    private enum Phase: Equatable { case upcoming, active, expired }

    private var phase: Phase {
        if now < start { return .upcoming }
        if now > end { return .expired }
        return .active
    }

    private var daysUntilStart: Int { max(1, Self.dayDistance(from: now, to: start)) }

    private var numeral: Int {
        switch phase {
        case .upcoming: daysUntilStart
        case .active: summary.daysRemaining
        case .expired: 0
        }
    }

    private var unit: String {
        switch phase {
        case .upcoming:
            return daysUntilStart == 1 ? "Tag bis zum Start" : "Tage bis zum Start"
        case .active:
            if summary.daysRemaining == 0 { return "Tage übrig · heute letzter Tag" }
            return summary.daysRemaining == 1 ? "Tag übrig" : "Tage übrig"
        case .expired:
            return "Tage übrig"
        }
    }

    private var pillText: String {
        switch phase {
        case .upcoming: "ab \(Format.dayMonth(start))"
        case .active: "Tag \(summary.daysElapsed) von \(summary.daysTotal)"
        case .expired: "Abgelaufen"
        }
    }

    private var progress: Double {
        switch phase {
        case .upcoming: 0
        case .expired: 1
        case .active: Self.fraction(of: now, start: start, end: end)
        }
    }

    private var flag: TktRailFlag? {
        if let date = summary.paidOffDate {
            return TktRailFlag(fraction: Self.fraction(of: date, start: start, end: end),
                               label: "Rentiert \(Format.dayMonth(date))", reached: true)
        }
        if phase == .active, let date = summary.forecastBreakEvenDate, date <= end {
            return TktRailFlag(fraction: Self.fraction(of: date, start: start, end: end),
                               label: "Break-even ≈ \(Format.dayMonth(date))", reached: false)
        }
        return nil
    }

    private var railAccessibilityText: String {
        var parts = ["\(Format.date(start, .long)) bis \(Format.date(end, .long))"]
        if phase == .active { parts.append("heute Tag \(summary.daysElapsed) von \(summary.daysTotal)") }
        if let paid = summary.paidOffDate {
            parts.append("rentiert seit \(Format.date(paid, .long))")
        } else if phase == .active, let date = summary.forecastBreakEvenDate, date <= end {
            parts.append("Break-even voraussichtlich am \(Format.date(date, .long))")
        }
        return parts.joined(separator: ", ")
    }

    private func reveal(animated: Bool) {
        let target = Double(numeral)
        if animated {
            withAnimation(.spring(duration: 0.9, bounce: 0.12)) { shownDays = target }
        } else {
            shownDays = target
        }
    }

    private static func fraction(of date: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }

    private static func dayDistance(from a: Date, to b: Date) -> Int {
        let cal = Calendar.vienna
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }
}

// MARK: - Timeline

private struct TktRailFlag: Equatable {
    var fraction: Double
    var label: String
    var reached: Bool
}

/// Track (route gradient up to today), "Heute" knob, break-even pennant with its date, start/end labels.
/// Labels are placed with alignment guides so they keep their natural (Dynamic Type) height.
private struct TktValidityRail: View {
    var progress: Double
    var showsToday: Bool
    var flag: TktRailFlag?
    var startLabel: String
    var endLabel: String
    var accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var reveal: Double = LaunchMode.isScreenshot ? 1 : 0

    private let trackHeight: CGFloat = 8
    private let knobSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if let flag { flagCaption(flag) }
            track
            labels
        }
        .onGeometryChange(for: CGFloat.self, of: { proxy in proxy.size.width }, action: { newWidth in
            width = newWidth
        })
        .onAppear {
            guard reveal < 1 else { return }
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.spring(duration: 1.1, bounce: 0.1).delay(0.25)) { reveal = 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue(accessibilityText)
    }

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    private var track: some View {
        let w = max(width, 1)
        let p = clampedProgress * reveal
        let x = w * p
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.surfaceSecondary)
                .frame(height: trackHeight)
            Capsule()
                .fill(Theme.routeGradient)
                .frame(height: trackHeight)
                .mask(alignment: .leading) {
                    Capsule().frame(width: max(trackHeight, x))
                }
                .opacity(p > 0 ? 1 : 0)
            if let flag {
                flagMark(flag)
                    .offset(x: w * min(max(flag.fraction, 0), 1) - 1.25, y: -10)
            }
            if showsToday {
                knob
                    .offset(x: min(max(x - knobSize / 2, 0), max(w - knobSize, 0)))
            }
        }
        .frame(height: 26)
    }

    private func flagMark(_ flag: TktRailFlag) -> some View {
        FlagShape()
            .fill(flag.reached ? Theme.positive : Theme.summit)
            .frame(width: 14, height: 22)
            .opacity(reveal)
    }

    private var knob: some View {
        Circle()
            .fill(Color.white)
            .frame(width: knobSize, height: knobSize)
            .overlay(Circle().strokeBorder(Theme.accentSecondary, lineWidth: 3.5))
            .shadow(color: Theme.accentSecondary.opacity(0.45), radius: 5, y: 2)
    }

    /// "Break-even 14. Dez." – right-aligned to the pennant, flips to its right side near the start.
    private func flagCaption(_ flag: TktRailFlag) -> some View {
        let total = max(width, 1)
        let fx = total * min(max(flag.fraction, 0), 1)
        return ZStack(alignment: .leading) {
            Color.clear.frame(height: 0)
            Text(flag.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(flag.reached ? Theme.positiveText : Theme.summitText)
                .fixedSize()
                .alignmentGuide(.leading) { d in
                    let preferred = fx - 6 - d.width
                    let x = preferred >= 0 ? preferred : min(fx + 16, max(total - d.width, 0))
                    return -x
                }
        }
        .opacity(reveal)
    }

    /// "1. März" · "Heute" (centred on the knob) · "28. Feb." – edge labels give way when they would collide.
    private var labels: some View {
        let total = max(width, 1)
        let tx = total * clampedProgress
        let hideStart = showsToday && clampedProgress < 0.2
        let hideEnd = showsToday && clampedProgress > 0.8
        return ZStack(alignment: .leading) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(startLabel)
                    .opacity(hideStart ? 0 : 1)
                Spacer(minLength: 0)
                Text(endLabel)
                    .opacity(hideEnd ? 0 : 1)
            }
            .foregroundStyle(Theme.textSecondary)
            if showsToday {
                Text("Heute")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in
                        -min(max(tx - d.width / 2, 0), max(total - d.width, 0))
                    }
                    .opacity(reveal)
            }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
    }
}
