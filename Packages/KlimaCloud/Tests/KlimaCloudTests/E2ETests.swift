import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KlimaCloud

/// End-to-end against the real Worker (`wrangler dev` + local D1), started and seeded by `E2E/run-e2e.sh`.
/// Skipped unless `KLIMACLOUD_E2E_URL` and `KLIMACLOUD_E2E_SEED` are set. Every test redeems its own seeded one-time
/// code, so the tests are independent of each other and of their order.
final class E2ETests: XCTestCase {
    private struct Seed: Decodable {
        struct Code: Decodable { var code: String; var verifier: String; var user: String }
        var users: [String: String]
        var codes: [String: Code]
        var redirect: String
    }

    private var base: URL!
    private var seed: Seed!
    private var client: CloudAPIClient!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["KLIMACLOUD_E2E_URL"].flatMap(URL.init(string:)), let seedPath = env["KLIMACLOUD_E2E_SEED"] else {
            throw XCTSkip("KLIMACLOUD_E2E_URL / KLIMACLOUD_E2E_SEED not set – run Packages/KlimaCloud/E2E/run-e2e.sh")
        }
        base = url
        seed = try JSONDecoder().decode(Seed.self, from: Data(contentsOf: URL(fileURLWithPath: seedPath)))
        client = CloudAPIClient(baseURL: url, transport: URLSessionTransport(), appVersion: "1.0.0", build: "1", osVersion: "26.0")
    }

    private func signIn(_ label: String) async throws -> CloudSession {
        let code = try XCTUnwrap(seed.codes[label], "no seeded code \(label)")
        let session = try await client.exchangeCode(code.code, codeVerifier: code.verifier, redirectURI: seed.redirect)
        XCTAssertEqual(session.user.id, code.user)
        return session
    }

    private func expectError(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async -> CloudError? {
        do {
            try await body()
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch {
            guard let cloud = error as? CloudError else {
                XCTFail("unexpected \(error)", file: file, line: line)
                return nil
            }
            return cloud
        }
    }

    // MARK: Config & browser start

    func testConfigReflectsSecrets() async throws {
        let config = try await client.fetchConfig()
        XCTAssertEqual(config.apiVersion, 1)
        XCTAssertTrue(config.googleWeb)          // dummy credentials in the e2e env file
        XCTAssertFalse(config.microsoftWeb)
        XCTAssertFalse(config.appleWeb)
        XCTAssertFalse(config.appleNative)
        XCTAssertEqual(config.minAppVersion, "1.0.0")
        XCTAssertEqual(config.syncTables, SyncTables.all)
        XCTAssertEqual(config.pushMaxRows, CloudAPIClient.pushMaxRows)
        XCTAssertNotNil(config.serverTime)
    }

    func testStartRedirectsToGoogleAndErrorsComeBackToTheApp() async throws {
        let verifier = PKCE.makeVerifier()
        let state = PKCE.randomURLSafe(byteCount: 24)
        let start = client.authorizeURL(provider: "google", codeChallenge: PKCE.challenge(for: verifier), state: state,
                                        redirectURI: seed.redirect)
        let google = try await location(of: start)
        XCTAssertEqual(google.host, "accounts.google.com")
        let query = WebAuthCallback.parameters(google)
        XCTAssertEqual(query["client_id"], "e2e-google-client.apps.googleusercontent.com")
        XCTAssertEqual(query["redirect_uri"], base.absoluteString + "/v1/auth/google/callback")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertNotNil(query["nonce"])
        XCTAssertNotEqual(query["state"], state)   // the provider gets the flow id, never the app state

        // Invalid challenge with a valid redirect + state: the error goes back to the app.
        let bad = client.authorizeURL(provider: "google", codeChallenge: "short", state: state, redirectURI: seed.redirect)
        let back = try await location(of: bad)
        XCTAssertEqual(back.scheme, "klimabilanz")
        XCTAssertEqual(WebAuthCallback.parse(back, expectedState: state).failure, .authorization(""))

        // A provider without secrets is disabled.
        let microsoft = client.authorizeURL(provider: "microsoft", codeChallenge: PKCE.challenge(for: verifier), state: state,
                                            redirectURI: seed.redirect)
        let disabled = WebAuthCallback.parse(try await location(of: microsoft), expectedState: state).failure
        XCTAssertEqual(disabled?.code, "provider_disabled")
        XCTAssertEqual(disabled?.message(providerName: "Microsoft"), "Die Anmeldung mit Microsoft ist auf dem Server noch nicht eingerichtet.")
    }

    func testNativeAppleIsDisabledWithoutBundleID() async throws {
        let error = await expectError {
            _ = try await self.client.signInWithApple(identityToken: "a.b.c", rawNonce: "n", authorizationCode: nil, fullName: nil)
        }
        XCTAssertEqual(error?.code, "provider_disabled")
        XCTAssertEqual(error?.status, 404)
    }

    // MARK: Sessions

    func testCodeExchangeMeAndDisplayName() async throws {
        let session = try await signIn("main")
        XCTAssertEqual(session.user.provider, "google")
        XCTAssertEqual(session.user.email, "one@e2e.test")
        XCTAssertTrue(session.user.emailVerified)
        XCTAssertEqual(session.user.displayName, "E2E one")
        XCTAssertNotNil(session.user.createdAt)
        XCTAssertFalse(session.isExpired)
        XCTAssertEqual(session.refreshToken.count, 43)

        let me = try await client.me(session: session)
        XCTAssertEqual(me.id, session.user.id)
        let renamed = try await client.updateDisplayName("  Marcel ✓ ", session: session)
        XCTAssertEqual(renamed.displayName, "Marcel ✓")
        let again = try await client.me(session: session)
        XCTAssertEqual(again.displayName, "Marcel ✓")
    }

    func testCodeReuseRevokesTheSession() async throws {
        let session = try await signIn("reuse")
        let code = seed.codes["reuse"]!
        let reuse = await expectError {
            _ = try await self.client.exchangeCode(code.code, codeVerifier: code.verifier, redirectURI: self.seed.redirect)
        }
        XCTAssertEqual(reuse?.isDefinitiveAuthFailure, true)
        let after = await expectError { _ = try await self.client.me(session: session) }
        XCTAssertEqual(after?.isUnauthorized, true)
    }

    func testRefreshRotationGraceAndReuseDetection() async throws {
        let s0 = try await signIn("rotation")
        let s1 = try await client.refresh(s0)
        XCTAssertNotEqual(s1.refreshToken, s0.refreshToken)
        // (The access token may be byte-identical: same session, same second → same JWT claims.)
        XCTAssertEqual(s1.user.id, s0.user.id)
        _ = try await client.me(session: s1)

        // Lost response: the same old token again within 60 s gets a fresh successor (grace)…
        let s1b = try await client.refresh(s0)
        XCTAssertNotEqual(s1b.refreshToken, s1.refreshToken)
        let s2 = try await client.refresh(s1b)
        _ = try await client.me(session: s2)

        // …but once its successor has been used, the old token is reuse: the whole session dies.
        let reuse = await expectError { _ = try await self.client.refresh(s0) }
        XCTAssertEqual(reuse?.isDefinitiveAuthFailure, true)
        let family = await expectError { _ = try await self.client.refresh(s2) }
        XCTAssertEqual(family?.isDefinitiveAuthFailure, true)
        let access = await expectError { _ = try await self.client.me(session: s2) }
        XCTAssertEqual(access?.isUnauthorized, true)
    }

    func testLogoutEndsOnlyThisSessionImmediately() async throws {
        let session = try await signIn("logout")
        await client.logout(session)
        let me = await expectError { _ = try await self.client.me(session: session) }
        XCTAssertEqual(me?.isUnauthorized, true)
        let refresh = await expectError { _ = try await self.client.refresh(session) }
        XCTAssertEqual(refresh?.isDefinitiveAuthFailure, true)
    }

    @MainActor
    func testCoordinatorRefreshesOnceAndWithSessionRetriesAfter401() async throws {
        let session = try await signIn("coordinator")
        let client = self.client!
        let refreshes = Counter()
        let coordinator = SessionCoordinator(store: InMemorySecureStore(), key: "auth.session.cf1") { old in
            refreshes.increment()
            return try await client.refresh(old)
        }
        // The device thinks the token is valid, the server does not (garbage access token): 401 → refresh → retry.
        var broken = session
        broken.accessToken = "not-a-jwt"
        coordinator.replace(with: broken)
        let provider: SessionProvider = { rejected in
            let next: CloudSession?
            if let rejected {
                next = await coordinator.refreshedSession(after: rejected)
            } else {
                next = await coordinator.validSession()
            }
            guard let next else { throw CloudError.sessionExpired }
            return next
        }
        let me = try await CloudAPIClient.withSession(provider) { try await client.me(session: $0) }
        XCTAssertEqual(me.id, session.user.id)
        XCTAssertEqual(refreshes.value, 1)

        // Three concurrent forced refreshes share one rotation (a second rotation of the same token would be reuse).
        async let a = coordinator.validSession(forceRefresh: true)
        async let b = coordinator.validSession(forceRefresh: true)
        async let c = coordinator.validSession(forceRefresh: true)
        let results = await [a, b, c]
        XCTAssertEqual(refreshes.value, 2)
        XCTAssertEqual(Set(results.compactMap { $0?.accessToken }).count, 1)
        let current = try XCTUnwrap(coordinator.session)
        _ = try await client.me(session: current)
    }

    // MARK: Sync

    private func fixtureRow<Row: SyncRow>(_ type: Row.Type, userID: String) throws -> Row {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backend/test/fixtures/contract-rows.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var push = ((root["tables"] as! [String: Any])[Row.table] as! [String: Any])["push"] as! [String: Any]
        push["user_id"] = userID
        push["id"] = UUID().uuidString   // fresh ids: the local D1 lives as long as the dev server
        return try CloudCoding.decoder.decode(Row.self, from: JSONSerialization.data(withJSONObject: push))
    }

    func testSyncRoundTripLastWriterWinsAndPaging() async throws {
        let session = try await signIn("sync")
        let uid = session.user.id
        let provider: SessionProvider = { _ in session }

        // Fixture rows of all four tables round-trip with canonical values.
        let ticket = try fixtureRow(TicketDTO.self, userID: uid)
        let trip = try fixtureRow(TripDTO.self, userID: uid)
        let favorite = try fixtureRow(FavoriteDTO.self, userID: uid)
        let benefit = try fixtureRow(BenefitDTO.self, userID: uid)
        let pushedTickets = try await client.push(table: TicketDTO.table, rows: [ticket], session: provider)
        XCTAssertEqual(pushedTickets.applied, 1)
        _ = try await client.push(table: TripDTO.table, rows: [trip], session: provider)
        _ = try await client.push(table: FavoriteDTO.table, rows: [favorite], session: provider)
        _ = try await client.push(table: BenefitDTO.table, rows: [benefit], session: provider)

        func pull<Row: SyncRow>(_ type: Row.Type, after: Int64 = 0) async throws -> (rows: [Row], maxRev: Int64) {
            try await client.pullAll(table: Row.table, after: after, session: provider)
        }
        func normalized<Row: SyncRow>(_ row: Row) -> Row {
            var copy = row
            copy.server_rev = nil
            copy.user_id = uid
            return copy
        }
        let tickets = try await pull(TicketDTO.self)
        XCTAssertEqual(tickets.rows.map(normalized), [ticket])
        XCTAssertEqual(tickets.rows.first?.server_rev, tickets.maxRev)
        let favorites = try await pull(FavoriteDTO.self)
        XCTAssertEqual(favorites.rows.map(normalized), [favorite])
        XCTAssertNotNil(favorites.rows.first?.deleted_at)
        let benefits = try await pull(BenefitDTO.self)
        XCTAssertEqual(benefits.rows.map(normalized), [benefit])
        let firstTrips = try await pull(TripDTO.self)
        XCTAssertEqual(firstTrips.rows.map(normalized), [trip])
        XCTAssertEqual(APITimestamp.string(from: firstTrips.rows[0].updated_at), "2026-10-08T03:50:12.500000Z")

        // Paging + chunking: 1201 more trips go up in 3 requests and come back over 3 pages.
        let base = APITimestamp.date(from: "2026-09-01T06:00:00.000001Z")!
        let many = (0..<1201).map { i in
            TripDTO(id: UUID(), user_id: uid, date: micro(base.addingTimeInterval(Double(i) * 60)), from_name: "Feldkirch",
                    to_name: "Bludenz", mode: "train", distance_km: 21.3, fare_eur: 5.1, is_fare_manual: false,
                    is_round_trip: i % 3 == 0, travel_class: "second", companions: i % 4, states: "V", note: "#\(i)",
                    category: "", is_induced: false, created_at: base, updated_at: micro(base.addingTimeInterval(Double(i))))
        }
        let pushed = try await client.push(table: TripDTO.table, rows: many, session: provider)
        XCTAssertEqual(pushed.requests, 3)
        XCTAssertEqual(pushed.applied, 1201)
        let afterFirst = try await pull(TripDTO.self, after: firstTrips.maxRev)
        XCTAssertEqual(afterFirst.rows.count, 1201)
        XCTAssertEqual(Set(afterFirst.rows.map(\.id)), Set(many.map(\.id)))
        XCTAssertEqual(afterFirst.rows.map(normalized).sorted { $0.note < $1.note }, many.sorted { $0.note < $1.note })
        let nothing = try await pull(TripDTO.self, after: afterFirst.maxRev)
        XCTAssertTrue(nothing.rows.isEmpty)
        XCTAssertEqual(nothing.maxRev, afterFirst.maxRev)

        // Last writer wins: an older write is skipped, an echo is skipped, a newer one applies.
        var stale = trip
        stale.note = "stale"
        stale.updated_at = micro(trip.updated_at.addingTimeInterval(-3600))
        let staleResult = try await client.push(table: TripDTO.table, rows: [stale], session: provider)
        XCTAssertEqual(staleResult.applied, 0)
        XCTAssertEqual(staleResult.skipped, 1)
        let echo = try await client.push(table: TripDTO.table, rows: [trip], session: provider)
        XCTAssertEqual(echo.applied, 0)
        var newer = trip
        newer.note = "neuer ✓"
        newer.updated_at = micro(trip.updated_at.addingTimeInterval(0.000001))
        newer.deleted_at = newer.updated_at   // soft delete in the same write
        let newerResult = try await client.push(table: TripDTO.table, rows: [newer], session: provider)
        XCTAssertEqual(newerResult.applied, 1)
        let changes = try await pull(TripDTO.self, after: afterFirst.maxRev)
        XCTAssertEqual(changes.rows.map(normalized), [newer])
        XCTAssertGreaterThan(changes.maxRev, afterFirst.maxRev)

        // A far-future clock is clamped to the server's now.
        var future = benefit
        future.updated_at = Date().addingTimeInterval(86_400 * 30)
        future.note = "Zukunft"
        _ = try await client.push(table: BenefitDTO.table, rows: [future], session: provider)
        let clamped = try await pull(BenefitDTO.self, after: benefits.maxRev)
        XCTAssertEqual(clamped.rows.first?.note, "Zukunft")
        XCTAssertLessThan(clamped.rows.first?.updated_at ?? .distantFuture, Date().addingTimeInterval(11 * 60))
    }

    func testIsolationAndUpgradeGate() async throws {
        let session = try await signIn("other")
        let provider: SessionProvider = { _ in session }
        let trips: (rows: [TripDTO], maxRev: Int64) = try await client.pullAll(table: TripDTO.table, after: 0, session: provider)
        XCTAssertTrue(trips.rows.isEmpty, "user two must not see user one's trips")

        // Another account's id in user_id is rejected.
        var foreign = TestData.trip(1)
        foreign.user_id = seed.users["one"]!
        let mismatch = await expectError { _ = try await self.client.push(table: TripDTO.table, rows: [foreign], session: provider) }
        XCTAssertEqual(mismatch?.code, "user_mismatch")

        let old = CloudAPIClient(baseURL: base, transport: URLSessionTransport(), appVersion: "0.9", build: "1", osVersion: "26.0")
        let gate = await expectError {
            let _: (rows: [TripDTO], maxRev: Int64) = try await old.pullAll(table: TripDTO.table, after: 0, session: provider)
        }
        XCTAssertEqual(gate, .upgradeRequired(minVersion: "1.0.0"))
    }

    func testAccountDeletion() async throws {
        let session = try await signIn("delete")
        let provider: SessionProvider = { _ in session }
        _ = try await client.push(table: BenefitDTO.table, rows: [try fixtureRow(BenefitDTO.self, userID: session.user.id)],
                                  session: provider)
        try await client.deleteAccount(session: session)
        let me = await expectError { _ = try await self.client.me(session: session) }
        XCTAssertEqual(me?.isUnauthorized, true)
        let refresh = await expectError { _ = try await self.client.refresh(session) }
        XCTAssertEqual(refresh?.isDefinitiveAuthFailure, true)
    }

    // MARK: Helpers

    /// The date as it comes back from the server (canonical µs string → Date).
    private func micro(_ date: Date) -> Date { APITimestamp.date(from: APITimestamp.string(from: date))! }

    /// The `Location` of a redirect, without following it.
    private func location(of url: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, response) = try await session.data(for: URLRequest(url: url))
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue([302, 303].contains(http.statusCode), "status \(http.statusCode)")
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-KB-API"), "1")
        return try XCTUnwrap(http.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)))
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
