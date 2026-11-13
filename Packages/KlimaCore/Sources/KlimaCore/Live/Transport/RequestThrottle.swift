import Foundation

/// Per-provider request budget (SPEC §2.3, §A2.3): a minimum interval between two requests plus a sliding one-minute
/// window. Callers reserve a slot and sleep until it; a wait longer than `maxWait` throws instead of queueing.
///
/// | Provider | minInterval | perMinute |
/// |---|---|---|
/// | `.oebbHafas` | `config.hafas.minInterval` (0.3 s) | 40 |
/// | `.oebbShop` | 1.0 s | 12 |
/// | `.vaoTariff` | 1.0 s | 20 |
public actor RequestThrottle {
    /// The budgets of SPEC §A2.3 (minInterval may be raised by the remote config, never lowered below these).
    public static func budget(for provider: LiveProvider) -> (minInterval: TimeInterval, perMinute: Int) {
        switch provider {
        case .oebbHafas: return (0.3, 40)
        case .oebbShop: return (1.0, 12)
        case .vaoTariff: return (1.0, 20)
        }
    }

    private let clock: @Sendable () -> Date
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    /// Reserved send times per provider (the last minute only).
    private var slots: [LiveProvider: [Date]] = [:]
    // MARK: funktionen – counters for Funktionen › Datenschutz (docs/FUNCTIONS_HUB.md §5): requests that really went out (the
    // wait was over), in memory only, from the launch on. No request content is kept, only the time.
    private var sent: [LiveProvider: [Date]] = [:]
    private var totals: [LiveProvider: Int] = [:]

    public init(clock: @escaping @Sendable () -> Date = { Date() },
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.clock = clock
        self.sleeper = sleeper
    }

    /// Waits until the provider may send (min interval + bucket). Throws `.rateLimited(provider, nil)` if the wait would
    /// exceed `maxWait`. The slot is reserved before sleeping, so concurrent callers queue behind each other.
    public func acquire(_ provider: LiveProvider, minInterval: TimeInterval, perMinute: Int, maxWait: TimeInterval = 5) async throws {
        let now = clock()
        var list = (slots[provider] ?? []).filter { now.timeIntervalSince($0) < 60 }
        var slot = now
        if let last = list.last { slot = max(slot, last.addingTimeInterval(max(0, minInterval))) }
        let limit = max(1, perMinute)
        if list.count >= limit { slot = max(slot, list[list.count - limit].addingTimeInterval(60)) }
        let wait = slot.timeIntervalSince(now)
        if wait > maxWait {
            slots[provider] = list
            throw LiveError.rateLimited(provider, retryAfter: nil)
        }
        list.append(slot)
        slots[provider] = list
        if wait > 0 { try await sleeper(wait) }
        recordSent(provider, at: slot)   // MARK: funktionen
    }

    /// Number of requests reserved in the last 60 s (for tests and the Settings status).
    public func recentCount(_ provider: LiveProvider) -> Int {
        let now = clock()
        return (slots[provider] ?? []).filter { now.timeIntervalSince($0) < 60 }.count
    }

    // MARK: funktionen – request counters

    private func recordSent(_ provider: LiveProvider, at date: Date) {
        totals[provider, default: 0] += 1
        var list = (sent[provider] ?? []).filter { date.timeIntervalSince($0) < 60 }
        list.append(date)
        sent[provider] = list
    }

    /// Requests that went out since the throttle was made (the launch): a reserved slot counts once its wait is over.
    public func totalAcquired(_ provider: LiveProvider) -> Int {
        totals[provider] ?? 0
    }

    /// The send time of the newest request, nil before the first.
    public func lastAcquired(_ provider: LiveProvider) -> Date? {
        sent[provider]?.max()
    }

    /// Last minute, since the launch and the newest send time of one provider.
    public func counters(_ provider: LiveProvider) -> RequestCounters {
        let now = clock()
        let lastMinute = (sent[provider] ?? []).filter { now.timeIntervalSince($0) < 60 }.count
        return RequestCounters(lastMinute: lastMinute, total: totalAcquired(provider), last: lastAcquired(provider))
    }

    /// The counters of every provider.
    public func allCounters() -> [LiveProvider: RequestCounters] {
        Dictionary(uniqueKeysWithValues: LiveProvider.allCases.map { ($0, counters($0)) })
    }
}

/// MARK: funktionen – what Funktionen › Datenschutz shows per live provider („3 in der letzten Minute, 41 seit dem Start“).
public struct RequestCounters: Equatable, Sendable {
    public var lastMinute: Int
    public var total: Int
    public var last: Date?

    public init(lastMinute: Int = 0, total: Int = 0, last: Date? = nil) {
        self.lastMinute = lastMinute
        self.total = total
        self.last = last
    }

    public static let zero = RequestCounters()
}
