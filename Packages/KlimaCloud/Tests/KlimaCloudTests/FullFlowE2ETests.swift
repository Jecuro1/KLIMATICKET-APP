import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KlimaCloud

/// Complete flows against `wrangler dev` + local D1 + the fake OIDC server of `E2E/fake-oidc.mjs`, started by
/// `E2E/run-e2e.sh`: real browser sign-ins (Worker /start → provider login → Worker /callback → app code → token) with
/// Google, Microsoft and Apple (form_post), simulated devices that sync like `SyncService` (owner guard, push since the
/// last push, cursor pull, `SyncMergeRule`), 1 200 rows across two devices, a stale write from a device whose clock is
/// behind, soft deletes, an account switch on one device, sign-out, and account deletion with Apple token revocation.
/// Skipped unless `KLIMACLOUD_E2E_URL` and `KLIMACLOUD_E2E_FAKE_OIDC` are set.
final class FullFlowE2ETests: XCTestCase {
    private var base: URL!
    private var fake: URL!
    private let redirect = "klimabilanz://auth-callback"

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["KLIMACLOUD_E2E_URL"].flatMap(URL.init(string:)),
              let fakeURL = env["KLIMACLOUD_E2E_FAKE_OIDC"].flatMap(URL.init(string:)) else {
            throw XCTSkip("KLIMACLOUD_E2E_URL / KLIMACLOUD_E2E_FAKE_OIDC not set – run Packages/KlimaCloud/E2E/run-e2e.sh")
        }
        base = url
        fake = fakeURL
    }

    // MARK: Two devices, 1 200 rows, stale write, soft delete, refresh

    @MainActor
    func testTwoDevicesSync1200RowsWithStaleWriteAndSoftDelete() async throws {
        let alice = Login(sub: "alice-\(UUID().uuidString)", email: "alice@example.test", name: "Alice Alpen")
        let a = SimDevice(name: "A", base: base)
        let b = SimDevice(name: "B", base: base)
        let sa = try await signIn(a, provider: "google", login: alice)
        let sb = try await signIn(b, provider: "google", login: alice)
        XCTAssertEqual(sa.user.id, sb.user.id, "same Google identity → same account")
        XCTAssertNotEqual(sa.refreshToken, sb.refreshToken, "one session per device")
        XCTAssertEqual(sa.user.displayName, "Alice Alpen")
        XCTAssertEqual(sa.user.provider, "google")
        XCTAssertTrue(sa.user.emailVerified)

        // Device A creates 1 200 trips and syncs: 3 push requests (500 + 500 + 200), its own rows come back unchanged.
        let ids = a.addTrips(1200)
        let first = try await a.sync()
        XCTAssertEqual(first.push.requests, 3)
        XCTAssertEqual(first.push.applied, 1200)
        XCTAssertEqual(first.pulled, 1200)
        XCTAssertEqual(a.trips.count, 1200)

        // Device B downloads everything (3 pages following `next`).
        let initial = try await b.sync()
        XCTAssertEqual(initial.push.requests, 0, "nothing local to push")
        XCTAssertEqual(initial.pulled, 1200)
        XCTAssertEqual(b.normalizedTrips, a.normalizedTrips)

        // A edits trip 0 and syncs.
        a.edit(ids[0], note: "A: neuer Stand")
        let edit = try await a.sync()
        XCTAssertEqual(edit.push.applied, 1)

        // B's clock runs an hour behind; B edits the same trip "earlier" than A did. The device notices its clock went
        // backwards and pushes everything: every echo is skipped, and so is the stale edit. The pull brings A's version.
        b.clockOffset = -3600
        b.edit(ids[0], note: "B: veraltet")
        let stale = try await b.sync()
        XCTAssertEqual(stale.push.applied, 0, "stale write and echoes are skipped")
        XCTAssertEqual(stale.push.skipped, 1200)
        XCTAssertEqual(b.trips[ids[0]]?.note, "A: neuer Stand", "the server's (newer) row wins on B")
        b.clockOffset = 0

        // B (clock fixed) soft-deletes trip 1 and edits trip 2; A gets both.
        b.delete(ids[1])
        b.edit(ids[2], note: "B: Notiz ✓")
        let bEdits = try await b.sync()
        XCTAssertEqual(bEdits.push.applied, 2)
        let aPull = try await a.sync()
        XCTAssertEqual(aPull.pulled, 2)
        XCTAssertNotNil(a.trips[ids[1]]?.deleted_at, "the soft delete reached A")
        XCTAssertEqual(a.trips[ids[2]]?.note, "B: Notiz ✓")
        XCTAssertEqual(a.normalizedTrips, b.normalizedTrips, "both devices converge")

        // Nothing changed: an idle sync pushes and pulls nothing.
        let idle = try await a.sync()
        XCTAssertEqual(idle.push.requests, 0)
        XCTAssertEqual(idle.pulled, 0)

        // A garbage access token: 401 → one refresh → retry. Then three concurrent forced refreshes share one rotation.
        var broken = try XCTUnwrap(a.coordinator.session)
        broken.accessToken = "not-a-jwt"
        a.coordinator.replace(with: broken)
        a.edit(ids[3], note: "nach 401")
        let retried = try await a.sync()
        XCTAssertEqual(retried.push.applied, 1)
        XCTAssertEqual(a.refreshes.value, 1)
        async let r1 = b.coordinator.validSession(forceRefresh: true)
        async let r2 = b.coordinator.validSession(forceRefresh: true)
        async let r3 = b.coordinator.validSession(forceRefresh: true)
        let shared = await [r1, r2, r3]
        XCTAssertEqual(b.refreshes.value, 1)
        XCTAssertEqual(Set(shared.compactMap { $0?.refreshToken }).count, 1)
        let afterRefresh = try await b.sync()
        XCTAssertEqual(afterRefresh.pulled, 1)
        XCTAssertEqual(b.rejections, 0)
        XCTAssertEqual(a.normalizedTrips, b.normalizedTrips)
    }

    // MARK: Account switch on one device, sign-out, no merge by e-mail

    @MainActor
    func testAccountSwitchSignOutAndIsolation() async throws {
        let shared = "geteilt-\(UUID().uuidString.prefix(8))@example.test"
        let carol = Login(sub: "carol-\(UUID().uuidString)", email: shared, name: "Carol")
        let dave = Login(sub: "dave-\(UUID().uuidString)", email: shared, name: "Dave")
        let d = SimDevice(name: "D", base: base)
        let carolSession = try await signIn(d, provider: "google", login: carol)
        let ids = d.addTrips(10)
        _ = try await d.sync()

        // Sign-out ends this device's session on the server; local data and the owner stay.
        let signedOut = try XCTUnwrap(d.coordinator.session)
        await d.signOut()
        let dead = await expectCloudError { _ = try await d.client.refresh(signedOut) }
        XCTAssertEqual(dead?.isDefinitiveAuthFailure, true)
        XCTAssertEqual(d.trips.count, 10)

        // Another account (Microsoft, same e-mail address): a different user, never merged by e-mail.
        let daveSession = try await signIn(d, provider: "microsoft", login: dave)
        XCTAssertNotEqual(daveSession.user.id, carolSession.user.id)
        XCTAssertEqual(daveSession.user.provider, "microsoft")
        XCTAssertEqual(daveSession.user.email, shared)
        XCTAssertFalse(daveSession.user.emailVerified, "Microsoft e-mails count as unverified without xms_edov")

        // The owner guard pauses sync until the user decides.
        do {
            _ = try await d.sync()
            XCTFail("expected the account-switch decision")
        } catch let error as SimDevice.SyncError {
            XCTAssertEqual(error, .accountSwitch(previous: carolSession.user.id, new: daveSession.user.id))
        }
        // "Daten dieses iPhones übernehmen": everything goes up into Dave's account.
        let merged = try await d.sync(.mergeLocal)
        XCTAssertEqual(merged.push.applied, 10)
        d.edit(ids[0], note: "nur bei Dave")
        _ = try await d.sync()

        // Carol on another device still has her own, unchanged rows.
        let e = SimDevice(name: "E", base: base)
        _ = try await signIn(e, provider: "google", login: carol)
        let carolPull = try await e.sync()
        XCTAssertEqual(carolPull.pulled, 10)
        XCTAssertEqual(e.trips[ids[0]]?.note, "#0")
        XCTAssertEqual(e.trips.count, 10)

        // "Durch die Daten des neuen Kontos ersetzen": E switches to Erin (Apple, form_post) and gets her (empty) data.
        await e.signOut()
        let erin = Login(sub: "erin-\(UUID().uuidString)", email: nil, name: "Erin Example")
        let erinSession = try await signIn(e, provider: "apple", login: erin)
        XCTAssertEqual(erinSession.user.provider, "apple")
        XCTAssertEqual(erinSession.user.displayName, "Erin Example", "Apple's first-login name from the form post")
        do {
            _ = try await e.sync()
            XCTFail("expected the account-switch decision")
        } catch let error as SimDevice.SyncError {
            XCTAssertEqual(error, .accountSwitch(previous: carolSession.user.id, new: erinSession.user.id))
        }
        let replaced = try await e.sync(.replaceLocal)
        XCTAssertEqual(replaced.push.requests, 0, "replacing never uploads the old account's rows")
        XCTAssertTrue(e.trips.isEmpty)
        XCTAssertEqual(SyncOwnerStore.owner(e.defaults)?.userID, erinSession.user.id)
        let erinAgain = try await e.sync()
        XCTAssertEqual(erinAgain.pulled, 0, "Erin sees nobody else's rows")
    }

    // MARK: Account deletion (Apple web), revocation, other devices fall back

    @MainActor
    func testAccountDeletionEndsEveryDeviceAndRevokesApple() async throws {
        let frank = Login(sub: "frank-\(UUID().uuidString)", email: "frank@privaterelay.appleid.test", name: "Frank Fake")
        let f = SimDevice(name: "F", base: base)
        let g = SimDevice(name: "G", base: base)
        let fs = try await signIn(f, provider: "apple", login: frank)
        // Apple sends the name only on the first authorization; the server keeps it.
        let gs = try await signIn(g, provider: "apple", login: Login(sub: frank.sub, email: frank.email, name: nil))
        XCTAssertEqual(fs.user.id, gs.user.id)
        XCTAssertEqual(gs.user.displayName, "Frank Fake")
        _ = f.addTrips(5)
        _ = try await f.sync()
        let gPull = try await g.sync()
        XCTAssertEqual(gPull.pulled, 5)

        try await CloudAPIClient.withSession(f.provider(for: fs.user.id)) { try await f.client.deleteAccount(session: $0) }

        // Every session of the account is gone at once.
        let me = await expectCloudError { _ = try await f.client.me(session: fs) }
        XCTAssertEqual(me?.isUnauthorized, true)
        let gSession = await g.coordinator.validSession(forceRefresh: true)
        XCTAssertNil(gSession)
        XCTAssertEqual(g.rejections, 1, "the other device signs out to a local profile exactly once")
        XCTAssertNil(g.coordinator.session)
        XCTAssertEqual(g.trips.count, 5, "data on the device stays")

        // The Worker revoked Frank's Apple refresh token (in waitUntil, so poll briefly).
        var revoked = false
        for _ in 0..<50 where !revoked {
            let calls = try await fakeCalls()
            revoked = calls.contains { $0["kind"] as? String == "revoke" && $0["sub"] as? String == frank.sub
                && $0["client_id"] as? String == "com.knitelarlberg.klimabilanz.web" && $0["token_type_hint"] as? String == "refresh_token" }
            if !revoked { try await Task.sleep(nanoseconds: 200_000_000) }
        }
        XCTAssertTrue(revoked, "Apple token revocation with a valid ES256 client secret")

        // Signing in again with the same Apple ID creates a fresh, empty account.
        let h = SimDevice(name: "H", base: base)
        let again = try await signIn(h, provider: "apple", login: Login(sub: frank.sub, email: frank.email, name: nil))
        XCTAssertNotEqual(again.user.id, fs.user.id)
        let fresh = try await h.sync()
        XCTAssertEqual(fresh.pulled, 0)
    }

    // MARK: Errors along the browser flow

    @MainActor
    func testCancelReplayCodeReuseAndCSRF() async throws {
        let device = SimDevice(name: "X", base: base)
        let transport = URLSessionTransport()

        // The app's transport never follows redirects (bearer tokens must not travel to a Location).
        let start = device.client.authorizeURL(provider: "google", codeChallenge: PKCE.challenge(for: PKCE.makeVerifier()),
                                               state: PKCE.randomURLSafe(byteCount: 24), redirectURI: redirect)
        let (_, redirected) = try await transport.send(URLRequest(url: start))
        XCTAssertEqual(redirected.statusCode, 302)
        XCTAssertEqual(redirected.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:))?.host, "accounts.google.com")

        // The user cancels at the provider: silent cancel in the app.
        let state = PKCE.randomURLSafe(byteCount: 24)
        let cancelled = try await browser(provider: "google", challenge: PKCE.challenge(for: PKCE.makeVerifier()), state: state,
                                          login: Login(sub: "x", deny: true))
        XCTAssertEqual(WebAuthCallback.parse(cancelled.app, expectedState: state).failure, .cancelled)
        XCTAssertEqual(WebAuthCallback.parse(cancelled.app, expectedState: "another-sign-in-state").failure, .stateMismatch)

        // A successful login – then the provider callback is replayed: the flow is gone (HTML page, no redirect).
        let verifier = PKCE.makeVerifier()
        let okState = PKCE.randomURLSafe(byteCount: 24)
        let login = Login(sub: "xavier-\(UUID().uuidString)", email: nil, name: nil)
        let flow = try await browser(provider: "microsoft", challenge: PKCE.challenge(for: verifier), state: okState, login: login)
        let (page, replay) = try await transport.send(flow.callback)
        XCTAssertEqual(replay.statusCode, 400)
        XCTAssertNil(replay.value(forHTTPHeaderField: "Location"))
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("Die Anmeldung ist abgelaufen"))

        // Login CSRF: the code is bound to this sign-in's state and PKCE verifier.
        XCTAssertEqual(WebAuthCallback.parse(flow.app, expectedState: PKCE.randomURLSafe(byteCount: 24)).failure, .stateMismatch)
        let code = try WebAuthCallback.parse(flow.app, expectedState: okState).get()
        let wrongVerifier = await expectCloudError {
            _ = try await device.client.exchangeCode(code, codeVerifier: PKCE.makeVerifier(), redirectURI: self.redirect)
        }
        XCTAssertEqual(wrongVerifier?.isDefinitiveAuthFailure, true)
        let consumed = await expectCloudError {
            _ = try await device.client.exchangeCode(code, codeVerifier: verifier, redirectURI: self.redirect)
        }
        XCTAssertEqual(consumed?.isDefinitiveAuthFailure, true, "a failed redemption consumes the code")

        // Code reuse after a successful redemption revokes the session it created.
        let v2 = PKCE.makeVerifier()
        let s2 = PKCE.randomURLSafe(byteCount: 24)
        let second = try await browser(provider: "google", challenge: PKCE.challenge(for: v2), state: s2, login: login)
        let code2 = try WebAuthCallback.parse(second.app, expectedState: s2).get()
        let session = try await device.client.exchangeCode(code2, codeVerifier: v2, redirectURI: redirect)
        _ = try await device.client.me(session: session)
        let reuse = await expectCloudError { _ = try await device.client.exchangeCode(code2, codeVerifier: v2, redirectURI: self.redirect) }
        XCTAssertEqual(reuse?.isDefinitiveAuthFailure, true)
        let afterReuse = await expectCloudError { _ = try await device.client.me(session: session) }
        XCTAssertEqual(afterReuse?.isUnauthorized, true)

        // The fake provider saw a correct token exchange from the Worker each time (client secret, PKCE, redirect_uri).
        let rejected = try await fakeCalls().filter { $0["kind"] as? String == "rejected" }
        XCTAssertEqual(rejected.count, 0, "the Worker never sent an invalid request to a provider: \(rejected)")
    }

    // MARK: Browser simulation

    struct Login {
        var sub: String
        var email: String? = nil
        var name: String? = nil
        var deny = false
    }

    private struct FormPost: Decodable {
        var action: String
        var fields: [String: String]
    }

    /// What `ASWebAuthenticationSession` does: GET the Worker's /start, sign in at the (fake) provider, deliver the
    /// provider's answer to the Worker's /callback (GET, or Apple's form POST), and return the final
    /// `klimabilanz://auth-callback?…` URL together with the callback request (for replays).
    @MainActor
    private func browser(provider: String, challenge: String, state: String, login: Login) async throws -> (app: URL, callback: URLRequest) {
        let transport = URLSessionTransport()
        let client = CloudAPIClient(baseURL: base, transport: transport)
        let start = client.authorizeURL(provider: provider, codeChallenge: challenge, state: state, redirectURI: redirect)
        let (_, toProvider) = try await transport.send(URLRequest(url: start))
        XCTAssertEqual(toProvider.statusCode, 302)
        let authorize = try XCTUnwrap(toProvider.value(forHTTPHeaderField: "Location").flatMap { URLComponents(string: $0) })

        // Same path and query at the fake provider, plus the simulated user login.
        var atFake = try XCTUnwrap(URLComponents(url: fake, resolvingAgainstBaseURL: false))
        atFake.path = "/\(provider)\(authorize.path)"
        var extra = [("login_sub", login.sub)]
        if let email = login.email { extra.append(("login_email", email)) }
        if let name = login.name { extra.append(("login_name", name)) }
        if login.deny { extra.append(("login_deny", "1")) }
        atFake.percentEncodedQuery = (authorize.percentEncodedQuery ?? "") + "&"
            + extra.map { "\($0.0)=\(CloudAPIClient.percentEncode($0.1))" }.joined(separator: "&")
        let (body, answer) = try await transport.send(URLRequest(url: try XCTUnwrap(atFake.url)))

        var callback: URLRequest
        if provider == "apple" {
            XCTAssertEqual(answer.statusCode, 200, String(decoding: body, as: UTF8.self))
            let form = try JSONDecoder().decode(FormPost.self, from: body)
            callback = URLRequest(url: try XCTUnwrap(URL(string: form.action)))
            callback.httpMethod = "POST"
            callback.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            callback.setValue("https://appleid.apple.com", forHTTPHeaderField: "Origin")   // cross-site form_post
            callback.httpBody = Data(CloudAPIClient.formEncode(form.fields).utf8)
        } else {
            XCTAssertEqual(answer.statusCode, 302, String(decoding: body, as: UTF8.self))
            callback = URLRequest(url: try XCTUnwrap(answer.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:))))
        }
        let (page, toApp) = try await transport.send(callback)
        XCTAssertEqual(toApp.statusCode, provider == "apple" ? 303 : 302, String(decoding: page, as: UTF8.self))
        XCTAssertEqual(toApp.value(forHTTPHeaderField: "X-KB-API"), "1")
        let app = try XCTUnwrap(toApp.value(forHTTPHeaderField: "Location").flatMap(URL.init(string:)))
        XCTAssertEqual(app.scheme, "klimabilanz")
        return (app, callback)
    }

    /// A complete sign-in of `device` (like `AuthService.signIn(with:using:)`): PKCE + state, browser, callback parsing,
    /// code exchange, session handed to the device's `SessionCoordinator`.
    @MainActor
    private func signIn(_ device: SimDevice, provider: String, login: Login) async throws -> CloudSession {
        let verifier = PKCE.makeVerifier()
        let state = PKCE.randomURLSafe(byteCount: 24)
        let flow = try await browser(provider: provider, challenge: PKCE.challenge(for: verifier), state: state, login: login)
        let code = try WebAuthCallback.parse(flow.app, expectedState: state).get()
        let session = try await device.client.exchangeCode(code, codeVerifier: verifier, redirectURI: redirect)
        device.coordinator.replace(with: session)
        return session
    }

    private func fakeCalls() async throws -> [[String: Any]] {
        let (data, _) = try await URLSessionTransport().send(URLRequest(url: fake.appendingPathComponent("__calls")))
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    @MainActor
    private func expectCloudError(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async -> CloudError? {
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
}

// MARK: - A simulated iPhone

/// One device: a `SessionCoordinator` with its own (in-memory) keychain, its own UserDefaults (sync owner, push time,
/// cursors) and a local trip store. `sync` follows `SyncService.pass` (App/Sources/Services/SyncService.swift) for one
/// table: owner guard, push of rows changed since the last push (everything when the clock went backwards), paged pull
/// on the server cursor, merge with `SyncMergeRule`, cursor moves after the merge.
@MainActor
final class SimDevice {
    enum SyncError: Error, Equatable {
        case accountSwitch(previous: String, new: String)
    }

    enum Mode {
        case normal, mergeLocal, replaceLocal
    }

    let name: String
    let client: CloudAPIClient
    let defaults: UserDefaults
    let coordinator: SessionCoordinator
    let refreshes: Counter
    private(set) var rejections = 0
    /// Seconds the device clock is off (negative = behind).
    var clockOffset: TimeInterval = 0
    var trips: [UUID: TripDTO] = [:]

    init(name: String, base: URL) {
        self.name = name
        let client = CloudAPIClient(baseURL: base, transport: URLSessionTransport(), appVersion: "1.0.0", build: "1", osVersion: "26.0")
        self.client = client
        defaults = UserDefaults(suiteName: "e2e.\(name).\(UUID().uuidString)")!
        let counter = Counter()
        refreshes = counter
        coordinator = SessionCoordinator(store: InMemorySecureStore(), key: "auth.session.cf1") { old in
            counter.increment()
            return try await client.refresh(old)
        }
        coordinator.onRejected = { [weak self] _, _ in self?.rejections += 1 }
    }

    /// The device clock, at the wire's microsecond precision.
    var now: Date { APITimestamp.date(from: APITimestamp.string(from: Date().addingTimeInterval(clockOffset)))! }

    /// The local rows as the server stores them (user id is filled in on push).
    var normalizedTrips: [UUID: TripDTO] {
        trips.mapValues { row in
            var r = row
            r.user_id = ""
            r.server_rev = nil
            return r
        }
    }

    func addTrips(_ count: Int) -> [UUID] {
        let end = now
        return (0..<count).map { i in
            // 1 ms apart, all in the past: a stamp in the future would count as "changed since the last push" again.
            let at = APITimestamp.date(from: APITimestamp.string(from: end.addingTimeInterval(-Double(count - i) / 1000)))!
            let trip = TripDTO(id: UUID(), user_id: "", date: at, from_name: "Feldkirch", to_name: "Wien Hbf", mode: "train",
                               distance_km: 683.4, fare_eur: 104.6, is_fare_manual: i % 5 == 0, is_round_trip: i % 2 == 0,
                               travel_class: i % 7 == 0 ? "first" : "second", companions: i % 3, states: "V,T,S,W",
                               note: "#\(i)", category: i % 4 == 0 ? "work" : "", is_induced: i % 9 == 0,
                               via: i % 6 == 0 ? "at:47:1187\tInnsbruck Hauptbahnhof\n\tLech Postamt" : "",
                               journey_id: i % 8 == 0 ? "7c1d4e2a-9b3f-4a5e-8d6c-1f2e3a4b5c6d" : "", leg_index: i % 8 == 0 ? 1 : 0,
                               created_at: at, updated_at: at)
            trips[trip.id] = trip
            return trip.id
        }
    }

    func edit(_ id: UUID, note: String) {
        guard var trip = trips[id] else { return }
        trip.note = note
        trip.updated_at = now
        trips[id] = trip
    }

    func delete(_ id: UUID) {
        guard var trip = trips[id] else { return }
        let at = now
        trip.deleted_at = at
        trip.updated_at = at
        trips[id] = trip
    }

    /// Like `AuthService.signOut()`: clear the local session first, then end it on the server. Data and owner stay.
    func signOut() async {
        await coordinator.waitForPendingRefresh()
        let old = coordinator.session
        coordinator.replace(with: nil)
        if let old { await client.logout(old) }
    }

    func provider(for uid: String) -> SessionProvider {
        let coordinator = self.coordinator
        return { rejected in
            let next: CloudSession?
            if let rejected {
                next = await coordinator.refreshedSession(after: rejected)
            } else {
                next = await coordinator.validSession()
            }
            guard let next, next.user.id == uid else { throw CloudError.sessionExpired }
            return next
        }
    }

    @discardableResult
    func sync(_ mode: Mode = .normal) async throws -> (push: PushResult, pulled: Int) {
        guard let session = await coordinator.validSession() else { throw CloudError.sessionExpired }
        let uid = session.user.id.lowercased()
        switch mode {
        case .normal:
            if let owner = SyncOwnerStore.owner(defaults) {
                if owner.userID != uid { throw SyncError.accountSwitch(previous: owner.userID, new: uid) }
            } else {
                SyncOwnerStore.claim(userID: uid, email: session.user.email, defaults)
            }
        case .mergeLocal:
            SyncOwnerStore.claim(userID: uid, email: session.user.email, defaults)
            SyncOwnerStore.setLastPush(nil, userID: uid, defaults)
        case .replaceLocal:
            break
        }
        let provider = self.provider(for: uid)
        let started = now
        var pushed = PushResult()
        var watermark: Date?
        if mode != .replaceLocal {
            let pushStarted = now
            let last = SyncOwnerStore.lastPush(userID: uid, defaults) ?? .distantPast
            let since = last > pushStarted ? Date.distantPast : last   // clock went backwards: push everything
            let rows = trips.values.filter { $0.updated_at > since }.sorted { $0.updated_at < $1.updated_at }.map { row -> TripDTO in
                var r = row
                r.user_id = uid
                return r
            }
            pushed = try await client.push(table: TripDTO.table, rows: rows, session: provider)
            SyncOwnerStore.setLastPush(pushStarted, userID: uid, defaults)
            watermark = pushStarted
        }
        let cursor = mode == .replaceLocal ? 0 : SyncOwnerStore.cursor(table: TripDTO.table, userID: uid, defaults)
        let pulled: (rows: [TripDTO], maxRev: Int64) = try await client.pullAll(table: TripDTO.table, after: cursor, session: provider)
        guard coordinator.session?.user.id.lowercased() == uid else { throw CloudError.sessionExpired }
        if mode == .replaceLocal { trips = [:] }
        let mergeNow = now
        for var remote in pulled.rows {
            remote.server_rev = nil
            remote.user_id = ""
            let local = trips[remote.id]
            var dirty = false
            if let local, let watermark { dirty = local.updated_at > watermark && local.updated_at <= mergeNow }
            let action = SyncMergeRule.action(localUpdatedAt: local?.updated_at, localIsDirty: dirty,
                                              remoteUpdatedAt: remote.updated_at, remoteIsDeleted: remote.deleted_at != nil,
                                              sameContent: local.map { normalized($0) } == remote)
            switch action {
            case .insert, .apply: trips[remote.id] = remote
            case .keep: break
            }
        }
        SyncOwnerStore.setCursor(pulled.maxRev, table: TripDTO.table, userID: uid, defaults)
        if mode == .replaceLocal {
            SyncOwnerStore.claim(userID: uid, email: session.user.email, defaults)
            SyncOwnerStore.setLastPush(started, userID: uid, defaults)
        }
        return (pushed, pulled.rows.count)
    }

    private func normalized(_ row: TripDTO) -> TripDTO {
        var r = row
        r.user_id = ""
        r.server_rev = nil
        return r
    }
}
