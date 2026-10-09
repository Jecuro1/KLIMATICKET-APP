import SwiftUI
import CoreMotion

/// Device tilt for holographic / parallax effects (ticket card sheen). Smoothed, ~30 Hz, stops when unused.
@Observable
@MainActor
final class MotionTilt {
    /// −1 … 1 (left/right)
    private(set) var roll: Double = 0
    /// −1 … 1 (towards/away)
    private(set) var pitch: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let r = max(-1, min(1, motion.attitude.roll / 0.6))
            let p = max(-1, min(1, (motion.attitude.pitch - 0.6) / 0.6))
            MainActor.assumeIsolated {
                self.roll += (r - self.roll) * 0.2
                self.pitch += (p - self.pitch) * 0.2
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

extension View {
    /// Applies `transform` only when `condition` is true.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
