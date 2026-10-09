import SwiftUI
import CoreMotion

/// Device tilt for holographic / parallax effects (ticket card sheen). Smoothed, ~30 Hz, stops when unused.
/// Changes smaller than `deadBand` are not published, so a phone lying still stops re-rendering the card; all
/// instances share one `CMMotionManager` (Apple: one per app), created on the first `start()`.
@Observable
@MainActor
final class MotionTilt {
    /// −1 … 1 (left/right)
    private(set) var roll: Double = 0
    /// −1 … 1 (towards/away)
    private(set) var pitch: Double = 0

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var isSubscribed = false

    /// 0.002 per step ≈ 0.006° card rotation / 0.05° foil angle – invisible, but sensor noise would otherwise
    /// republish every 33 ms forever, even with the phone lying on a table.
    private static let deadBand = 0.002

    func start() {
        users += 1
        guard users == 1 else { return }
        isSubscribed = MotionFeed.shared.add(self)
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0, isSubscribed else { return }
        MotionFeed.shared.remove(self)
        isSubscribed = false
    }

    fileprivate func receive(roll r: Double, pitch p: Double) {
        let nextRoll = roll + (r - roll) * 0.2
        let nextPitch = pitch + (p - pitch) * 0.2
        guard abs(nextRoll - roll) > Self.deadBand || abs(nextPitch - pitch) > Self.deadBand else { return }
        roll = nextRoll
        pitch = nextPitch
    }
}

/// The app's single device-motion source (30 Hz on the main queue), running while any `MotionTilt` is started.
/// Holds them weakly: one that goes away without `stop()` is dropped, and the sensor stops with the last one.
@MainActor
private final class MotionFeed {
    static let shared = MotionFeed()

    private struct Subscriber {
        weak var tilt: MotionTilt?
    }

    private var manager: CMMotionManager?
    private var subscribers: [ObjectIdentifier: Subscriber] = [:]

    /// false when the device has no motion sensors (simulator).
    func add(_ tilt: MotionTilt) -> Bool {
        let manager = self.manager ?? CMMotionManager()
        self.manager = manager
        guard manager.isDeviceMotionAvailable else { return false }
        subscribers[ObjectIdentifier(tilt)] = Subscriber(tilt: tilt)
        guard !manager.isDeviceMotionActive else { return true }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let r = max(-1, min(1, motion.attitude.roll / 0.6))
            let p = max(-1, min(1, (motion.attitude.pitch - 0.6) / 0.6))
            MainActor.assumeIsolated { self.deliver(roll: r, pitch: p) }
        }
        return true
    }

    func remove(_ tilt: MotionTilt) {
        subscribers[ObjectIdentifier(tilt)] = nil
        stopIfUnused()
    }

    private func deliver(roll: Double, pitch: Double) {
        var gone: [ObjectIdentifier] = []
        for (id, subscriber) in subscribers {
            if let tilt = subscriber.tilt { tilt.receive(roll: roll, pitch: pitch) } else { gone.append(id) }
        }
        guard !gone.isEmpty else { return }
        for id in gone { subscribers[id] = nil }
        stopIfUnused()
    }

    private func stopIfUnused() {
        if subscribers.isEmpty { manager?.stopDeviceMotionUpdates() }
    }
}

extension View {
    /// Applies `transform` only when `condition` is true.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
