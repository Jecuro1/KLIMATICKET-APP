import Foundation
import SwiftUI

/// Which medals the Gipfelbuch has already shown as earned, per ticket year – so a medal earned since the last visit
/// gets its unlock moment (shine, pop, ring, "Neu") exactly once. A per-device UI memory like the map look
/// (`atlas.mapLook`), not user data: losing it only means one moment is skipped or repeated.
enum AchUnlockMemory {
    private static func key(_ ticketYear: String) -> String { "gipfelbuch.shownUnlocked.\(ticketYear)" }

    /// The medals unlocked since the last visit, and remembers the current set. The very first visit of a ticket year
    /// only remembers (no celebration flood for an existing collection). Never in screenshot or performance runs.
    static func takeFresh(unlocked: [String], ticketYear: String, defaults: UserDefaults = .standard) -> Set<String> {
        guard !LaunchMode.isSandboxed, !ticketYear.isEmpty else { return [] }
        let current = Set(unlocked)
        let stored = defaults.stringArray(forKey: key(ticketYear))
        if stored.map(Set.init) != current {
            defaults.set(current.sorted(), forKey: key(ticketYear))
        }
        guard let stored else { return [] }
        return current.subtracting(stored)
    }
}

/// A band of light sweeps once across a medal's face whenever `trigger` changes (a medal just earned, the detail
/// opening on an earned medal). Additive light clipped to the coin, ~0,7 s; no band (and no blend layer) while idle.
/// Reduce Motion / screenshots: nothing.
struct AchShineSweep: View {
    let trigger: Int
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The animator sits on a clear base (a keyframe animator only plays on a *change* of its trigger, so it must
        // exist before the first one); the band and its blend layer exist only while it sweeps – nothing composites
        // over the 6–17 medals of the grid while they scroll.
        if !reduceMotion && !MotionPolicy.isStatic {
            let size = size
            Color.clear
                .keyframeAnimator(initialValue: -1.0, trigger: trigger) { base, x in
                    base.overlay {
                        if x > -0.98 && x < 0.98 {
                            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                   .init(color: .white.opacity(0.75), location: 0.5),
                                                   .init(color: .white.opacity(0), location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: size * 0.34, height: size * 1.5)
                                .rotationEffect(.degrees(22))
                                .offset(x: x * size * 0.85)
                                .blendMode(.plusLighter)
                        }
                    }
                } keyframes: { _ in
                    LinearKeyframe(-1.0, duration: 0.01)
                    CubicKeyframe(1.0, duration: 0.7)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
