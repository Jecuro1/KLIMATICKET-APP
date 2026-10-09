import Foundation

/// Lightweight main-thread hang detector: a background thread posts a block to the main queue every 0.5 s and
/// reports when it takes longer than 250 ms to run (the main thread was blocked – the user saw a frozen UI).
///
/// Long hangs (≥ 2 s) also write a marker through `onLongHang`, so a hang that ends with iOS killing the app is
/// still reported on the next launch. Paused in the background (a suspended app is not a hang).
final class HangWatchdog: @unchecked Sendable {
    struct Hang: Sendable {
        var start: Date
        var durationMs: Double
        var screen: String?
    }

    let pingInterval: TimeInterval
    let threshold: TimeInterval
    /// From this duration on, an ongoing hang is reported every second via `onLongHang`.
    let longHangThreshold: TimeInterval = 2

    var screenProvider: @Sendable () -> String? = { nil }
    var onHang: @Sendable (Hang) -> Void = { _ in }
    /// `Hang` so far while it lasts (duration grows); `nil` once it ended.
    var onLongHang: @Sendable (Hang?) -> Void = { _ in }

    private let lock = NSLock()
    private var isRunning = false
    /// Identifies the current loop thread – a thread left over from `stop()` + `start()` exits.
    private var runToken = 0
    private var isPaused = true
    /// Bumped on every pause/resume – a ping that spans a background phase is discarded.
    private var epoch = 0

    init(pingInterval: TimeInterval = 0.5, threshold: TimeInterval = 0.25) {
        self.pingInterval = pingInterval
        self.threshold = threshold
    }

    func start() {
        lock.lock()
        guard !isRunning else { lock.unlock(); return }
        isRunning = true
        runToken += 1
        let token = runToken
        lock.unlock()
        let thread = Thread { [weak self] in self?.run(token: token) }
        thread.name = "KlimaBilanz.HangWatchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    func stop() {
        lock.lock()
        isRunning = false
        epoch += 1
        lock.unlock()
    }

    func pause() {
        lock.lock()
        isPaused = true
        epoch += 1
        lock.unlock()
    }

    func resume() {
        lock.lock()
        isPaused = false
        epoch += 1
        lock.unlock()
    }

    private func state(token: Int) -> (running: Bool, paused: Bool, epoch: Int) {
        lock.lock(); defer { lock.unlock() }
        return (isRunning && token == runToken, isPaused, epoch)
    }

    private func run(token: Int) {
        while true {
            Thread.sleep(forTimeInterval: pingInterval)
            let before = state(token: token)
            guard before.running else { return }
            guard !before.paused else { continue }

            let ping = Ping()
            let sentAt = DispatchTime.now().uptimeNanoseconds
            let wallStart = Date()
            DispatchQueue.main.async { ping.respond() }
            if ping.wait(seconds: threshold) { continue }

            // The main thread is blocked. Note what was on screen while it still is.
            let screen = screenProvider()
            var reportedLong = false
            while !ping.wait(seconds: 1) {
                let soFar = Double(DispatchTime.now().uptimeNanoseconds &- sentAt) / 1_000_000
                if soFar >= longHangThreshold * 1000, state(token: token).epoch == before.epoch {
                    onLongHang(Hang(start: wallStart, durationMs: soFar, screen: screen))
                    reportedLong = true
                }
            }
            if reportedLong { onLongHang(nil) }

            let after = state(token: token)
            guard after.running, !after.paused, after.epoch == before.epoch else { continue }
            let durationMs = Double(ping.respondedAt &- sentAt) / 1_000_000
            // A blocked main thread for minutes is a debugger pause or a suspended process, not a user-visible hang.
            guard durationMs >= threshold * 1000, durationMs < 120_000 else { continue }
            onHang(Hang(start: wallStart, durationMs: durationMs, screen: screen))
        }
    }

    /// One main-queue round trip; `respondedAt` is taken on the main thread, so a late watchdog wake-up does not
    /// inflate the measured duration.
    private final class Ping: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _respondedAt: UInt64 = 0

        var respondedAt: UInt64 {
            lock.lock(); defer { lock.unlock() }
            return _respondedAt
        }

        func respond() {
            lock.lock()
            _respondedAt = DispatchTime.now().uptimeNanoseconds
            lock.unlock()
            semaphore.signal()
        }

        /// True when the main thread answered within `seconds`.
        func wait(seconds: TimeInterval) -> Bool {
            semaphore.wait(timeout: .now() + seconds) == .success
        }
    }
}
