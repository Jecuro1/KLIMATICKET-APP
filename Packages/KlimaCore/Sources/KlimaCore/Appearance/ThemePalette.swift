import Foundation

// MARK: themes – the six colour palettes of Einstellungen › Darstellung › Look & Feel (docs/THEMES.md).
// Pure data: the app turns these hex values into colours once (Shared/ThemePalettes.swift); the tests in
// Tests/KlimaCoreTests/Appearance gate every palette on contrast before it can ship.

/// One colour in light and dark appearance, as sRGB hex ("#RRGGBB").
public struct ThemeHexPair: Equatable, Hashable, Sendable {
    public let light: String
    public let dark: String

    public init(_ light: String, _ dark: String) {
        self.light = light
        self.dark = dark
    }

    public func value(dark isDark: Bool) -> String { isDark ? dark : light }
}

/// The palettes, in the order the picker shows them. The raw values are stored (theme.v1) – never rename one.
public enum ThemePaletteID: String, CaseIterable, Codable, Sendable, Identifiable {
    case gletscher, zirbe, morgenrot, daemmerung, alpengluehen, graphit

    public var id: String { rawValue }

    /// Today's look: every value of Gletscher is the value the app had before themes existed.
    public static let standard: ThemePaletteID = .gletscher
}

/// The tokens a palette changes. Everything else in Theme.swift – above all the colours that carry a meaning
/// (`ThemeSemanticToken`) – stays the same in every palette.
public enum ThemeToken: String, CaseIterable, Sendable {
    /// Tint of buttons, links, toggles, selection rings (large shapes and icons; small text uses `accentText`).
    case accent
    /// Text-safe accent (≥ 4,5 : 1 on cards in both appearances).
    case accentText
    /// Fill behind white labels (`.glassProminent`, tinted glass buttons): white on it reads ≥ 3 : 1.
    case prominentTint
    /// Route / progress gradient: start, middle (55 %), end.
    case routeStart, routeMiddle, routeEnd
    /// Primary call to action (white bold label on it): leading, middle, trailing. Same in both appearances.
    case ctaLeading, ctaMiddle, ctaTrailing
}

/// Colours with a meaning: they never change with a palette, so green stays „Gewinn“, red „Verlust“, orange „Gipfel“
/// and the live green „Echtzeit“. Values mirror Shared/Theme.swift (a test reads that file and compares).
public enum ThemeSemanticToken: String, CaseIterable, Sendable {
    case positive, positiveText, negative, negativeText, summit, summitText, live

    public var hex: ThemeHexPair {
        switch self {
        case .positive: ThemeHexPair("#23876A", "#6BD6A9")
        case .positiveText: ThemeHexPair("#0A6B52", "#6BD6A9")
        case .negative: ThemeHexPair("#D64545", "#FF7B7B")
        case .negativeText: ThemeHexPair("#B42318", "#FF9A9A")
        case .summit: ThemeHexPair("#F08A5B", "#FFAD85")
        case .summitText: ThemeHexPair("#B0501F", "#FFAD85")
        case .live: ThemeHexPair("#0B7A4E", "#5BE0A0")
        }
    }

    /// The Theme.swift property that holds this colour.
    public var themeProperty: String {
        switch self {
        case .positive: "pine"   // Theme.positive = pine
        case .summit: "dawn"     // Theme.summit = dawn
        default: rawValue
        }
    }
}

/// A palette: name, a one-line description, and a value for every `ThemeToken`.
public struct ThemePalette: Equatable, Sendable, Identifiable {
    public let id: ThemePaletteID
    /// "Zirbe"
    public let name: String
    /// "Waldgrün mit Lärchengold"
    public let tagline: String
    public let accent: ThemeHexPair
    public let accentText: ThemeHexPair
    public let prominentTint: ThemeHexPair
    /// Start, middle, end of the route / progress gradient (at `routeLocations`).
    public let route: [ThemeHexPair]
    /// Leading, middle, trailing of the CTA gradient – one value for both appearances, like before themes.
    public let cta: [String]

    /// Stop locations of the route gradient (glacier → dusk at 55 % → dawn in Gletscher).
    public static let routeLocations: [Double] = [0, 0.55, 1]

    public init(id: ThemePaletteID, name: String, tagline: String, accent: ThemeHexPair, accentText: ThemeHexPair,
                prominentTint: ThemeHexPair, route: [ThemeHexPair], cta: [String]) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.accent = accent
        self.accentText = accentText
        self.prominentTint = prominentTint
        self.route = route
        self.cta = cta
    }

    /// The value of `token` in this palette (light and dark).
    public func hex(_ token: ThemeToken) -> ThemeHexPair? {
        switch token {
        case .accent: accent
        case .accentText: accentText
        case .prominentTint: prominentTint
        case .routeStart: route.indices.contains(0) ? route[0] : nil
        case .routeMiddle: route.indices.contains(1) ? route[1] : nil
        case .routeEnd: route.indices.contains(2) ? route[2] : nil
        case .ctaLeading: cta.indices.contains(0) ? ThemeHexPair(cta[0], cta[0]) : nil
        case .ctaMiddle: cta.indices.contains(1) ? ThemeHexPair(cta[1], cta[1]) : nil
        case .ctaTrailing: cta.indices.contains(2) ? ThemeHexPair(cta[2], cta[2]) : nil
        }
    }
}

