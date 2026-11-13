import SwiftUI
import KlimaCore

// MARK: themes – the colours of one Look & Feel palette, built once (docs/THEMES.md §2). The hex values live in KlimaCore
// (`ThemeCatalog`), where the contrast gates test them; this file only turns them into SwiftUI colours and gradients.

/// The themable tokens of one palette as ready-made SwiftUI values. Built once per palette and then handed out as the same
/// instances: two reads of `Theme.accent` compare equal, so rows that take a colour do not re-render for nothing. A class, so a
/// token read hands out one reference instead of copying the whole set; immutable after `init`.
final class ThemeColorSet: @unchecked Sendable {
    let palette: ThemePaletteID
    /// `Theme.accent`: tint of buttons, links, toggles, rings (large shapes and icons).
    let accent: Color
    /// `Theme.accentText`: text-safe accent for small text.
    let accentText: Color
    /// `Theme.prominentTint`: fill behind white labels.
    let prominentTint: Color
    /// `Theme.routeGradient` / `Theme.progressGradient`.
    let routeGradient: LinearGradient
    /// `Theme.ctaGradient`.
    let ctaGradient: LinearGradient
    /// The stops of both gradients, for the palette previews in Look & Feel.
    let routeColors: [Color]
    let ctaColors: [Color]
    /// The route stops resolved for one appearance (charts that draw both modes themselves, e.g. the summit chart).
    let routeLight: [Color]
    let routeDark: [Color]
    /// MARK: review-themes – a figure tinted with the accent right beside Gewinn / Verlust / Gipfel figures (the remaining
    /// amount in the Übersicht verdict): `accentText`, or `Theme.textPrimary` when the accent looks like one of those colours
    /// (KlimaCore `ThemeMeaning`: Zirbe, Morgenrot, Alpenglühen), so „Noch € 356“ never reads as a gain or a loss.
    let besideMeaningText: Color
    /// MARK: review-themes – `accentText` of the dark appearance whatever the scheme (the black Dynamic Island).
    let accentTextOnDark: Color

    init(_ palette: ThemePalette) {
        self.palette = palette.id
        if palette.id == .gletscher {
            // Gletscher is the look before themes: the very same `glacier` instance and the gradient built as it was.
            accent = Theme.glacier
        } else {
            accent = Color(light: palette.accent.light, dark: palette.accent.dark)
        }
        let text = Color(light: palette.accentText.light, dark: palette.accentText.dark)
        accentText = text
        prominentTint = Color(light: palette.prominentTint.light, dark: palette.prominentTint.dark)
        besideMeaningText = ThemeMeaning.echoesMeaning(palette) ? Theme.textPrimary : text   // MARK: review-themes
        accentTextOnDark = Color(hex: palette.accentText.dark)   // MARK: review-themes
        let route = palette.route.map { Color(light: $0.light, dark: $0.dark) }
        routeColors = route
        routeLight = palette.route.map { Color(hex: $0.light) }
        routeDark = palette.route.map { Color(hex: $0.dark) }
        routeGradient = LinearGradient(
            stops: zip(route, ThemePalette.routeLocations).map { Gradient.Stop(color: $0.0, location: CGFloat($0.1)) },
            startPoint: .leading, endPoint: .trailing)
        let cta = palette.cta.map { Color(hex: $0) }
        ctaColors = cta
        ctaGradient = LinearGradient(colors: cta, startPoint: .leading, endPoint: .trailing)
    }
}
