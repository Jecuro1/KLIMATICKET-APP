import SwiftUI
import KlimaCore

/// Design tokens – the single source of truth for colour, type, spacing and shape (see docs/DESIGN.md).
/// Shared by the app and the widget extension.
enum Theme {
    // MARK: Brand palette – "Alpine Glass" (light / dark)

    /// Gletscherblau – primary tint.
    static let glacier = Color(light: "#2A7BD4", dark: "#7CC4FF")
    static let glacier2 = Color(light: "#63B3EE", dark: "#A9DBFF")
    /// Morgenrot – summit, break-even, ticket price.
    static let dawn = Color(light: "#F08A5B", dark: "#FFAD85")
    static let dawn2 = Color(light: "#F8B48E", dark: "#FFCDB0")
    /// Alpenglühen – rose accent.
    static let alpenglow = Color(light: "#E86C8A", dark: "#FF8FAB")
    /// Zirbe – eco, CO₂, on track, profit.
    static let pine = Color(light: "#23876A", dark: "#6BD6A9")
    /// Abenddämmerung – route middle, climber.
    static let dusk = Color(light: "#7A6FE0", dark: "#A99FFF")
    static let gold = Color(light: "#E2A93B", dark: "#F5C25B")

    // MARK: Semantic colours

    static let accent = glacier
    static let accentSecondary = dusk
    static let onAccent = Color.white
    // MARK: motion – fill behind white labels (`.glassProminent`, tinted glass buttons). `accent` is a light blue in
    // dark mode (#7CC4FF), where white text on it reads at < 2:1; this stays a deep glacier blue in both appearances.
    static let prominentTint = Color(light: "#2A7BD4", dark: "#2E78CC")

    static let background = Color(light: "#E6ECF3", dark: "#08132A")
    static let sheetBackground = Color(light: "#F1F4F8", dark: "#0D1830")
    static let surface = Color(light: Color.white.opacity(0.77), dark: Color.white.opacity(0.07))
    static let surfaceSecondary = Color(light: "#76809624", dark: "#A0AFCD29")
    static let separator = Color(light: "#0C1A2B17", dark: "#E8F1FC1A")

    static let textPrimary = Color(light: "#0C1A2B", dark: "#F3F7FC")
    static let textSecondary = Color(light: "#0C1A2B9E", dark: "#E8F1FCA8")
    static let textTertiary = Color(light: "#0C1A2B66", dark: "#E8F1FC6B")

    /// Value / savings / paid off.
    static let positive = pine
    /// Remaining to break-even.
    static let remaining = dawn
    static let negative = Color(light: "#D64545", dark: "#FF7B7B")
    /// Text-safe red (≥ 4.5:1 on cards in both appearances) for destructive links and error copy.
    static let negativeText = Color(light: "#B42318", dark: "#FF9A9A")
    static let eco = pine
    static let summit = dawn

    // Text-safe variants of the accents (≥ 4.5:1 on light backgrounds) – use these for small text.
    static let positiveText = Color(light: "#0A6B52", dark: "#6BD6A9")
    static let summitText = Color(light: "#B0501F", dark: "#FFAD85")
    static let accentText = Color(light: "#1D5FB0", dark: "#9DD3FF")

    static let celebrationColors: [Color] = [
        Color(hex: "#2A7BD4"), Color(hex: "#7A6FE0"), Color(hex: "#F08A5B"), Color(hex: "#23876A"), Color(hex: "#E2A93B"), Color(hex: "#E86C8A"),
    ]

    /// Route / progress: glacier → dusk → dawn.
    static let routeGradient = LinearGradient(
        stops: [.init(color: Color(light: "#3B8BE0", dark: "#6CB6FF"), location: 0),
                .init(color: Color(light: "#7C79E6", dark: "#A99FFF"), location: 0.55),
                .init(color: Color(light: "#F08A5B", dark: "#FFAD85"), location: 1)],
        startPoint: .leading, endPoint: .trailing)
    static let progressGradient = routeGradient
    /// Primary CTA (100°): #3A8BE4 → #5C86EA → #7F7EE8.
    static let ctaGradient = LinearGradient(colors: [Color(hex: "#3A8BE4"), Color(hex: "#5C86EA"), Color(hex: "#7F7EE8")],
                                            startPoint: .leading, endPoint: .trailing)

