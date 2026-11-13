import SwiftUI
import KlimaCore

// MARK: themes – Farbe: the six palettes as cards, each a mini dashboard in light and dark side by side (docs/THEMES.md §2).
// Only palettes that pass every contrast gate are offered (`ThemeContrast.shippable` – today all six). The selection ring
// glides to the tapped card; VoiceOver reads "Zirbe, ausgewählt".

struct AppearancePaletteGrid: View {
    @Binding var selection: ThemePaletteID
    var onSelect: (ThemePaletteID) -> Void

    @Namespace private var namespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Built once: the contrast gates run over every palette.
    private static let offered: [ThemePalette] = ThemeContrast.shippable

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .top)]
            : [GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top), GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .top)]
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(Self.offered) { palette in
                card(palette)
            }
        }
    }

    private func card(_ palette: ThemePalette) -> some View {
        let isSelected = palette.id == selection
        let colors = ThemeRuntime.colors(for: palette.id)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        return Button {
            onSelect(palette.id)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                AppearanceSwatch(colors: colors)
                    .frame(height: 92)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Theme.separator, lineWidth: 1) }
                    .padding(4)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.Radius.tile + 4, style: .continuous)
                                .strokeBorder(colors.accent, lineWidth: 2.5)
                                .matchedGeometryEffect(id: "ring", in: namespace)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, colors.accent)
                                .background(Circle().fill(Theme.sheetBackground).padding(2))
                                .offset(x: 4, y: -4)
                                .motionTransition(.pop)
                        }
                    }
                    .scaleEffect(isSelected || reduceMotion ? 1 : 0.96)
                VStack(alignment: .leading, spacing: 1) {
                    Text(palette.name)
                        .font(.subheadline.weight(isSelected ? .bold : .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(palette.tagline)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, Theme.Spacing.xxs)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSelected ? "\(palette.name), ausgewählt" : palette.name)
        .accessibilityValue(palette.tagline)
        .accessibilityHint(isSelected ? "" : "Doppeltippen, um diese Farbe zu wählen.")
        // The state is in the label ("Zirbe, ausgewählt"); an extra selected trait would make VoiceOver say it twice.
        .accessibilityAddTraits(.isButton)
    }
}

/// A palette at a glance: the same mini dashboard in light (left) and dark (right).
struct AppearanceSwatch: View {
    var colors: ThemeColorSet

    var body: some View {
        HStack(spacing: 0) {
            half.environment(\.colorScheme, .light)
            half.environment(\.colorScheme, .dark)
        }
        .accessibilityHidden(true)
    }

    private var half: some View {
        ZStack(alignment: .topLeading) {
            Theme.background
            RadialGradient(colors: [colors.accent.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 90)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(colors.accent).frame(width: 12, height: 12)
                    Capsule().fill(Theme.textPrimary.opacity(0.7)).frame(width: 26, height: 5)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(colors.accentText).frame(width: 30, height: 4)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceSecondary)
                        Capsule().fill(colors.routeGradient).frame(width: 40)
                    }
                    .frame(height: 5)
                }
                .padding(7)
                .background(Theme.surface, in: .rect(cornerRadius: 8, style: .continuous))
                Capsule()
                    .fill(colors.ctaGradient)
                    .frame(width: 38, height: 12)
            }
            .padding(9)
        }
    }
}
