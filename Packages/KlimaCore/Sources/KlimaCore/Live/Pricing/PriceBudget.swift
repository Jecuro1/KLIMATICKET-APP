import Foundation

/// Per-quote budget of the price flow (SPEC §B6, W-B acceptance 4): at most `limit` requests to the price back ends
/// (ÖBB shop + VAO) and a total time budget (12 s). Bound as a task-local by `LivePriceService` for the duration of
/// one quote; `OebbShopClient` and `VerbundTariffClient` spend one unit before every request they send (retries and
/// session renewals included). Outside a quote (direct client calls) there is no budget.
final class PriceRequestBudget: @unchecked Sendable {
    @TaskLocal static var current: PriceRequestBudget?

    let limit: Int
    let deadline: Date
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var _used = 0
    private var _expired = false

    init(limit: Int, deadline: Date, clock: @escaping @Sendable () -> Date) {
        self.limit = limit
        self.deadline = deadline
        self.clock = clock
    }

    var used: Int {
        lock.lock(); defer { lock.unlock() }
        return _used
    }

    var remaining: Int { max(0, limit - used) }

    /// True once the time budget was exceeded (checked against the injected clock).
    var isExpired: Bool {
        lock.lock(); defer { lock.unlock() }
        return _expired
    }

    /// Reserves one request. Throws `.timeout` past the deadline and `.noPrice` when the request budget is used up
    /// (nothing is sent in either case).
    func spend(_ provider: LiveProvider) throws {
        try checkDeadline()
        lock.lock()
        defer { lock.unlock() }
        guard _used < limit else { throw LiveError.noPrice(Self.exhausted) }
        _used += 1
    }

    /// Throws `.timeout` when the injected clock is past the deadline.
    func checkDeadline() throws {
        if clock() > deadline {
            lock.lock()
            _expired = true
            lock.unlock()
            throw LiveError.timeout
        }
    }

    func markExpired() {
        lock.lock()
        _expired = true
        lock.unlock()
    }

    static let exhausted = "Anfragebudget erschöpft"

    /// Spends from the bound budget, if any.
    static func spend(_ provider: LiveProvider) throws {
        try current?.spend(provider)
    }
}
