import Foundation
#if canImport(Network)
import Network   // the Linux type-check harness has no stub of this module; Xcode always builds the real branch
#endif

/// Wraps `NWPathMonitor`: tells the live layer whether a network path exists (docs/OEBB_LIVE.md §E2).
/// Only started once live data is switched on; it makes no request of its own.
@MainActor
final class Connectivity {
    private var isRunning = false
    /// Called on the main actor whenever the path changes (`true` = online).
    var onChange: ((Bool) -> Void)?
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    func start() {
        guard !isRunning else { return }
        isRunning = true
        #if canImport(Network)
        let monitor = NWPathMonitor()   // a cancelled monitor cannot restart: a fresh one per start
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.onChange?(online) }
        }
        self.monitor = monitor
        monitor.start(queue: DispatchQueue(label: "klimabilanz.connectivity", qos: .utility))
        #endif
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
    }
}
