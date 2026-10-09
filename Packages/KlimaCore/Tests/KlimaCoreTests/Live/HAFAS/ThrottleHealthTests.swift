import XCTest
@testable import KlimaCore

/// `RequestThrottle` and `LiveHealth` with a fake clock and sleeper (SPEC §A2.3, §D2 WP-A 11).
final class ThrottleHealthTests: XCTestCase {
    static let start = ISO.date("2026-10-09T10:00:00Z")!

    func testMinimumIntervalHolds() async throws {
        let clock = FakeClock(Self.start)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        for _ in 0..<4 { try await throttle.acquire(.oebbHafas, minInterval: 0.3, perMinute: 40) }
        XCTAssertEqual(clock.sleeps.count, 3)
        for s in clock.sleeps { XCTAssertEqual(s, 0.3, accuracy: 1e-5) } // Date arithmetic at epoch 1.79e9 s
        XCTAssertEqual(clock.now.timeIntervalSince(Self.start), 0.9, accuracy: 1e-5)
        // Providers are independent.
        try await throttle.acquire(.oebbShop, minInterval: 1, perMinute: 12)
        XCTAssertEqual(clock.sleeps.count, 3)
    }

    func testBucketAllows40PerMinute() async throws {
        let clock = FakeClock(Self.start)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        let budget = RequestThrottle.budget(for: .oebbHafas)
        XCTAssertEqual(budget.perMinute, 40)
        XCTAssertEqual(budget.minInterval, 0.3)
        for _ in 0..<40 { try await throttle.acquire(.oebbHafas, minInterval: 0, perMinute: 40) }
        XCTAssertTrue(clock.sleeps.isEmpty)
        let count = await throttle.recentCount(.oebbHafas)
        XCTAssertEqual(count, 40)
        do {
            try await throttle.acquire(.oebbHafas, minInterval: 0, perMinute: 40)
            XCTFail("the 41st request within a minute must not queue for 60 s")
        } catch {
            XCTAssertEqual(error as? LiveError, .rateLimited(.oebbHafas, retryAfter: nil))
        }
        // With a long enough maxWait the request waits for the window instead.
        try await throttle.acquire(.oebbHafas, minInterval: 0, perMinute: 40, maxWait: 120)
        XCTAssertEqual(clock.sleeps.last ?? 0, 60, accuracy: 1e-5)
        // Shop budget: 12 per minute, 1 s apart → the 13th within the minute is refused.
        let shopClock = FakeClock(Self.start)
        let shop = RequestThrottle(clock: shopClock.closure, sleeper: shopClock.sleeper)
        for _ in 0..<12 { try await shop.acquire(.oebbShop, minInterval: 1, perMinute: 12) }
        XCTAssertEqual(shopClock.now.timeIntervalSince(Self.start), 11, accuracy: 1e-5)
        do { try await shop.acquire(.oebbShop, minInterval: 1, perMinute: 12); XCTFail() } catch {
            XCTAssertEqual(error as? LiveError, .rateLimited(.oebbShop, retryAfter: nil))
        }
    }

    func testThreeFailuresOpenTheCircuitForTwoMinutes() async throws {
        let clock = FakeClock(Self.start)
        let health = LiveHealth(clock: clock.closure)
        await health.recordFailure(.oebbHafas, .timeout)
        await health.recordFailure(.oebbHafas, .http(status: 502, excerpt: ""))
        try await health.check(.oebbHafas)
        await health.recordFailure(.oebbHafas, .decoding("x"))
        do {
            try await health.check(.oebbHafas)
            XCTFail("open after 3 failures")
        } catch {
            XCTAssertEqual(error as? LiveError, .circuitOpen(.oebbHafas, until: Self.start.addingTimeInterval(120)))
        }
        clock.advance(119)
        do { try await health.check(.oebbHafas); XCTFail() } catch {}
        clock.advance(2)
        try await health.check(.oebbHafas)
        await health.recordSuccess(.oebbHafas)
        let s = await health.status()[.oebbHafas]
        XCTAssertEqual(s?.consecutiveFailures, 0)
        XCTAssertEqual(s?.lastSuccess, clock.now)
        XCTAssertEqual(s?.lastError, .decoding("x"))
    }

    func testBlockedOpensFor30MinutesShopAnd6HoursHafas() async throws {
        let clock = FakeClock(Self.start)
        let health = LiveHealth(clock: clock.closure)
        await health.recordFailure(.oebbShop, .blocked(.oebbShop))
        await health.recordFailure(.oebbHafas, .blocked(.oebbHafas))
        await health.recordFailure(.vaoTariff, .rateLimited(.vaoTariff, retryAfter: 10))
        let status = await health.status()
        XCTAssertEqual(status[.oebbShop]?.openUntil, Self.start.addingTimeInterval(30 * 60))
        XCTAssertEqual(status[.oebbHafas]?.openUntil, Self.start.addingTimeInterval(6 * 3600))
        XCTAssertEqual(status[.vaoTariff]?.openUntil, Self.start.addingTimeInterval(10))
        await health.recordFailure(.vaoTariff, .rateLimited(.vaoTariff, retryAfter: nil))
        let vao = await health.status()[.vaoTariff]?.openUntil
        XCTAssertEqual(vao, Self.start.addingTimeInterval(60))
        await health.reset(.oebbShop)
        try await health.check(.oebbShop)
        do { try await health.check(.oebbHafas); XCTFail() } catch {}
        await health.reset()
        try await health.check(.oebbHafas)
        let empty = await health.status()
        XCTAssertTrue(empty.isEmpty)
    }

    func testNonFailuresDoNotCount() async throws {
        let health = LiveHealth(clock: FakeClock(Self.start).closure)
        for e: LiveError in [.noConnection, .noPrice("NA"), .hafas(code: "LOCATION", message: nil), .offline, .offline, .offline,
                             .http(status: 404, excerpt: ""), .disabled(.oebbHafas)] {
            await health.recordFailure(.oebbHafas, e)
        }
        try await health.check(.oebbHafas)
        let s = await health.status()[.oebbHafas]
        XCTAssertEqual(s?.consecutiveFailures, 0)
        XCTAssertNil(s?.openUntil)
        XCTAssertEqual(s?.lastError, .http(status: 404, excerpt: ""), ".noConnection/.hafas/.disabled do not overwrite lastError")
        await health.recordFailure(.oebbHafas, .timeout)
        await health.recordFailure(.oebbHafas, .noConnection)
        await health.recordFailure(.oebbHafas, .timeout)
        let n = await health.status()[.oebbHafas]?.consecutiveFailures
        XCTAssertEqual(n, 2, ".noConnection neither counts nor resets")
        await health.recordNotice(.oebbHafas, .blocked(.oebbHafas))
        let after = await health.status()[.oebbHafas]
        XCTAssertNil(after?.openUntil, "a notice has no breaker effect")
        XCTAssertEqual(after?.lastError, .blocked(.oebbHafas))
    }

    func testURLErrorMapping() {
        XCTAssertEqual(URLSessionTransport.map(URLError(.timedOut)) as? LiveError, .timeout)
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff] {
            XCTAssertEqual(URLSessionTransport.map(URLError(code)) as? LiveError, .offline, "\(code)")
        }
        XCTAssertTrue(URLSessionTransport.map(URLError(.cancelled)) is CancellationError)
        guard case .network? = URLSessionTransport.map(URLError(.cannotFindHost)) as? LiveError else { return XCTFail() }
    }
}