/// Every palette, in picker order.
public enum ThemeCatalog {
    public static let all: [ThemePalette] = ThemePaletteID.allCases.map(palette)

    public static func palette(_ id: ThemePaletteID) -> ThemePalette {
        switch id {
        case .gletscher:
            // Exactly the values of Theme.swift before themes (glacier, accentText, prominentTint, routeGradient, ctaGradient).
            ThemePalette(id: id, name: "Gletscher", tagline: "Klares Eis – das Original",
                         accent: ThemeHexPair("#2A7BD4", "#7CC4FF"),
                         accentText: ThemeHexPair("#1D5FB0", "#9DD3FF"),
                         prominentTint: ThemeHexPair("#2A7BD4", "#2E78CC"),
                         route: [ThemeHexPair("#3B8BE0", "#6CB6FF"), ThemeHexPair("#7C79E6", "#A99FFF"), ThemeHexPair("#F08A5B", "#FFAD85")],
                         cta: ["#3A8BE4", "#5C86EA", "#7F7EE8"])
        case .zirbe:
            ThemePalette(id: id, name: "Zirbe", tagline: "Waldgrün, Bergsee und Lärchengold",
                         accent: ThemeHexPair("#24804F", "#6FD39A"),
                         accentText: ThemeHexPair("#196B40", "#8FE0B2"),
                         prominentTint: ThemeHexPair("#21784A", "#237A4C"),
                         route: [ThemeHexPair("#2E9A63", "#5FD39A"), ThemeHexPair("#1F8A8A", "#5CC9C4"), ThemeHexPair("#E2A93B", "#F5C25B")],
                         cta: ["#2B8C57", "#22827A", "#2F7699"])
        case .morgenrot:
            ThemePalette(id: id, name: "Morgenrot", tagline: "Warmes Licht über dem Grat",
                         accent: ThemeHexPair("#CC5A1E", "#FFA772"),
                         accentText: ThemeHexPair("#A8461A", "#FFB98F"),
                         prominentTint: ThemeHexPair("#C2541C", "#B9531F"),
                         route: [ThemeHexPair("#E8A23A", "#F8C266"), ThemeHexPair("#EE7F4F", "#FF9F78"), ThemeHexPair("#D9567A", "#FF8FAB")],
                         cta: ["#D9662A", "#D9573F", "#C94A62"])
        case .daemmerung:
            ThemePalette(id: id, name: "Dämmerung", tagline: "Blaue Stunde in Violett",
                         accent: ThemeHexPair("#6B5FD9", "#A99FFF"),
                         accentText: ThemeHexPair("#5446C2", "#C2BAFF"),
                         prominentTint: ThemeHexPair("#5E52D1", "#5B4FCC"),
                         route: [ThemeHexPair("#5C7CF0", "#8FA8FF"), ThemeHexPair("#8E6FE0", "#B59CFF"), ThemeHexPair("#E8749A", "#FF9DB8")],
                         cta: ["#5E6FEA", "#7464E0", "#8D5BD6"])
        case .alpengluehen:
            ThemePalette(id: id, name: "Alpenglühen", tagline: "Rosé, wenn die Gipfel glühen",
                         accent: ThemeHexPair("#CF4F79", "#FF8FAB"),
                         accentText: ThemeHexPair("#B23A63", "#FFADC2"),
                         prominentTint: ThemeHexPair("#C4436E", "#B8416A"),
                         route: [ThemeHexPair("#F08A5B", "#FFAD85"), ThemeHexPair("#E8678A", "#FF8FAB"), ThemeHexPair("#9A6FE0", "#B9A0FF")],
                         cta: ["#E0607A", "#CF4F79", "#B04A9A"])
        case .graphit:
            ThemePalette(id: id, name: "Graphit", tagline: "Ruhiges Schiefergrau",
                         accent: ThemeHexPair("#4A5A72", "#B8C4D6"),
                         accentText: ThemeHexPair("#3B4A60", "#CBD5E3"),
                         prominentTint: ThemeHexPair("#475569", "#475569"),
                         route: [ThemeHexPair("#8796AE", "#7D8BA3"), ThemeHexPair("#5A6880", "#A9B5C8"), ThemeHexPair("#2C3648", "#E2E8F0")],
                         cta: ["#4E5D75", "#435167", "#38455A"])
        }
    }
}
