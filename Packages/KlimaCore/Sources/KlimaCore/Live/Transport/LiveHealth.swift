import Foundation

/// Circuit breaker + status per provider (SPEC §A2.3), shown in Settings › Live-Daten.
///
/// | Event | Circuit open for |
/// |---|---|
/// | `.blocked` | 30 min (shop, VAO) / 6 h (HAFAS `AUTH`) |
/// | `.rateLimited` | `retryAfter ?? 60 s` |
/// | 3 consecutive `.http(5xx)` / `.timeout` / `.network` / `.decoding` | 2 min |
///
/// `.offline`, `.noConnection`, `.noPrice` and `.hafas(code)` are not failures for the breaker. Success resets
/// `consecutiveFailures`.
public actor LiveHealth {
    public struct Status: Sendable, Hashable {
        public var lastSuccess: Date?
        public var lastError: LiveError?
        public var openUntil: Date?
        public var consecutiveFailures: Int

        public init(lastSuccess: Date? = nil, lastError: LiveError? = nil, openUntil: Date? = nil, consecutiveFailures: Int = 0) {
            self.lastSuccess = lastSuccess
            self.lastError = lastError
            self.openUntil = openUntil
            self.consecutiveFailures = consecutiveFailures
        }
    }

    static let failureThreshold = 3
    static let failureOpenSeconds: TimeInterval = 120

    private let clock: @Sendable () -> Date
    private var statuses: [LiveProvider: Status] = [:]

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    /// Throws `.circuitOpen(p, until:)` while the circuit is open.
    public func check(_ p: LiveProvider) throws {
        if let until = statuses[p]?.openUntil, until > clock() { throw LiveError.circuitOpen(p, until: until) }
    }

    public func recordSuccess(_ p: LiveProvider) {
        var s = statuses[p] ?? Status()
        s.lastSuccess = clock()
        s.consecutiveFailures = 0
        s.openUntil = nil
        statuses[p] = s
    }

    public func recordFailure(_ p: LiveProvider, _ e: LiveError) {
        let now = clock()
        var s = statuses[p] ?? Status()
        switch e {
        case .blocked:
            s.lastError = e
            s.openUntil = now.addingTimeInterval(p == .oebbHafas ? 6 * 3600 : 30 * 60)
        case .rateLimited(_, let retryAfter):
            s.lastError = e
            s.openUntil = now.addingTimeInterval(max(1, retryAfter ?? 60))
        case .http(let status, _) where status >= 500:
            s.lastError = e
            countFailure(&s, now: now)
        case .timeout, .network, .decoding:
            s.lastError = e
            countFailure(&s, now: now)
        case .http, .sessionExpired, .offline:
            s.lastError = e
        case .noConnection, .noPrice, .hafas, .disabled, .circuitOpen:
            return
        }
        statuses[p] = s
    }

    /// Records an error for the status display without any breaker effect (e.g. the primary HAFAS profile answered
    /// AUTH and the fallback profile took over).
    public func recordNotice(_ p: LiveProvider, _ e: LiveError) {
        var s = statuses[p] ?? Status()
        s.lastError = e
        statuses[p] = s
    }

    public func status() -> [LiveProvider: Status] { statuses }

    /// On config change / user „Erneut versuchen“. nil resets every provider.
    public func reset(_ p: LiveProvider? = nil) {
        if let p { statuses[p] = nil } else { statuses = [:] }
    }

    private func countFailure(_ s: inout Status, now: Date) {
        s.consecutiveFailures += 1
        if s.consecutiveFailures >= Self.failureThreshold { s.openUntil = now.addingTimeInterval(Self.failureOpenSeconds) }
    }
}
