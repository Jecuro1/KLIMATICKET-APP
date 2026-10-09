import SwiftUI

/// Einstellungen › Darstellung › App-Symbol (CI screenshots `appIcon`, `appIconSunrise`).
/// A zoomed-in home screen shows the chosen icon in context – light or dark, like the real home screen – and the
/// grid below switches it. Motion (docs/MOTION.md): the blocks reveal once in reading order, the new icon pops onto
/// the stage with a one-shot glow (`Motion.bouncy`), the selection ring glides to the tapped tile and the check pops;
/// Reduce Motion turns all of it into cross-fades, screenshots show the end state. Nothing loops.
struct AppIconPickerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var selectionNamespace

    /// CI screenshot routes preselect an icon (UI state only, no system alert).
    var screenshotChoice: AppIconChoice? = nil

    /// nil = follow the app's colour scheme.
    @State private var previewScheme: ColorScheme?
    @State private var showsNavigationTitle = false
    /// Bumped on every switch: drives the stage glow and the selection haptic.
    @State private var changeCount = 0
    @State private var failureCount = 0

    @ScaledMetric(relativeTo: .body) private var scaledIconSize: CGFloat = 64

    private var store: AppIconStore { AppIconStore.shared }
    private var iconSize: CGFloat { min(scaledIconSize, 92) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header
                    .reveal(order: 0)
                IconHomeStage(choice: store.current, scheme: previewScheme ?? colorScheme, pulse: changeCount,
                              schemeSelection: schemeBinding)
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .reveal(order: 1)
                activeCaption
                    .reveal(order: 2)
                choices
                    .reveal(order: 3)
                Text("iOS bestätigt den Wechsel kurz mit einer Mitteilung. Jedes Symbol hat eine helle, eine dunkle und eine getönte Variante – passend zu deinem Home-Bildschirm.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.screen)
                    .reveal(.fade, order: 4)
            }
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .revealScope()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, isPastHeader in
            withMotion(Motion.crossfade) { showsNavigationTitle = isPastHeader }
        }
        .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.45) }
        .navigationTitle("App-Symbol")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("App-Symbol")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavigationTitle)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .haptic(.selection, trigger: changeCount)
        .haptic(.error, trigger: failureCount)
        .onAppear {
            if let screenshotChoice, LaunchMode.isScreenshot { store.select(screenshotChoice) }
        }
    }

    private var schemeBinding: Binding<ColorScheme> {
        // GlassSegmentedPicker sets it inside `withMotion(Motion.snappy)` – the wallpaper cross-fades with the capsule.
        Binding(get: { previewScheme ?? colorScheme }, set: { previewScheme = $0 })
    }

    // MARK: Header & caption

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: "Für deinen Home-Bildschirm")
            Text("App-Symbol")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Such dir aus, wie KlimaBilanz auf deinem Home-Bildschirm aussieht.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
    }

    private var activeCaption: some View {
        let choice = store.current
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(choice.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentTransition(.opacity)
            Spacer(minLength: 0)
            SetPill(text: "Aktiv", symbol: "checkmark", tint: Theme.positiveText)
        }
        .motionAnimation(Motion.snappy, value: choice)
        .padding(.horizontal, Theme.Spacing.screen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aktives App-Symbol: \(choice.title). \(choice.subtitle)")
    }

    // MARK: Choices

    private var choices: some View {
        SurfaceCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Kicker(text: "Alle Symbole")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum), spacing: Theme.Spacing.s, alignment: .top)],
                          spacing: Theme.Spacing.l) {
                    ForEach(AppIconChoice.allCases) { choice in
                        tile(choice)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }

    private var tileMinimum: CGFloat {
        max(iconSize + 30, dynamicTypeSize.isAccessibilitySize ? 140 : 92)
    }

    private func tile(_ choice: AppIconChoice) -> some View {
        let isSelected = choice == store.current
        let ringRadius = iconSize * 0.2237 + 6  // concentric with the icon (6 pt padding)
        return Button {
            select(choice)
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                AppIconImage(choice: choice, size: iconSize)
                    .shadow(color: Color(red: 26 / 255, green: 52 / 255, blue: 96 / 255).opacity(isSelected ? 0.26 : 0.12),
                            radius: isSelected ? 10 : 5, y: isSelected ? 6 : 3)
                    .padding(6)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: ringRadius, style: .continuous)
                                .strokeBorder(Theme.accent, lineWidth: 2.5)
                                .matchedGeometryEffect(id: "ring", in: selectionNamespace)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Theme.accent)
                                .background(Circle().fill(Theme.sheetBackground).padding(2))
                                .offset(x: 6, y: -6)
                                .motionTransition(.pop)
                        }
                    }
                    .scaleEffect(isSelected || reduceMotion ? 1 : 0.93)
                Text(choice.title)
                    .font(.footnote.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("App-Symbol \(choice.title)")
        .accessibilityValue(choice.subtitle)
        .accessibilityHint(isSelected ? "" : "Doppeltippen, um dieses Symbol zu verwenden.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != store.current, !store.isChanging else { return }
        withMotion(Motion.bouncy) {
            changeCount += 1
            store.select(choice) { changed in
                guard !changed else { return }
                failureCount += 1
                app.showToast("exclamationmark.triangle.fill", "App-Symbol nicht geändert", "Bitte versuch es gleich noch einmal.")
            }
        }
    }
}

