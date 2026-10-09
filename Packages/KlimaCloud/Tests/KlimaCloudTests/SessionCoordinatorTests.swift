import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KlimaCloud

@MainActor
final class SessionCoordinatorTests: XCTestCase {
    private let key = "auth.session.cf1"

    private func expired(_ refresh: String = "refresh-A") -> CloudSession {
        TestData.session("access-old", refresh: refresh, expiresIn: 30)   // inside the 60 s margin
    }

    func testValidSessionWithoutRefresh() async {
        let calls = Counter()
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in
            calls.increment()
            return TestData.session("x")
        }
        coordinator.replace(with: TestData.session())
        let s = await coordinator.validSession()
        XCTAssertEqual(s?.accessToken, "access-A")
        XCTAssertEqual(calls.value, 0)
    }

    func testConcurrentCallersShareOneRefresh() async {
        let calls = Counter()
        let store = InMemorySecureStore()
        let coordinator = SessionCoordinator(store: store, key: key) { old in
            calls.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            return TestData.session("access-new", refresh: old.refreshToken + "-rotated")
        }
        coordinator.replace(with: expired())
        async let a = coordinator.validSession()
        async let b = coordinator.validSession()
        async let c = coordinator.validSession(forceRefresh: true)
        async let d = coordinator.refreshedSession(after: expired())
        let results = await [a, b, c, d]
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(results.map { $0?.accessToken }, Array(repeating: "access-new", count: 4))
        XCTAssertEqual(coordinator.session?.refreshToken, "refresh-A-rotated")
        // Persisted, device-only.
        let stored = try? JSONDecoder().decode(CloudSession.self, from: store.values[key] ?? Data())
        XCTAssertEqual(stored?.refreshToken, "refresh-A-rotated")
        XCTAssertTrue(store.deviceOnlyKeys.contains(key))
    }

    func testRefreshedSessionAfterAnotherCallerRefreshed() async {
        let calls = Counter()
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in
            calls.increment()
            return TestData.session("access-C", refresh: "refresh-C")
        }
        let old = TestData.session("access-A")
        coordinator.replace(with: TestData.session("access-B"))   // someone else already rotated
        let s = await coordinator.refreshedSession(after: old)
        XCTAssertEqual(s?.accessToken, "access-B")
        XCTAssertEqual(calls.value, 0)
        let forced = await coordinator.refreshedSession(after: TestData.session("access-B"))
        XCTAssertEqual(forced?.accessToken, "access-C")
        XCTAssertEqual(calls.value, 1)
    }

    func testDefinitiveFailureSignalsOnceAndClears() async {
        let store = InMemorySecureStore()
        let rejections = Counter()
        let coordinator = SessionCoordinator(store: store, key: key) { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            throw CloudError.api(status: 400, code: "invalid_grant", message: "")
        }
        coordinator.onRejected = { rejected, error in
            XCTAssertEqual(rejected.refreshToken, "refresh-A")
            XCTAssertTrue(error.isDefinitiveAuthFailure)
            rejections.increment()
        }
        coordinator.replace(with: expired())
        XCTAssertNotNil(store.values[key])
        async let a = coordinator.validSession()
        async let b = coordinator.validSession()
        async let c = coordinator.validSession(forceRefresh: true)
        let results = await [a, b, c]
        XCTAssertEqual(results.compactMap { $0 }.count, 0)
        XCTAssertEqual(rejections.value, 1)
        XCTAssertNil(coordinator.session)
        XCTAssertNil(store.values[key])
        // Later calls do not signal again.
        _ = await coordinator.validSession()
        XCTAssertEqual(rejections.value, 1)
    }

    func testTransientFailureKeepsSession() async {
        let rejections = Counter()
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in throw URLError(.notConnectedToInternet) }
        coordinator.onRejected = { _, _ in rejections.increment() }
        coordinator.replace(with: expired())
        let s = await coordinator.validSession()
        XCTAssertNil(s)   // expired and could not refresh
        XCTAssertEqual(coordinator.session?.refreshToken, "refresh-A")
        XCTAssertEqual(rejections.value, 0)

        // A captive portal's HTML 400 is not definitive either.
        let portal = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in throw CloudError.http(400, "<html>") }
        portal.replace(with: expired())
        _ = await portal.validSession()
        XCTAssertNotNil(portal.session)
    }

    func testRefreshResultIsIgnoredAfterAccountChange() async {
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in
            try await Task.sleep(nanoseconds: 80_000_000)
            return TestData.session("access-stale", refresh: "refresh-stale")
        }
        coordinator.replace(with: expired())
        let pending = Task { await coordinator.validSession() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        coordinator.replace(with: TestData.session("access-other", refresh: "refresh-other"))
        _ = await pending.value
        XCTAssertEqual(coordinator.session?.refreshToken, "refresh-other")
    }

    func testFailedRejectionAfterAccountChangeDoesNotSignOut() async {
        let rejections = Counter()
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            throw CloudError.api(status: 400, code: "invalid_grant", message: "")
        }
        coordinator.onRejected = { _, _ in rejections.increment() }
        coordinator.replace(with: expired())
        let pending = Task { await coordinator.validSession() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        coordinator.replace(with: TestData.session("access-new", refresh: "refresh-new"))
        _ = await pending.value
        XCTAssertEqual(coordinator.session?.refreshToken, "refresh-new")
        XCTAssertEqual(rejections.value, 0)
    }

    func testLoadLockedAndDeferredSave() async {
        let store = InMemorySecureStore()
        let coordinator = SessionCoordinator(store: store, key: key) { $0 }
        coordinator.replace(with: TestData.session())
        let changes = Counter()
        let reloaded = SessionCoordinator(store: store, key: key) { $0 }
        reloaded.onChange = { _ in changes.increment() }
        store.isLocked = true
        XCTAssertEqual(reloaded.load(), .locked)
        XCTAssertNil(reloaded.session)
        store.isLocked = false
        XCTAssertEqual(reloaded.load(), .loaded(coordinator.session))
        XCTAssertEqual(changes.value, 1)

        store.failWrites = true
        reloaded.replace(with: TestData.session("access-Z", refresh: "refresh-Z"))
        XCTAssertTrue(reloaded.needsSaving)
        store.failWrites = false
        reloaded.saveIfNeeded()
        XCTAssertFalse(reloaded.needsSaving)
        let stored = try? JSONDecoder().decode(CloudSession.self, from: store.values[key] ?? Data())
        XCTAssertEqual(stored?.refreshToken, "refresh-Z")
    }

    func testSignOutClearsStore() async {
        let store = InMemorySecureStore()
        let coordinator = SessionCoordinator(store: store, key: key) { $0 }
        coordinator.replace(with: TestData.session())
        coordinator.replace(with: nil)
        XCTAssertNil(coordinator.session)
        XCTAssertNil(store.values[key])
        let after = await coordinator.validSession()
        XCTAssertNil(after)
    }

    func testWaitForPendingRefresh() async {
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: key) { _ in
            try await Task.sleep(nanoseconds: 40_000_000)
            return TestData.session("access-new", refresh: "refresh-new")
        }
        coordinator.replace(with: expired())
        let pending = Task { await coordinator.validSession() }
        try? await Task.sleep(nanoseconds: 5_000_000)
        await coordinator.waitForPendingRefresh()
        XCTAssertEqual(coordinator.session?.refreshToken, "refresh-new")
        _ = await pending.value
    }
}
