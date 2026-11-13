import Foundation

// MARK: review-themes – a palette's accent must not pass for a colour with a meaning (docs/THEMES.md §3). Gewinn (green),
// Verlust (red) and Gipfel (orange) never change; but a green, orange or rose accent next to them reads like one of them. Where
// a palette's accent sits that close, a figure the app would tint with the accent right beside such a figure (the remaining
// amount in the Übersicht verdict) stays neutral instead.

public enum ThemeMeaning {
    /// Hue distance (degrees on the colour wheel) below which two saturated colours read as the same family.
    public static let minimumHueDistance = 30.0
    /// Below this saturation a colour reads as grey and carries no hue (Graphit).
    public static let minimumSaturation = 0.25

    /// Hue in degrees (0 ..< 360) and HSV saturation (0 … 1).
    public static func hueAndSaturation(_ color: ThemeRGB) -> (hue: Double, saturation: Double) {
        let r = color.r / 255, g = color.g / 255, b = color.b / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let saturation = maxC == 0 ? 0 : delta / maxC
        guard delta > 0 else { return (0, saturation) }
        var hue: Double
        if maxC == r {
            hue = 60 * ((g - b) / delta)
        } else if maxC == g {
            hue = 60 * ((b - r) / delta) + 120
        } else {
            hue = 60 * ((r - g) / delta) + 240
        }
        if hue < 0 { hue += 360 }
        return (hue, saturation)
    }

    /// Shortest distance of two hues on the wheel (0 … 180).
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// The meaning colour `palette`'s accent (or text accent) resembles in either appearance, or nil.
    public static func echoedMeaning(_ palette: ThemePalette) -> ThemeSemanticToken? {
        let accents = [palette.accent.light, palette.accent.dark, palette.accentText.light, palette.accentText.dark]
            .compactMap(ThemeRGB.init(hex:))
            .map(hueAndSaturation)
            .filter { $0.saturation >= minimumSaturation }
        for token in ThemeSemanticToken.allCases {
            let meanings = [token.hex.light, token.hex.dark].compactMap(ThemeRGB.init(hex:)).map(hueAndSaturation)
            for accent in accents {
                if meanings.contains(where: { $0.saturation >= minimumSaturation && hueDistance($0.hue, accent.hue) < minimumHueDistance }) {
                    return token
                }
            }
        }
        return nil
    }

    /// True when the accent reads like Gewinn, Verlust, Gipfel or Echtzeit.
    public static func echoesMeaning(_ palette: ThemePalette) -> Bool {
        echoedMeaning(palette) != nil
    }
}
