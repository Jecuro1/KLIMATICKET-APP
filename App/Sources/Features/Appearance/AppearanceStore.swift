import SwiftUI
import WidgetKit
import KlimaCore

// MARK: themes – Look & Feel: what you chose (theme.v1 in the App Group, docs/THEMES.md §7) and what the screens show.
//
// The choice is stored at once. Haptik works at once too (you feel the level you tap). Farbe, Bewegung and Zahlen reach the
// screens when the Settings sheet closes: `applyPending()` switches the runtimes and bumps `revision`, and RootView gives the
// tab interface that id, so every screen is built again with the new values under one cross-fade (no half-switched screen).

@Observable
@MainActor
final class AppearanceStore {
    /// What Look & Feel shows and stores.
    var prefs: AppearancePrefs {
        didSet {
            guard prefs != oldValue else { return }
            save()
        }
    }

    /// What the screens use right now. Differs from `prefs` while Einstellungen is open.
    private(set) var applied: AppearancePrefs

    /// Bumped whenever palette, motion or numbers on screen change (RootView re-identifies the tab interface).
    private(set) var revision = 0

    /// Where theme.v1 is written; nil for screenshot and perf runs (nothing is stored).
    @ObservationIgnored private let defaults: UserDefaults?

    /// `defaults`: the App Group defaults (or nil: not stored). `legacyHapticsEnabled`: the old switch „Haptisches Feedback“,
    /// carried over the first time. `forcedPalette`: `-KBTheme` / a screenshot scene (applied, never stored).
    init(defaults: UserDefaults?, legacyHapticsEnabled: Bool?, forcedPalette: ThemePaletteID? = AppearanceLaunch.forcedPalette) {
        self.defaults = defaults
        var prefs = AppearancePrefs.load(defaults?.data(forKey: AppearancePrefs.storageKey), legacyHapticsEnabled: legacyHapticsEnabled)
        if let forcedPalette { prefs.palette = forcedPalette }
        self.prefs = prefs
        applied = prefs
        Self.activate(prefs)
    }

    /// The level every haptic plays at.
    var hapticLevel: HapticLevel { prefs.haptics }

    /// Farbe, Bewegung or Zahlen differ from what the screens show (they switch when Einstellungen closes).
    var hasPendingChanges: Bool { Self.visible(prefs) != Self.visible(applied) }

    /// Switches the screens to the stored choice. Returns whether anything visible changed (then `revision` moved).
    @discardableResult
    func applyPending() -> Bool {
        let paletteChanged = applied.palette != prefs.palette
        guard hasPendingChanges else {
            applied = prefs
            return false
        }
        applied = prefs
        Self.activate(prefs)
        revision &+= 1
        // Widgets read the palette from theme.v1 when they draw: ask for a redraw (iOS decides when; docs/THEMES.md §7).
        if paletteChanged, defaults != nil { WidgetCenter.shared.reloadAllTimelines() }
        return true
    }

    private static func activate(_ prefs: AppearancePrefs) {
        ThemeRuntime.activate(prefs.palette)
        AppearanceRuntime.apply(prefs)
    }

    /// What a screen shows (haptics are felt, not seen).
    private static func visible(_ prefs: AppearancePrefs) -> AppearancePrefs {
        var copy = prefs
        copy.haptics = .full
        return copy
    }

    private func save() {
        defaults?.set(prefs.encoded(), forKey: AppearancePrefs.storageKey)
    }
}

/// Launch arguments of Look & Feel (CI and perf runs).
enum AppearanceLaunch {
    /// `-KBTheme zirbe`, or the palette a screenshot scene is about (`themeDash` → Zirbe, …). Applied, never stored.
    static var forcedPalette: ThemePaletteID? {
        if let raw = UserDefaults.standard.string(forKey: "KBTheme"), let id = ThemePaletteID(rawValue: raw) { return id }
        return LaunchMode.screenshotScreen.flatMap(screenshotPalette(for:))
    }

    /// The capture script passes no extra arguments per scene, so each theme scene names its palette here.
    static func screenshotPalette(for screen: String) -> ThemePaletteID? {
        switch screen {
        case "themeDash": .zirbe
        case "themeStats": .morgenrot
        case "themeTicket": .daemmerung
        case "themeTrips": .alpengluehen
        case "themeSettingsGraphit": .graphit
        default: nil
        }
    }
}
