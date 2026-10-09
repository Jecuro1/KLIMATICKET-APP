import XCTest
@testable import KlimaCloud

final class MergeRuleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    func testTable() {
        typealias A = SyncMergeRule.Action
        let cases: [(local: Date?, dirty: Bool, remote: Date, deleted: Bool, same: Bool, expected: A)] = [
            (nil, false, t1, false, false, .insert),     // new row
            (nil, false, t1, true, false, .keep),        // unknown tombstone
            (t0, false, t1, false, true, .keep),         // identical
            (t0, true, t1, false, false, .apply),        // unpushed edit, remote newer → remote wins
            (t1, true, t0, false, false, .keep),         // unpushed edit, local newer → keep for the next push
            (t1, true, t1, false, false, .keep),         // tie on a dirty row: local stays (pushed next)
            (t1, false, t0, false, false, .apply),       // pushed: server is authoritative even if older (clamped)
            (t0, false, t1, true, false, .apply),        // remote soft delete
        ]
        for c in cases {
            XCTAssertEqual(SyncMergeRule.action(localUpdatedAt: c.local, localIsDirty: c.dirty, remoteUpdatedAt: c.remote,
                                                remoteIsDeleted: c.deleted, sameContent: c.same), c.expected, "\(c)")
        }
    }
}

final class OwnerStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "klimacloud.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testClaimWritesBackendMarker() {
        XCTAssertNil(SyncOwnerStore.owner(defaults))
        SyncOwnerStore.claim(userID: "ABC-1", email: "a@b.at", defaults)
        XCTAssertEqual(SyncOwnerStore.owner(defaults), .init(userID: "abc-1", email: "a@b.at", isLegacy: false))
        XCTAssertEqual(defaults.string(forKey: "sync.owner.backend"), "cf1")
    }

    func testOwnerWithoutMarkerIsLegacy() {
        // Written by the Supabase-era app (no backend marker).
        defaults.set("supabase-user", forKey: "sync.owner.userID")
        defaults.set("old@b.at", forKey: "sync.owner.email")
        let owner = SyncOwnerStore.owner(defaults)
        XCTAssertEqual(owner?.userID, "supabase-user")
        XCTAssertEqual(owner?.isLegacy, true)
        // The first Cloudflare account adopts the data: claim + push everything.
        SyncOwnerStore.claim(userID: "cf-user", email: nil, defaults)
        SyncOwnerStore.setLastPush(nil, userID: "cf-user", defaults)
        XCTAssertEqual(SyncOwnerStore.owner(defaults), .init(userID: "cf-user", email: nil, isLegacy: false))
        XCTAssertNil(SyncOwnerStore.lastPush(userID: "cf-user", defaults))
    }

    func testCursorsAndLastPushArePerAccount() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        SyncOwnerStore.setLastPush(date, userID: "U1", defaults)
        SyncOwnerStore.setCursor(9_007_199_254_740_993, table: "trips", userID: "u1", defaults)
        XCTAssertEqual(SyncOwnerStore.lastPush(userID: "u1", defaults), date)
        XCTAssertEqual(SyncOwnerStore.cursor(table: "trips", userID: "U1", defaults), 9_007_199_254_740_993)
        XCTAssertEqual(SyncOwnerStore.cursor(table: "trips", userID: "u2", defaults), 0)
        SyncOwnerStore.resetPullCursors(userID: "u1", defaults)
        XCTAssertEqual(SyncOwnerStore.cursor(table: "trips", userID: "u1", defaults), 0)
        XCTAssertEqual(SyncOwnerStore.lastPush(userID: "u1", defaults), date)
    }

    func testForget() {
        SyncOwnerStore.claim(userID: "u1", email: "a@b.at", defaults)
        SyncOwnerStore.setLastPush(Date(), userID: "u1", defaults)
        SyncOwnerStore.setCursor(5, table: "benefits", userID: "u1", defaults)
        SyncOwnerStore.forget(userID: "U1", defaults)
        XCTAssertNil(SyncOwnerStore.owner(defaults))
        XCTAssertNil(defaults.string(forKey: "sync.owner.backend"))
        XCTAssertNil(SyncOwnerStore.lastPush(userID: "u1", defaults))
        XCTAssertEqual(SyncOwnerStore.cursor(table: "benefits", userID: "u1", defaults), 0)
    }

    func testForgetOtherAccountKeepsOwner() {
        SyncOwnerStore.claim(userID: "u1", email: nil, defaults)
        SyncOwnerStore.forget(userID: "u2", defaults)
        XCTAssertEqual(SyncOwnerStore.owner(defaults)?.userID, "u1")
    }
}

final class SessionPersistenceTests: XCTestCase {
    func testSessionCodableRoundTrip() throws {
        let session = CloudSession(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1_000),
                                   refreshExpiresAt: Date(timeIntervalSince1970: 2_000),
                                   user: CloudUser(id: "u", email: nil, emailVerified: false, displayName: nil, avatarURL: nil,
                                                   provider: "apple", createdAt: APITimestamp.date(from: "2026-10-09T12:00:00.000001Z")))
        let back = try JSONDecoder().decode(CloudSession.self, from: try JSONEncoder().encode(session))
        XCTAssertEqual(back, session)
        XCTAssertTrue(session.isExpired(at: Date(timeIntervalSince1970: 941)))
        XCTAssertFalse(session.isExpired(at: Date(timeIntervalSince1970: 939)))
    }
}
