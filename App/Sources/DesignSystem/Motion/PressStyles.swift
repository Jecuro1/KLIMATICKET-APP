import SwiftUI

/// Direct-manipulation feedback for anything tappable (docs/MOTION.md §7): the label dips under the finger with
/// `Motion.press` and springs back with `Motion.release`. Scale and opacity only (no layout), so it stays at 120 Hz
/// inside scrolling lists. Reduce Motion: a slight dim, no scaling.
///
///     Button { … } label: { FavoriteChipLabel(…) }.buttonStyle(.pressable)
///     NavigationLink(value: trip) { TripRow(trip: trip) }.buttonStyle(.pressableCard)
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = Motion.Distance.pressScale
    /// Light impact when the finger comes down – for primary actions, not for every row.
    var hapticOnPress = false

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, scale: scale, hapticOnPress: hapticOnPress)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Buttons, chips, icon buttons (dips to 95 %).
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Cards and rows – large surfaces move less (98 %).
    static var pressableCard: PressableButtonStyle { PressableButtonStyle(scale: Motion.Distance.pressScaleCard) }
    /// Custom depth and an optional press haptic.
    static func pressable(scale: CGFloat, haptic: Bool = false) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale, hapticOnPress: haptic)
    }
}

private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let hapticOnPress: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .contentShape(.rect)
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .opacity(pressed ? 0.86 : (isEnabled ? 1 : 0.45))
            .animation(MotionPolicy.isStatic ? nil : (pressed ? Motion.press : Motion.release), value: pressed)
            .if(hapticOnPress) { $0.haptic(.tap, trigger: pressed, when: { _, isDown in isDown }) }
    }
}
