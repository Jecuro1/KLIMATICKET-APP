import Foundation

/// Launch diagnostics for CI screenshot runs only (`-KBScreenshot`): wall-clock timestamps of the launch path and
/// every main-thread stall over 250 ms in the first 20 s, appended to `Documents/launch-trace.txt`, which
/// scripts/capture_screenshots.sh collects next to the screenshots. Does nothing in normal use.
final class LaunchTrace: @unchecked Sendable {
    static let shared = LaunchTrace()

    let isEnabled = LaunchMode.isScreenshot
    private let lock = NSLock()
    private let origin = Date()
    private var marked: Set<String> = []
    private var monitoring = false
    private lazy var fileURL: URL = URL.documentsDirectory.appending(path: "launch-trace.txt")

    /// Records `event` once per launch (with `+ms` since the trace started, i.e. since `App.init`).
    static func mark(_ event: String) { shared.mark(event) }

    func mark(_ event: String) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard marked.insert(event).inserted else { return }
        if marked.count == 1 { append("launch \(LaunchMode.screenshotScreen ?? "-") pid \(ProcessInfo.processInfo.processIdentifier)") }
        append(event)
    }

    /// Pings the main queue every 50 ms for 20 s; a ping answered late is a stall (the first one includes the time
    /// until the main run loop starts, i.e. everything before the first frame).
    func startStallMonitor() {
        guard isEnabled else { return }
        lock.lock()
        let start = !monitoring
        monitoring = true
        lock.unlock()
        guard start else { return }
        let origin = origin
        Thread.detachNewThread { [self] in
            while Date().timeIntervalSince(origin) < 20 {
                let sent = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let lag = Date().timeIntervalSince(sent)
                if lag > 0.25 {
                    lock.lock()
                    append("stall \(Int(lag * 1000)) ms from +\(Int(sent.timeIntervalSince(origin) * 1000)) ms")
                    lock.unlock()
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    /// Caller holds `lock`.
    private func append(_ text: String) {
        let now = Date()
        let wall = String(format: "%.3f", now.timeIntervalSince1970)
        let data = Data("\(wall) +\(Int(now.timeIntervalSince(origin) * 1000)) ms  \(text)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
