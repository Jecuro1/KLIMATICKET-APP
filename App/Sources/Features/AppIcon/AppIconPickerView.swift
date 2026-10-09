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
    /// CI screenshot route `appIconAXList` opens scrolled to the end.  // MARK: review-icons
    var screenshotAnchor: UnitPoint? = nil

    /// nil = follow the app's colour scheme.
    @State private var previewScheme: ColorScheme?
    @State private var showsNavigationTitle = false
    /// Bumped on every switch: drives the stage glow and the selection haptic.
    @State private var changeCount = 0

    @ScaledMetric(relativeTo: .body) private var scaledIconSize: CGFloat = 64

    private var store: AppIconStore { AppIconStore.shared }
    private static let unbreakableBrand = "KlimaBilanz".map(String.init).joined(separator: "\u{2060}")  // MARK: review-icons
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
        .defaultScrollAnchor(screenshotAnchor)
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
            // MARK: review-icons – word joiners keep the brand whole at large text sizes ("Kli-" | "maBilanz").
            Text("Such dir aus, wie \(Self.unbreakableBrand) auf deinem Home-Bildschirm aussieht.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Such dir aus, wie KlimaBilanz auf deinem Home-Bildschirm aussieht.")
                .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
    }

    private var activeCaption: some View {
        let choice = store.current
        // MARK: review-icons – at accessibility sizes the pill goes under the text instead of squeezing it
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(choice.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
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
                // MARK: review-icons – accessibility sizes: one row per icon (icon + name + description) instead of
                // a 2-column grid whose names ("Sonnenaufgang") would break mid-word.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
                    : AnyLayout(IconCenteredGrid(minimumWidth: tileMinimum, spacing: Theme.Spacing.s, rowSpacing: Theme.Spacing.l))
                layout {
                    ForEach(AppIconChoice.allCases) { choice in
                        tile(choice)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }

    private var tileMinimum: CGFloat { max(iconSize + 30, 92) }

    private func tile(_ choice: AppIconChoice) -> some View {
        let isSelected = choice == store.current
        let ringRadius = iconSize * 0.2237 + 6  // concentric with the icon (6 pt padding)
        let isRow = dynamicTypeSize.isAccessibilitySize
        let layout = isRow
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
        return Button {
            select(choice)
        } label: {
            layout {
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
                if isRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title)
                            .font(.body.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(choice.subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(choice.title)
                        .font(.footnote.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                }
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
                // One haptic per action (MOTION.md §6): the toast plays `.error` itself.
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
        // Zoomed-in home screen: the row above is cut by the top edge, the switch sits where the search pill would.
        ZStack(alignment: .top) {
            // MARK: review-icons – both skies (and both icon variants below) stay stacked, so the sun/moon switch
            // cross-fades morning into blue hour (opacity only) instead of snapping.
            wallpaper(dark: false)
            wallpaper(dark: true)
                .opacity(scheme == .dark ? 1 : 0)
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
            .padding(.top, -30)
            .accessibilityHidden(true)
        }
        .frame(height: 266)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(alignment: .bottom) {
            schemeToggle
                .padding(.bottom, 14)
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
    private func wallpaper(dark: Bool) -> some View {
        ZStack {
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
                ZStack {
                    AppIconImage(choice: choice, size: iconSize)
                        .environment(\.colorScheme, .light)
                    AppIconImage(choice: choice, size: iconSize)
                        .environment(\.colorScheme, .dark)
                        .opacity(scheme == .dark ? 1 : 0)
                }
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
        // MARK: review-icons – the stage is a fixed-size illustration; past AX2 the switch would cover the icon's label.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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

// MARK: - Layout

/// Tiles of equal width in as many columns as fit; a shorter last row is centred (5 icons → 3 + 2, not 3 + 2 hanging
/// on the left). Dynamic Type grows `minimumWidth`, so the grid drops to two or one column on its own.
private struct IconCenteredGrid: Layout {
    var minimumWidth: CGFloat
    var spacing: CGFloat
    var rowSpacing: CGFloat

    private func metrics(width: CGFloat) -> (columns: Int, tileWidth: CGFloat) {
        let columns = max(1, Int((width + spacing) / (minimumWidth + spacing)))
        return (columns, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
    }

    private func rows(_ subviews: Subviews, columns: Int) -> [Range<Int>] {
        stride(from: 0, to: subviews.count, by: columns).map { $0..<min($0 + columns, subviews.count) }
    }

    private func height(of row: Range<Int>, in subviews: Subviews, tileWidth: CGFloat) -> CGFloat {
        row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (minimumWidth * 3 + spacing * 2)
        let (columns, tileWidth) = metrics(width: width)
        let rowRanges = rows(subviews, columns: columns)
        let total = rowRanges.reduce(0) { $0 + height(of: $1, in: subviews, tileWidth: tileWidth) }
        return CGSize(width: width, height: total + CGFloat(max(rowRanges.count - 1, 0)) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, tileWidth) = metrics(width: bounds.width)
        var y = bounds.minY
        for row in rows(subviews, columns: columns) {
            let rowHeight = height(of: row, in: subviews, tileWidth: tileWidth)
            let rowWidth = CGFloat(row.count) * tileWidth + CGFloat(row.count - 1) * spacing
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: tileWidth, height: rowHeight))
                x += tileWidth + spacing
            }
            y += rowHeight + rowSpacing
        }
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
