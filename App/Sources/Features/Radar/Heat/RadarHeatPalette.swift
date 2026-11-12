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
    private let ground: [Double]

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
        ground = rgb(Theme.background)
    }

    var isDark: Bool { scheme == .dark }

    /// The colour of a blend of the three heat colours.
    func color(_ blend: HeatBlend) -> Color {
        func mix(_ index: Int) -> Double { green[index] * blend.green + orange[index] * blend.orange + red[index] * blend.red }
        return Color(.sRGB, red: mix(0), green: mix(1), blue: mix(2), opacity: 1)
    }

    // Layers of one cell, from below: a scrim, a halo, the body. The scrim is a plain ground under the colour (white on the light map,
    // the app's night blue on the dark one): green on the map's green land and orange on its brown hills would otherwise vanish, and
    // on the dark map the cells would not glow. It reaches a little past the body, so every cell has a thin bezel. The halo is the
    // colour again, wider and faint: the soft edge. Dark maps get a stronger body (the colours are the light dark-mode variants of the
    // tokens).
    var scrim: Color { isDark ? Color(.sRGB, red: ground[0], green: ground[1], blue: ground[2], opacity: 1) : Color.white }
    var scrimOpacity: Double { isDark ? 0.58 : 0.55 }
    var haloOpacity: Double { isDark ? 0.20 : 0.16 }
    var bodyOpacity: Double { isDark ? 0.82 : 0.66 }
    var bodyLine: Double { isDark ? 1.0 : 0.9 }

    /// A cell with too few trains for a colour: grey, thin, hatched.
    var neutralFill: Color { (isDark ? Color.white : Color.black).opacity(isDark ? 0.08 : 0.05) }
    var neutralLine: Color { (isDark ? Color.white : Color.black).opacity(isDark ? 0.50 : 0.32) }
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
