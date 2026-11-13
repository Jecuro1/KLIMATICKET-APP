import SwiftUI
import KlimaCore

/// Einstellungen › Darstellung › Look & Feel (docs/THEMES.md): Farbe (six palettes, contrast-tested), Bewegung, Haptik and
/// Zahlen, with a live preview on top that shows every choice before it reaches the app. Haptik works at once; Farbe,
/// Bewegung and Zahlen switch when Einstellungen closes (one cross-fade, `AppearanceSwitchHost`).
/// Motion (docs/MOTION.md): the blocks reveal once in reading order, the selection ring glides, a palette change cross-fades
/// the preview with a one-shot glow, a week-start change slides Sunday across, a Bewegung change replays the preview's hero
/// in that level. Reduce Motion turns all of it into cross-fades, screenshots show the end state. Nothing loops.
struct AppearanceView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// CI screenshot scenes open scrolled to a section.
    var screenshotSection: AppearanceSection? = nil

    /// nil = follow the app's colour scheme.
    @State private var previewScheme: ColorScheme?
    @State private var showsNavigationTitle = false
    /// Bumped on every palette change: the preview's glow.
    @State private var paletteTick = 0
    /// Bumped on every Bewegung change: the preview's hero shows that level once.
    @State private var motionReplay = 0

    private static let unbreakableBrand = "KlimaBilanz".map(String.init).joined(separator: "\u{2060}")

    private var look: AppearanceStore { app.settings.look }

    var body: some View {
        @Bindable var look = app.settings.look
        let draft = ThemeRuntime.colors(for: look.prefs.palette)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                        .reveal(order: 0)
                    AppearanceStage(prefs: look.prefs, scheme: previewScheme ?? colorScheme, glow: paletteTick,
                                    replay: motionReplay, schemeSelection: schemeBinding)
                        .padding(.horizontal, Theme.Spacing.cardGutter)
                        .reveal(order: 1)
                    if look.hasPendingChanges && app.isShowingSettings {
                        pendingNote(draft)
                            .padding(.horizontal, Theme.Spacing.cardGutter)
                            .motionTransition(.rise)
                    }
                    card("Farbe", order: 2) {
                        Text("Für Knöpfe, Schalter, Links, Routen und Fortschritt. Grün, Rot und Orange behalten ihre Bedeutung.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        AppearancePaletteGrid(selection: $look.prefs.palette, onSelect: selectPalette)
                        if AppIconStore.shared.isSupported {
                            AppearanceIconSuggestion(palette: look.prefs.palette, tint: draft.accent)
                        }
                    }
                    .id(AppearanceSection.palettes)
                    card("Bewegung", order: 3) {
                        AppearanceChoice(selection: $look.prefs.motion, options: MotionLevel.allCases, tint: draft.accent,
                                         title: \.title, feedback: { _ in Haptic.selection.feedback(at: look.hapticLevel) },
                                         accessibilityName: "Bewegung")
                        detail(look.prefs.motion.detail)
                        if reduceMotion {
                            notice("figure.walk.motion",
                                   "„Bewegung reduzieren“ ist in iOS an. Das gilt immer – auch bei „Voll“ gibt es nur sanfte Überblendungen.")
                        }
                    }
                    .id(AppearanceSection.motion)
                    card("Haptik", order: 4) {
                        // The choice plays its own level once (a snap) – the one haptic of this action.
                        AppearanceChoice(selection: $look.prefs.haptics, options: HapticLevel.allCases, tint: draft.accent,
                                         title: \.title, feedback: { Haptic.snap.feedback(at: $0) },
                                         accessibilityName: "Haptik")
                        detail(look.prefs.haptics.detail)
                    }
                    .id(AppearanceSection.haptics)
                    card("Zahlen", order: 5) {
                        numberOption("Beträge", example: AppearanceFormat.example(look.prefs.format.amounts)) {
                            AppearanceChoice(selection: $look.prefs.format.amounts, options: FormatPrefs.Amounts.allCases,
                                             tint: draft.accent, title: \.title, feedback: selectionTick(),
                                             accessibilityName: "Beträge")
                        }
                        numberOption("Woche beginnt am", example: AppearanceFormat.example(look.prefs.format.weekStart)) {
                            AppearanceChoice(selection: $look.prefs.format.weekStart, options: FormatPrefs.WeekStart.allCases,
                                             tint: draft.accent, title: \.title, feedback: selectionTick(),
                                             accessibilityName: "Woche beginnt am")
                        }
                        numberOption("CO₂", example: AppearanceFormat.example(look.prefs.format.co2)) {
                            AppearanceChoice(selection: $look.prefs.format.co2, options: FormatPrefs.CO2Unit.allCases,
                                             tint: draft.accent, title: \.title, feedback: selectionTick(),
                                             accessibilityName: "CO₂")
                        }
                        detail("Gilt überall, wo die App die Genauigkeit selbst wählt – etwa beim Ticketpreis und bei Durchschnitten. Gerundete Kennzahlen wie die große Ersparnis bleiben ganze Euro, Fahrtpreise und Tarife bleiben auf den Cent.")
                    }
                    .id(AppearanceSection.numbers)
                    notes
                        .reveal(.fade, order: 6)
                    if Self.visible(look.prefs) != Self.visible(.standard) {
                        resetButton
                            .frame(maxWidth: .infinity)
                            .motionTransition(.opacity)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
                .motionAnimation(Motion.smooth, value: look.hasPendingChanges)
            }
            .scrollIndicators(.hidden)
            .task {
                guard let screenshotSection, LaunchMode.isScreenshot else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(screenshotSection, anchor: .top)
            }
        }
        .revealScope()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 64
        } action: { _, isPastHeader in
            withMotion(Motion.crossfade) { showsNavigationTitle = isPastHeader }
        }
        .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.45) }
        .navigationTitle("Look & Feel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Look & Feel")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .opacity(showsNavigationTitle ? 1 : 0)
                    .accessibilityHidden(!showsNavigationTitle)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onChange(of: look.prefs.motion) { _, _ in motionReplay += 1 }
    }

    private var schemeBinding: Binding<ColorScheme> {
        Binding(get: { previewScheme ?? colorScheme }, set: { previewScheme = $0 })
    }

    /// A selection tick at the chosen Haptik level (Dezent and Aus: none).
    private func selectionTick<Value>() -> (Value) -> SensoryFeedback? {
        let level = look.hapticLevel
        return { _ in Haptic.selection.feedback(at: level) }
    }

    private func selectPalette(_ id: ThemePaletteID) {
        guard id != look.prefs.palette else { return }
        withMotion(Motion.smooth) {
            look.prefs.palette = id
            paletteTick += 1
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Kicker(text: "Darstellung")
            Text("Look & Feel")
                .font(Theme.Typography.heroTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Farbe, Bewegung, Haptik und Zahlen – so fühlt sich \(Self.unbreakableBrand) für dich an.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Farbe, Bewegung, Haptik und Zahlen – so fühlt sich KlimaBilanz für dich an.")
                .padding(.top, Theme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
    }

    private func pendingNote(_ draft: ThemeColorSet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: "sparkles")
                .foregroundStyle(draft.accentText)
                .accessibilityHidden(true)
            Text("Farbe, Bewegung und Zahlen wechseln, sobald du die Einstellungen schließt.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(draft.accent.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, order: Int, @ViewBuilder content: () -> Content) -> some View {
        SurfaceCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: title)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .reveal(order: order)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .motionAnimation(Motion.crossfade, value: text)
    }

    private func notice(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    private func numberOption<Control: View>(_ title: String, example: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            control()
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                Text("Beispiel")
                    .foregroundStyle(Theme.textSecondary)
                Text(example)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .motionAnimation(Motion.snappy, value: example)
            }
            .font(.footnote.weight(.medium))
            .accessibilityElement(children: .combine)
        }
        .padding(.bottom, Theme.Spacing.xxs)
    }

    // MARK: Notes & reset

    private var notes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            notice("paintpalette", "Grün heißt Gewinn und CO₂, Rot Verlust, Orange Gipfel – in jedem Theme gleich.")
            notice("checkmark.seal", "Jede Palette ist auf Lesbarkeit geprüft: Text in der Akzentfarbe mindestens 4,5 : 1, weiße Schrift auf Knöpfen mindestens 3 : 1 – hell und dunkel.")
            notice("square.grid.2x2", "Widgets übernehmen die Farbe, wenn iOS sie das nächste Mal neu zeichnet.")
        }
        .padding(.horizontal, Theme.Spacing.screen)
    }

    private var resetButton: some View {
        Button {
            withMotion(Motion.smooth) {
                var standard = AppearancePrefs.standard
                standard.haptics = look.prefs.haptics   // Haptik is its own choice
                if standard.palette != look.prefs.palette { paletteTick += 1 }
                look.prefs = standard
            }
        } label: {
            Label("Farbe, Bewegung und Zahlen zurücksetzen", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.xs)
        }
        .buttonStyle(.glass)
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }

    /// Haptik aside – what the reset button resets.
    private static func visible(_ prefs: AppearancePrefs) -> AppearancePrefs {
        var copy = prefs
        copy.haptics = .full
        return copy
    }
}

/// Sections the CI screenshots scroll to.
enum AppearanceSection: Hashable {
    case palettes, motion, haptics, numbers
}
