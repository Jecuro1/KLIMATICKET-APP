import SwiftUI
import KlimaCore

// MARK: themes – the option control of Look & Feel (Bewegung, Haptik, Zahlen): a Liquid Glass capsule whose selection glides
// (it is a control, DESIGN.md §2). Each segment is as wide as its label needs plus an equal share of the rest, so
// "Immer mit Cent" stays whole next to "Automatisch"; above the default text size the options stack as full-width rows.
// The caller decides what the change plays (Haptik plays its own level, everything else a tick).

struct AppearanceChoice<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [Value]
    /// Tint of the selection (the palette being chosen, so the screen previews it).
    var tint: Color
    var title: (Value) -> String
    /// What plays when the selection changes; nil plays nothing.
    var feedback: (Value) -> SensoryFeedback?
    /// VoiceOver: "Beträge" – read before the option.
    var accessibilityName: String

    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize > .large {
                VStack(spacing: Theme.Spacing.xxs) {
                    ForEach(options, id: \.self) { option in
                        row(option)
                    }
                }
                .padding(Theme.Spacing.xxs)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
            } else {
                AppearanceSegmentLayout(spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        segment(option)
                    }
                }
                .padding(3)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .sensoryFeedback(trigger: selection) { _, new in
            MotionPolicy.isScreenshot ? nil : feedback(new)
        }
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            choose(option)
        } label: {
            Text(title(option))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(tint.opacity(colorScheme == .dark ? 0.3 : 0.16))
                            .overlay(Capsule().strokeBorder(tint.opacity(colorScheme == .dark ? 0.5 : 0.4), lineWidth: 1))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable(scale: 0.97))
        .accessibilityLabel("\(accessibilityName): \(title(option))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func row(_ option: Value) -> some View {
        let isSelected = option == selection
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile - 4, style: .continuous)
        return Button {
            choose(option)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Text(title(option))
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? tint : Theme.textTertiary)
                    .symbolReplaceTransition()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background {
                if isSelected {
                    shape.fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.12))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable(scale: 0.98))
        .accessibilityLabel("\(accessibilityName): \(title(option))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func choose(_ option: Value) {
        guard option != selection else { return }
        withMotion(Motion.snappy) { selection = option }
    }
}

/// Segments as wide as their labels need, plus an equal share of what is left; when the labels need more than there is,
/// each gets its share in proportion to its label (the label then scales down a little, `minimumScaleFactor`).
struct AppearanceSegmentLayout: Layout {
    var spacing: CGFloat

    private func widths(for subviews: Subviews, in available: CGFloat) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let room = max(0, available - spacing * CGFloat(max(subviews.count - 1, 0)))
        let total = ideal.reduce(0, +)
        guard total > 0 else { return ideal.map { _ in room / CGFloat(max(subviews.count, 1)) } }
        if total <= room {
            let extra = (room - total) / CGFloat(subviews.count)
            return ideal.map { $0 + extra }
        }
        return ideal.map { room * $0 / total }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let width = proposal.width ?? (ideal.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
        let assigned = widths(for: subviews, in: width)
        let height = zip(subviews, assigned).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(for: subviews, in: bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}
