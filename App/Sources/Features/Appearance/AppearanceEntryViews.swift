import SwiftUI
import KlimaCore

// MARK: themes – the ways into Look & Feel and the icon ↔ palette suggestions (docs/THEMES.md §8). A suggestion never switches
// anything by itself: it names the partner and offers one tap.

/// "Look & Feel" in Einstellungen › Darstellung: the palette's accent as the tile, the current choices as the subtitle.
struct AppearanceSettingsRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let prefs = app.settings.look.prefs
        NavigationLink {
            AppearanceView()
        } label: {
            SetRowLabel(title: "Look & Feel", subtitle: Self.subtitle(prefs), symbol: "paintpalette.fill",
                        tint: ThemeRuntime.colors(for: prefs.palette).accent)
        }
        .accessibilityLabel("Look & Feel")
        .accessibilityValue(Self.subtitle(prefs))
    }

    /// "Zirbe · Bewegung Ruhig · Haptik Dezent"
    static func subtitle(_ prefs: AppearancePrefs) -> String {
        "\(ThemeCatalog.palette(prefs.palette).name) · Bewegung \(prefs.motion.title) · Haptik \(prefs.haptics.title)"
    }
}

/// Look & Feel › Farbe: the App-Symbol that goes with the chosen palette.
struct AppearanceIconSuggestion: View {
    var palette: ThemePaletteID
    var tint: Color

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A row; at accessibility sizes the button goes under the name instead of squeezing it.
    private var suggestionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
    }

    var body: some View {
        let choice = AppIconChoice(rawValue: AppearancePairing.icon(for: palette).rawValue) ?? .alpin
        let store = AppIconStore.shared
        let isActive = store.current == choice
        suggestionLayout {
            AppIconImage(choice: choice, size: 44)
                .id(choice)
                .motionTransition(.pop)
            VStack(alignment: .leading, spacing: 1) {
                Text("Passendes App-Symbol")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(choice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isActive {
                SetPill(text: "Aktiv", symbol: "checkmark", tint: Theme.positiveText)
            } else {
                Button("Übernehmen") {
                    store.select(choice) { changed in
                        guard !changed else { return }
                        app.showToast("exclamationmark.triangle.fill", "App-Symbol nicht geändert", "Bitte versuch es gleich noch einmal.")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .tint(tint)
                .disabled(store.isChanging)
                .accessibilityLabel("App-Symbol \(choice.title) übernehmen")
            }
        }
        .padding(Theme.Spacing.s)
        .background(Theme.surfaceSecondary.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .motionAnimation(Motion.snappy, value: choice)
        .motionAnimation(Motion.snappy, value: isActive)
        .accessibilityElement(children: .combine)
    }
}

/// App-Symbol: the palette that goes with the chosen icon (shown when it is not the palette in use).
struct AppearanceThemeSuggestion: View {
    var icon: AppIconChoice

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A row; at accessibility sizes the button goes under the name instead of squeezing it.
    private var suggestionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
    }

    var body: some View {
        let look = app.settings.look
        let suggested = AppearancePairing.palette(for: AppearanceIconID(rawValue: icon.rawValue) ?? .alpin)
        let colors = ThemeRuntime.colors(for: suggested)
        let isActive = look.prefs.palette == suggested
        suggestionLayout {
            AppearanceSwatch(colors: colors)
                .frame(width: 64, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Theme.Radius.modeTile, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1) }
            VStack(alignment: .leading, spacing: 1) {
                Text("Passendes Theme")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(ThemeCatalog.palette(suggested).name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                if isActive && look.hasPendingChanges && app.isShowingSettings {
                    Text("Wechselt, sobald du die Einstellungen schließt.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .motionTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isActive {
                SetPill(text: "Aktiv", symbol: "checkmark", tint: Theme.positiveText)
            } else {
                Button("Übernehmen") {
                    withMotion(Motion.smooth) { look.prefs.palette = suggested }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .tint(colors.accent)
                .accessibilityLabel("Theme \(ThemeCatalog.palette(suggested).name) übernehmen")
            }
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
        .motionAnimation(Motion.snappy, value: suggested)
        .motionAnimation(Motion.snappy, value: isActive)
        .accessibilityElement(children: .combine)
    }
}
