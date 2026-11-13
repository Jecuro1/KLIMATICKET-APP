import SwiftUI
import KlimaCore

// MARK: themes – the option control of Look & Feel (Bewegung, Haptik, Zahlen): a Liquid Glass capsule whose selection glides
// (it is a control, DESIGN.md §2). At accessibility sizes the options stack as full-width rows, so "Immer mit Cent" never
// breaks letter by letter. The caller decides what the change plays (Haptik plays its own level, everything else a tick).

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
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.xxs) {
                    ForEach(options, id: \.self) { option in
                        row(option)
                    }
                }
                .padding(Theme.Spacing.xxs)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
            } else {
                HStack(spacing: 2) {
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
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.s)
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
