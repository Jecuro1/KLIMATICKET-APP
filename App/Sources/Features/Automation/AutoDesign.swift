import SwiftUI
import KlimaCore

// MARK: automation – the building blocks of Einstellungen › Automatik (docs/AUTOMATION.md §5): the trigger's icon and tint, the
// tile, the sentence tokens and their wrapping layout, weekday chips, the 16-place budget bar and the notice preview. Theme and
// Motion tokens only.

extension AutoTriggerKind {
    var autoSymbol: String {
        switch self {
        case .ticketDeadline: "calendar.badge.exclamationmark"
        case .milestone: "flag.checkered"
        case .dayWithoutTrip: "moon.stars.fill"
        case .followDelay: "clock.badge.exclamationmark"
        case .tripLogged: "checkmark.seal.fill"
        }
    }

    var autoTint: Color {
        switch self {
        case .ticketDeadline: Theme.gold
        case .milestone: Theme.dawn
        case .dayWithoutTrip: Theme.dusk
        case .followDelay: Theme.alpenglow
        case .tripLogged: Theme.pine
        }
    }
}

extension AutoConditionKind {
    var autoTitle: String {
        switch self {
        case .weekdays: "Nur an bestimmten Tagen"
        case .timeWindow: "Nur zu bestimmten Zeiten"
        case .noTripToday: "Nur wenn heute noch keine Fahrt erfasst ist"
        case .validTicket: "Nur mit gültigem Ticket"
        }
    }

    var autoSymbol: String {
        switch self {
        case .weekdays: "calendar"
        case .timeWindow: "clock"
        case .noTripToday: "tram"
        case .validTicket: "ticket"
        }
    }
}

/// The rule's icon: a rounded tile in the trigger's colour, dimmed while the rule is off.
struct AutoKindTile: View {
    var kind: AutoTriggerKind
    var isOn: Bool = true
    var size: CGFloat = 40

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(max(scale, 1), 1.5)
        let tint = kind.autoTint
        Image(systemName: kind.autoSymbol)
            .font(.system(size: side * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: side * 0.3, style: .continuous))
            .saturation(isOn ? 1 : 0)
            .opacity(isOn ? 1 : 0.45)
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }
}

/// A word of the rule sentence („Wenn“, „und“, „dann“).
struct AutoSentenceWord: View {
    var text: String
    var isMuted = false

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .foregroundStyle(isMuted ? Theme.textTertiary : Theme.textPrimary)
            .padding(.vertical, 6)
    }
}

/// A tappable part of the rule sentence: a tinted capsule that opens a menu.
struct AutoToken: View {
    var text: String
    var tint: Color
    var symbol: String? = nil
    var isPlaceholder = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(isPlaceholder ? Theme.textSecondary : Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(isPlaceholder ? 0.06 : 0.16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(isPlaceholder ? 0.25 : 0.4), style: StrokeStyle(lineWidth: 1, dash: isPlaceholder ? [4, 3] : []))
        }
        .contentShape(.rect(cornerRadius: 14))
    }
}

/// Wraps its children like words in a line (the rule sentence). Each line is centred vertically.
struct AutoFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// Mo … So as seven chips. At least one day stays selected.
struct AutoWeekdayPicker: View {
    @Binding var selection: Set<RouteWeekday>
    var tint: Color = Theme.accent

    var body: some View {
        AutoFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(RouteWeekday.allCases, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    withMotion(Motion.snappy) {
                        if isOn { if selection.count > 1 { selection.remove(day) } } else { selection.insert(day) }
                    }
                } label: {
                    Text(day.shortName)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 34, minHeight: 34)
                        .padding(.horizontal, 4)
                        .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
                        .background(isOn ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(Theme.surfaceSecondary), in: .capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(AutoText.weekdayName(day))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .haptic(.selection, trigger: selection)
    }
}

/// The 16 places of the automation among the 64 pending notifications of iOS – one segment per planned notice.
struct AutoBudgetBar: View {
    var used: Int
    var ceiling: Int = AutoRuleScheduler.slotCeiling
    var waiting: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    caption
                    Spacer(minLength: Theme.Spacing.xs)
                    count
                }
                VStack(alignment: .leading, spacing: 2) {
                    caption
                    count
                }
            }
            segments
                .frame(height: 10)
                .motionAnimation(Motion.smooth, value: used)
                .accessibilityHidden(true)
            if waiting > 0 {
                Text("+ \(waiting) warten")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.summitText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Geplante Mitteilungen: \(min(used, ceiling)) von \(ceiling) Plätzen belegt\(waiting > 0 ? ", \(waiting) warten" : "")")
    }

    private var caption: some View {
        Text("Geplante Mitteilungen")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var count: some View {
        Text("\(min(used, ceiling)) von \(ceiling)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(waiting > 0 ? Theme.summitText : Theme.textSecondary)
            .numericValue(Double(used))
    }

    private var segments: some View {
        ZStack {
            HStack(spacing: 3) {
                ForEach(0..<ceiling, id: \.self) { _ in Capsule().fill(Theme.surfaceSecondary) }
            }
            Theme.routeGradient
                .mask {
                    HStack(spacing: 3) {
                        ForEach(0..<ceiling, id: \.self) { index in Capsule().opacity(index < used ? 1 : 0) }
                    }
                }
        }
    }
}

/// What a notice looks like on the lock screen: app icon, „KlimaBilanz“, title, the rule, the text. Only a preview.
struct AutoNoticePreview: View {
    var title: String
    var ruleName: String
    var message: String
    var timeText: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            SetAppIconView(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("KLIMABILANZ")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Automatik · \(ruleName)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.s)
        .background(Theme.surface, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vorschau der Mitteilung: \(title). \(message)")
    }
}

/// A row of choices as capsules that wrap at large text sizes (minutes, days, percent).
struct AutoChoiceChips<Value: Hashable>: View {
    var choices: [Value]
    var isSelected: (Value) -> Bool
    var title: (Value) -> String
    var accessibilityTitle: ((Value) -> String)? = nil
    var tap: (Value) -> Void

    var body: some View {
        AutoFlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
            ForEach(choices, id: \.self) { value in
                let isOn = isSelected(value)
                Button {
                    withMotion(Motion.snappy) { tap(value) }
                } label: {
                    Text(title(value))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
                        .background(isOn ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(Theme.surfaceSecondary), in: .capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(accessibilityTitle?(value) ?? title(value))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}
