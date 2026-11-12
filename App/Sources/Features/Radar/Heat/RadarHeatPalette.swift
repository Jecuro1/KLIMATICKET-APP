import SwiftUI
import KlimaCore

// MARK: radarheat – the colours of the Pünktlichkeit layer. Tokens only: green is `Theme.positive`, orange `Theme.summit`, red
// `Theme.negative` (docs/DESIGN.md §3); this file resolves them for the map's appearance and mixes them by the weights of a
// `HeatBlend`, because a map overlay has no environment of its own to resolve an adaptive colour in.

struct HeatPalette {
    let scheme: ColorScheme
    private let green: [Double]
    private let orange: [Double]
    private let red: [Double]

    init(scheme: ColorScheme) {
        self.scheme = scheme
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        func rgb(_ color: Color) -> [Double] {
            let resolved = color.resolve(in: environment)
            return [Double(resolved.red), Double(resolved.green), Double(resolved.blue)]
        }
        green = rgb(Theme.positive)
        orange = rgb(Theme.summit)
        red = rgb(Theme.negative)
    }

    var isDark: Bool { scheme == .dark }

    /// The colour of a blend of the three heat colours.
    func color(_ blend: HeatBlend) -> Color {
        func mix(_ index: Int) -> Double { green[index] * blend.green + orange[index] * blend.orange + red[index] * blend.red }
        return Color(.sRGB, red: mix(0), green: mix(1), blue: mix(2), opacity: 1)
    }

    // Layers of one cell: a wide faint glow, a halo, the body. Dark maps get a stronger glow (the colours are the light dark-mode
    // variants of the tokens and shine on the dark map); light maps keep the body a little more open so the map stays readable.
    var glowOpacity: Double { isDark ? 0.14 : 0.10 }
    var haloOpacity: Double { isDark ? 0.26 : 0.20 }
    var bodyOpacity: Double { isDark ? 0.62 : 0.50 }
    var bodyLine: Double { isDark ? 0.95 : 0.80 }

    /// A cell with too few trains for a colour: grey, thin, hatched.
    var neutralFill: Color { (isDark ? Color.white : Color.black).opacity(isDark ? 0.06 : 0.05) }
    var neutralLine: Color { (isDark ? Color.white : Color.black).opacity(isDark ? 0.34 : 0.30) }
}

extension HeatBucket {
    /// The colour of a bucket in the bar, the legend and the dots: green, orange, red; cancelled violet (never red: red already
    /// means "more than 15 minutes"), without realtime grey.
    var tint: Color {
        switch self {
        case .onTime: Theme.positive
        case .delayed: Theme.summit
        case .severe: Theme.negative
        case .cancelled: Theme.dusk
        case .noRealtime: Theme.textTertiary
        }
    }

    /// The same for text (≥ 4.5:1 on cards).
    var textTint: Color {
        switch self {
        case .onTime: Theme.positiveText
        case .delayed: Theme.summitText
        case .severe: Theme.negativeText
        case .cancelled: Theme.textPrimary
        case .noRealtime: Theme.textSecondary
        }
    }
}
