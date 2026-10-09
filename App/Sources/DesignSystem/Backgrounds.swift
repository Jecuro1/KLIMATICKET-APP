import SwiftUI

/// Softly animated 3×3 mesh gradient behind screens (sky over the Arlberg). Static with Reduce Motion,
/// solid with Reduce Transparency, ~10 fps to stay battery friendly.
struct AmbientBackground: View {
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Theme.background
            } else if reduceMotion || LaunchMode.isScreenshot {
                mesh(t: 0.6)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { context in
                    mesh(t: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func mesh(t: Double) -> some View {
        let s = Float(sin(t / 9)) * 0.06 * Float(intensity)
        let c = Float(cos(t / 11)) * 0.05 * Float(intensity)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + s, 0], [1, 0],
                [0, 0.45 + c], [0.5 - c, 0.5 + s], [1, 0.4 - s],
                [0, 1], [0.5 + c, 1], [1, 1],
            ],
            colors: colorScheme == .dark ? AmbientBackground.darkColors : AmbientBackground.lightColors,
            smoothsColors: true
        )
        .overlay(Theme.background.opacity(colorScheme == .dark ? 0.15 : 0.1))
    }

    static let lightColors: [Color] = [
        Color(hex: "#C9D8F2"), Color(hex: "#D8DDF5"), Color(hex: "#E9DDF2"),
        Color(hex: "#DCE6F6"), Color(hex: "#EEF0F8"), Color(hex: "#F8E4D8"),
        Color(hex: "#EEF2F8"), Color(hex: "#F1F3F9"), Color(hex: "#F4EEF2"),
    ]

    static let darkColors: [Color] = [
        Color(hex: "#0B1430"), Color(hex: "#131A3D"), Color(hex: "#1D1640"),
        Color(hex: "#0A1226"), Color(hex: "#0E1530"), Color(hex: "#2A1838"),
        Color(hex: "#070B14"), Color(hex: "#080C18"), Color(hex: "#0D0B18"),
    ]
}

extension View {
    /// Places the ambient mesh background behind a scrollable screen.
    func ambientBackground(intensity: Double = 1) -> some View {
        background { AmbientBackground(intensity: intensity) }
    }
}
