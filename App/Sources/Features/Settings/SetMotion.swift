import SwiftUI

// Motion of the settings module (docs/MOTION.md) on top of the motion system: the screen header that condenses into the
// inline title, symbols that work while something runs (sync, update check, tariffs, restore) and symbols that answer
// a switch being turned on. Everything here is a render transform or a symbol effect – no layout animates, nothing
// loops off screen – and everything is off under Reduce Motion and in CI screenshots.

// MARK: - Condensing header

extension View {
    /// The large header shrinks a little towards its leading edge and fades while the list scrolls under the navigation
    /// bar (`SetInlineTitle` fades in at the same time). Reads `condense` – keep it on the small header view.
    /// Reduce Motion: fade only.
    func setHeaderCondense(_ condense: ScrollCondense?) -> some View {
        modifier(SetHeaderCondenseModifier(condense: condense))
    }
}

private struct SetHeaderCondenseModifier: ViewModifier {
    let condense: ScrollCondense?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let p = condense?.value ?? 0
        content
            .scaleEffect(reduceMotion ? 1 : 1 - 0.08 * p, anchor: .bottomLeading)
            .opacity(1 - 0.9 * Double(p))
    }
}

/// The inline navigation title: fades in over the second half of the header's scroll distance. Only this view reads
/// the scroll progress, so the list itself never re-renders while scrolling.
struct SetInlineTitle: View {
    let title: String
    let condense: ScrollCondense

    var body: some View {
        let p = condense.value
        Text(title)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .opacity(Double(min(max((p - 0.5) * 2, 0), 1)))
            .accessibilityHidden(p < 0.5)
    }
}

// MARK: - Busy symbols

/// How a row's icon shows that its work is running.
enum SetBusyStyle {
    /// Circular arrows turn (sync, update check, tariffs).
    case rotate
    /// Documents and other shapes pulse (restoring a backup).
    case pulse
}

extension View {
    /// The SF Symbol inside works while `isActive` – the row's own icon instead of a separate spinner. Finite by
    /// nature (it stops with the work). Reduce Motion and screenshots: static – `SetBusyIndicator` shows a spinner.
    func setBusySymbol(_ isActive: Bool, style: SetBusyStyle = .rotate) -> some View {
        modifier(SetBusySymbolModifier(isActive: isActive, style: style))
    }
}

private struct SetBusySymbolModifier: ViewModifier {
    let isActive: Bool
    let style: SetBusyStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let runs = isActive && !reduceMotion && !MotionPolicy.isStatic
        switch style {
        case .rotate:
            content.symbolEffect(.rotate.clockwise, options: .repeat(.continuous), isActive: runs)
        case .pulse:
            content.symbolEffect(.pulse, options: .repeat(.continuous), isActive: runs)
        }
    }
}

/// The trailing spinner of a busy row – only where its symbol cannot show the work (Reduce Motion, screenshots).
struct SetBusyIndicator: View {
    var isBusy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isBusy && (reduceMotion || MotionPolicy.isStatic) {
            ProgressView()
                .transition(.opacity)
        }
    }
}

// MARK: - Symbols that answer a switch

/// What a row's symbol does when its switch is turned on.
enum SetSwitchEffect {
    /// Hops once – "on".
    case bounce
    /// Shakes like a ringing bell or a vibrating phone (Mitteilungen, Haptik).
    case wiggle
    /// Turns once around – refresh and cycle symbols (automatic update check).
    case rotate
}

extension View {
    /// The row's SF Symbol plays `effect` once whenever `isOn` turns on – never when it turns off, never on appear.
    /// Reduce Motion and screenshots: nothing moves.
    func setSymbolOnEnable(_ isOn: Bool, _ effect: SetSwitchEffect = .bounce) -> some View {
        modifier(SetSwitchEffectModifier(isOn: isOn, effect: effect))
    }

    /// The row's SF Symbol plays `effect` once on every change of `trigger` (a value that was picked, a row that arrived).
    func setSymbolEffect<T: Equatable>(_ effect: SetSwitchEffect, trigger: T) -> some View {
        modifier(SetSymbolTriggerModifier(effect: effect, trigger: trigger))
    }
}

private struct SetSwitchEffectModifier: ViewModifier {
    let isOn: Bool
    let effect: SetSwitchEffect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plays = 0

    func body(content: Content) -> some View {
        content
            .modifier(SetSymbolTriggerModifier(effect: effect, trigger: plays))
            .onChange(of: isOn) { wasOn, nowOn in
                guard !wasOn, nowOn, !reduceMotion, !MotionPolicy.isStatic else { return }
                plays += 1
            }
    }
}

private struct SetSymbolTriggerModifier<T: Equatable>: ViewModifier {
    let effect: SetSwitchEffect
    let trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            switch effect {
            case .bounce: content.symbolEffect(.bounce, value: trigger)
            case .wiggle: content.symbolEffect(.wiggle, value: trigger)
            case .rotate: content.symbolEffect(.rotate, value: trigger)
            }
        }
        .symbolEffectsRemoved(reduceMotion || MotionPolicy.isStatic)
    }
}