// MARK: - Stage

/// A zoomed-in home screen: wallpaper, neighbouring apps as frosted placeholders, the chosen icon with its label,
/// and the light/dark switch. Illustration only – hidden from VoiceOver except for the switch.
private struct IconHomeStage: View {
    var choice: AppIconChoice
    var scheme: ColorScheme
    var pulse: Int
    @Binding var schemeSelection: ColorScheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let iconSize: CGFloat = 74
    private let columnSpacing: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        ZStack {
            wallpaper
            VStack(spacing: 22) {
                HStack(spacing: columnSpacing) {
                    ForEach(0..<3, id: \.self) { _ in placeholder }
                }
                HStack(alignment: .top, spacing: columnSpacing) {
                    placeholder
                    activeIcon
                    placeholder
                }
            }
            .offset(y: -6)
            .accessibilityHidden(true)
        }
        .frame(height: 252)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(alignment: .topTrailing) {
            schemeToggle
                .padding(Theme.Spacing.s)
        }
        .overlay {
            shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.5), lineWidth: 1)
        }
        .shadow(color: Color(red: 26 / 255, green: 52 / 255, blue: 96 / 255).opacity(scheme == .dark ? 0.3 : 0.16),
                radius: 16, y: 8)
        .environment(\.colorScheme, scheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vorschau auf dem Home-Bildschirm: \(choice.title)")
    }

    // Wallpaper: the Alpine sky – morning (light) or blue hour (dark), with two ridges.
    private var wallpaper: some View {
        let dark = scheme == .dark
        return ZStack {
            LinearGradient(colors: dark ? [Color(hex: "#081332"), Color(hex: "#1B2160"), Color(hex: "#3B2A6E")]
                                        : [Color(hex: "#3F7BD8"), Color(hex: "#7B74E0"), Color(hex: "#E59A92")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: dark ? "#FF8FAB" : "#FFC49E").opacity(dark ? 0.28 : 0.55), .clear],
                           center: UnitPoint(x: 0.72, y: 0.62), startRadius: 0, endRadius: 220)
            RidgeShape(peakX: 0.74, peakY: 0.58, seed: 11, roughness: 0.9)
                .fill(Color.white.opacity(dark ? 0.07 : 0.16))
            RidgeShape(peakX: 0.28, peakY: 0.74, seed: 4, roughness: 0.8)
                .fill(Color.white.opacity(dark ? 0.09 : 0.22))
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous)
                .fill(Color.white.opacity(reduceTransparency ? 0.3 : (scheme == .dark ? 0.1 : 0.2)))
                .overlay {
                    RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous)
                        .strokeBorder(Color.white.opacity(scheme == .dark ? 0.16 : 0.32), lineWidth: 0.8)
                }
                .frame(width: iconSize, height: iconSize)
            Capsule()
                .fill(Color.white.opacity(scheme == .dark ? 0.22 : 0.38))
                .frame(width: 38, height: 6)
                .padding(.vertical, 3)
        }
    }

    private var activeIcon: some View {
        VStack(spacing: 7) {
            ZStack {
                if !reduceMotion && !MotionPolicy.isStatic {
                    IconGlowPulse(color: choice.glow, size: iconSize, trigger: pulse)
                }
                AppIconImage(choice: choice, size: iconSize)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                    .id(choice)
                    .motionTransition(.asymmetric(insertion: .scale(scale: 0.55).combined(with: .opacity),
                                                  removal: .scale(scale: 1.18).combined(with: .opacity)))
            }
            .frame(width: iconSize, height: iconSize)
            Text("KlimaBilanz")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .lineLimit(1)
                .fixedSize()
                .frame(width: iconSize)
        }
    }

    // Light / dark preview switch (Liquid Glass – it is a control; the capsule glides, selection haptic built in).
    private var schemeToggle: some View {
        GlassSegmentedPicker(selection: $schemeSelection, options: [ColorScheme.light, ColorScheme.dark]) { option in
            Image(systemName: option == .light ? "sun.max.fill" : "moon.fill")
                .accessibilityLabel(option == .light ? "Vorschau hell" : "Vorschau dunkel")
        }
        .fixedSize()
    }
}

/// One-shot bloom behind the stage icon after a switch (no repeat, nothing left running).
private struct IconGlowPulse: View {
    var color: Color
    var size: CGFloat
    var trigger: Int

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size * 1.15, height: size * 1.15)
            .blur(radius: 20)
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, value in
                view
                    .opacity(value)
                    .scaleEffect(0.7 + value * 0.6)
            } keyframes: { _ in
                CubicKeyframe(0.9, duration: 0.16)
                CubicKeyframe(0.0, duration: 0.8)
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Settings row

/// "App-Symbol" row in Einstellungen › Darstellung: the current icon as the row's tile.
struct AppIconSettingsRow: View {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let choice = AppIconStore.shared.current
        NavigationLink {
            AppIconPickerView()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App-Symbol")
                    Text(choice.title)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                }
            } icon: {
                AppIconImage(choice: choice, size: 30 * min(max(scale, 1), 1.6))
            }
        }
        .accessibilityLabel("App-Symbol")
        .accessibilityValue(choice.title)
    }
}