    // MARK: Transport modes (landscape colours; always paired with icon + label)

    // MARK: global – one Color per mode (built once): rows get equal values, so SwiftUI can skip them on re-render.
    static func modeColor(_ mode: TransportMode) -> Color { modeColors[mode] ?? makeModeColor(mode) }

    private static let modeColors: [TransportMode: Color] =
        Dictionary(uniqueKeysWithValues: TransportMode.allCases.map { ($0, makeModeColor($0)) })

    private static func makeModeColor(_ mode: TransportMode) -> Color {
        switch mode {
        case .train: Color(light: "#2F7FDA", dark: "#6CB6FF")      // Gletscher
        case .sBahn: Color(light: "#1FA9B8", dark: "#4FD3DD")      // Bergsee
        case .metro: Color(light: "#E0628A", dark: "#FF86AA")      // Alpenglühen
        case .tram: Color(light: "#8673E6", dark: "#A897FF")       // Dämmerung
        case .bus: Color(light: "#F0904F", dark: "#FFAE73")        // Morgenrot
        case .ferry: Color(light: "#2A9D8F", dark: "#5FD1C2")
        case .cableCar: Color(light: "#23876A", dark: "#6BD6A9")   // Zirbe
        case .other: Color(light: "#64748B", dark: "#94A3B8")
        }
    }

    // MARK: Achievement tiers

    // MARK: global – built once per tier (see modeColor).
    static func tierGradient(_ tier: Achievement.Tier) -> LinearGradient { tierGradients[tier] ?? makeTierGradient(tier) }

    private static let tierGradients: [Achievement.Tier: LinearGradient] =
        Dictionary(uniqueKeysWithValues: [Achievement.Tier.bronze, .silver, .gold, .platinum].map { ($0, makeTierGradient($0)) })

    private static func makeTierGradient(_ tier: Achievement.Tier) -> LinearGradient {
        let colors: [Color]
        switch tier {
        case .bronze: colors = [Color(hex: "#E7A06B"), Color(hex: "#B8672E")]
        case .silver: colors = [Color(hex: "#E2E8F0"), Color(hex: "#94A3B8")]
        case .gold: colors = [Color(hex: "#FFE08A"), Color(hex: "#E0A422")]
        case .platinum: colors = [Color(hex: "#C7D2FE"), Color(hex: "#7B5CFF")]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Typography

    enum Typography {
        static let hero = Font.system(size: 112, weight: .ultraLight, design: .rounded)
        /// Big price/validity numerals ("€ 24,90", "142").
        static let priceNumeral = Font.system(size: 46, weight: .light, design: .rounded).monospacedDigit()
        static let heroTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let numberLarge = Font.system(size: 34, weight: .bold, design: .rounded).monospacedDigit()
        static let numberMedium = Font.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()
        static let numberSmall = Font.system(size: 18, weight: .bold, design: .rounded).monospacedDigit()
        static let title = Font.title2.weight(.bold)
        static let sectionTitle = Font.system(size: 20, weight: .bold)
        static let headline = Font.headline
        static let body = Font.body
        static let caption = Font.footnote
        /// Uppercase eyebrow ("FREITAG, 9. OKTOBER"), tracking +1.06.
        static let kicker = Font.system(size: 12.5, weight: .semibold)
    }

    // MARK: Layout

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
        /// Horizontal screen margin for titles/text (cards use `cardGutter`).
        static let screen: CGFloat = 20
        static let cardGutter: CGFloat = 16
    }

    enum Radius {
        static let modeTile: CGFloat = 12
        static let chip: CGFloat = 14
        static let tile: CGFloat = 20
        static let formGroup: CGFloat = 24
        static let card: CGFloat = 28
        static let pass: CGFloat = 30
        static let sheet: CGFloat = 38
    }
}
