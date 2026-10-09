import SwiftUI
import KlimaCore

/// Design tokens – the single source of truth for colour, type, spacing and shape (see docs/DESIGN.md).
/// Shared by the app and the widget extension.
enum Theme {
    // MARK: Brand & semantic colours (adaptive light/dark)

    static let accent = Color(light: "#2F6BFF", dark: "#7AA2FF")
    static let accentSecondary = Color(light: "#7B5CFF", dark: "#A78BFF")
    static let onAccent = Color.white

    static let background = Color(light: "#EEF2F8", dark: "#070B14")
    static let surface = Color(light: "#FFFFFF", dark: "#111827")
    static let surfaceSecondary = Color(light: "#F4F6FA", dark: "#182133")
    static let separator = Color(light: "#0B1220", dark: "#FFFFFF").opacity(0.08)

    static let textPrimary = Color(light: "#0B1220", dark: "#F4F7FB")
    static let textSecondary = Color(light: "#4A5568", dark: "#A9B4C6")
    static let textTertiary = Color(light: "#8A94A6", dark: "#6B778C")

    /// Value / savings / paid off.
    static let positive = Color(light: "#12A37F", dark: "#3DDBA8")
    /// Remaining to break-even, warnings.
    static let remaining = Color(light: "#F08A4B", dark: "#FFA36B")
    static let negative = Color(light: "#E5484D", dark: "#FF6B6F")
    static let eco = Color(light: "#22A55B", dark: "#4ADE80")
    static let summit = Color(light: "#F08A4B", dark: "#FFA36B")

    static let celebrationColors: [Color] = [
        Color(hex: "#2F6BFF"), Color(hex: "#7B5CFF"), Color(hex: "#3DDBA8"), Color(hex: "#FFA36B"), Color(hex: "#FFD166"),
    ]

    /// Progress gradient for amortisation visuals.
    static let progressGradient = LinearGradient(colors: [Color(hex: "#3B82F6"), Color(hex: "#7B5CFF")],
                                                 startPoint: .leading, endPoint: .trailing)

    // MARK: Transport modes

    static func modeColor(_ mode: TransportMode) -> Color {
        switch mode {
        case .train: Color(light: "#2F6BFF", dark: "#6E96FF")
        case .sBahn: Color(light: "#0EA5E9", dark: "#38BDF8")
        case .metro: Color(light: "#E5484D", dark: "#FF6B6F")
        case .tram: Color(light: "#D9467C", dark: "#F472B6")
        case .bus: Color(light: "#F08A4B", dark: "#FFA36B")
        case .ferry: Color(light: "#0D9488", dark: "#2DD4BF")
        case .cableCar: Color(light: "#7B5CFF", dark: "#A78BFF")
        case .other: Color(light: "#64748B", dark: "#94A3B8")
        }
    }

    // MARK: Achievement tiers

    static func tierGradient(_ tier: Achievement.Tier) -> LinearGradient {
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
        static let hero = Font.system(size: 96, weight: .thin, design: .rounded)
        static let heroTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let numberLarge = Font.system(size: 34, weight: .bold, design: .rounded).monospacedDigit()
        static let numberMedium = Font.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()
        static let numberSmall = Font.system(.headline, design: .rounded).monospacedDigit()
        static let title = Font.title2.weight(.bold)
        static let sectionTitle = Font.title3.weight(.bold)
        static let headline = Font.headline
        static let body = Font.body
        static let caption = Font.footnote
        /// Uppercase kicker ("FREITAG, 9. OKTOBER").
        static let kicker = Font.caption.weight(.semibold)
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
        /// Horizontal screen margin.
        static let screen: CGFloat = 20
    }

    enum Radius {
        static let chip: CGFloat = 14
        static let tile: CGFloat = 20
        static let card: CGFloat = 28
        static let sheet: CGFloat = 36
    }
}
