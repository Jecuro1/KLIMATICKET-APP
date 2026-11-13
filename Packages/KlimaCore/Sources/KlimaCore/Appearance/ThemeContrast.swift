import Foundation

// MARK: themes – WCAG 2.x contrast for the palette gates (docs/THEMES.md §3). A palette that fails a gate is not shipped.

/// An sRGB colour with 0…255 channels (fractions allowed after compositing).
public struct ThemeRGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// "#RRGGBB" (with or without "#"); nil for anything else.
    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let value = UInt32(s, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF)
        g = Double((value >> 8) & 0xFF)
        b = Double(value & 0xFF)
    }

    public static let white = ThemeRGB(r: 255, g: 255, b: 255)

    /// This colour at `alpha` over `background` (source-over in sRGB, like the renderer composites a translucent fill).
    public func composited(alpha: Double, over background: ThemeRGB) -> ThemeRGB {
        ThemeRGB(r: r * alpha + background.r * (1 - alpha),
                 g: g * alpha + background.g * (1 - alpha),
                 b: b * alpha + background.b * (1 - alpha))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            let c = channel / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

public enum ThemeContrast {
    /// Normal text (WCAG AA).
    public static let textMinimum = 4.5
    /// Large or bold text on a fill, and graphical objects such as icons and toggles (WCAG AA).
    public static let largeTextMinimum = 3.0

    /// The card surface in light appearance: `Theme.surface` (white at 77 %) over `Theme.background` (#E6ECF3).
    public static let lightCard = ThemeRGB.white.composited(alpha: 0.77, over: ThemeRGB(hex: "#E6ECF3")!)
    /// The card surface in dark appearance: white at 7 % over #08132A.
    public static let darkCard = ThemeRGB.white.composited(alpha: 0.07, over: ThemeRGB(hex: "#08132A")!)
    /// Plain backgrounds text sits on outside cards: Theme.background and Theme.sheetBackground.
    public static let lightBackgrounds = [ThemeRGB(hex: "#E6ECF3")!, ThemeRGB(hex: "#F1F4F8")!]
    public static let darkBackgrounds = [ThemeRGB(hex: "#08132A")!, ThemeRGB(hex: "#0D1830")!]

    public static func ratio(_ a: ThemeRGB, _ b: ThemeRGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// One contrast requirement of a palette.
    public struct Gate: Equatable, Sendable {
        public let palette: ThemePaletteID
        /// "accentText (hell) auf Karte"
        public let name: String
        public let ratio: Double
        public let minimum: Double
        public var passes: Bool { ratio >= minimum }
    }

    /// Every gate of `palette`: text-safe accent ≥ 4,5 : 1 on cards and backgrounds in both appearances, accent ≥ 3 : 1 on
    /// cards (icons, toggles, rings), white on prominentTint and on every CTA stop ≥ 3 : 1 (bold labels).
    public static func gates(for palette: ThemePalette) -> [Gate] {
        var gates: [Gate] = []
        func add(_ name: String, _ fg: String, _ bg: ThemeRGB, _ minimum: Double) {
            guard let color = ThemeRGB(hex: fg) else {
                gates.append(Gate(palette: palette.id, name: "\(name) (kein gültiges Hex)", ratio: 0, minimum: minimum))
                return
            }
            gates.append(Gate(palette: palette.id, name: name, ratio: ratio(color, bg), minimum: minimum))
        }
        add("accentText (hell) auf Karte", palette.accentText.light, lightCard, textMinimum)
        add("accentText (dunkel) auf Karte", palette.accentText.dark, darkCard, textMinimum)
        for (index, bg) in lightBackgrounds.enumerated() {
            add("accentText (hell) auf Hintergrund \(index + 1)", palette.accentText.light, bg, textMinimum)
        }
        for (index, bg) in darkBackgrounds.enumerated() {
            add("accentText (dunkel) auf Hintergrund \(index + 1)", palette.accentText.dark, bg, textMinimum)
        }
        add("accent (hell) auf Karte", palette.accent.light, lightCard, largeTextMinimum)
        add("accent (dunkel) auf Karte", palette.accent.dark, darkCard, largeTextMinimum)
        if let tint = ThemeRGB(hex: palette.prominentTint.light) {
            gates.append(Gate(palette: palette.id, name: "Weiß auf prominentTint (hell)", ratio: ratio(.white, tint), minimum: largeTextMinimum))
        }
        if let tint = ThemeRGB(hex: palette.prominentTint.dark) {
            gates.append(Gate(palette: palette.id, name: "Weiß auf prominentTint (dunkel)", ratio: ratio(.white, tint), minimum: largeTextMinimum))
        }
        for (index, hex) in palette.cta.enumerated() {
            guard let stop = ThemeRGB(hex: hex) else { continue }
            gates.append(Gate(palette: palette.id, name: "Weiß auf CTA-Stopp \(index + 1)", ratio: ratio(.white, stop), minimum: largeTextMinimum))
        }
        return gates
    }

    /// The palettes that pass every gate – the only ones the picker offers.
    public static var shippable: [ThemePalette] {
        ThemeCatalog.all.filter { gates(for: $0).allSatisfy(\.passes) }
    }
}
