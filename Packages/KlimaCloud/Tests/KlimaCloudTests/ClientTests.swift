import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KlimaCloud

final class ClientRequestTests: XCTestCase {
    func testAuthorizeURL() {
        let client = TestData.client(FakeTransport { _, _ in FakeTransport.api(200, [:]) })
        let url = client.authorizeURL(provider: "google", codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
                                      state: "state.with~chars-_", redirectURI: "klimabilanz://auth-callback")
        XCTAssertEqual(url.absoluteString,
                       "https://klimabilanz-api.example.workers.dev/v1/auth/google/start?code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
                       + "&code_challenge_method=S256&state=state.with~chars-_&redirect_uri=klimabilanz%3A%2F%2Fauth-callback")
    }

    func testTrailingSlashInBaseURL() {
        let client = CloudAPIClient(baseURL: URL(string: "https://api.example.at/")!,
                                    transport: FakeTransport { _, _ in FakeTransport.api(200, [:]) })
        XCTAssertEqual(client.url("/v1/config").absoluteString, "https://api.example.at/v1/config")
    }

    func testExchangeCodeSendsFormAndDecodesSession() async throws {
        let transport = FakeTransport { _, _ in FakeTransport.api(200, TestData.tokenJSON()) }
        let session = try await TestData.client(transport).exchangeCode("K+1/2", codeVerifier: "v".padding(toLength: 64, withPad: "v", startingAt: 0),
                                                                         redirectURI: "klimabilanz://auth-callback")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/auth/token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "KlimaBilanz/1.2.3 (45; iOS 26.0)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-KB-App-Version"), "1.2.3")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.formFields, ["grant_type": "authorization_code", "code": "K+1/2",
                                            "code_verifier": String(repeating: "v", count: 64),
                                            "redirect_uri": "klimabilanz://auth-callback"])
        XCTAssertTrue(String(data: request.httpBody!, encoding: .utf8)!.contains("code=K%2B1%2F2"))
        XCTAssertEqual(session.accessToken, "jwt-1")
        XCTAssertEqual(session.refreshToken, "rt-1")
        XCTAssertEqual(session.expiresAt, TestData.fixedNow.addingTimeInterval(900))
        XCTAssertEqual(session.refreshExpiresAt, TestData.fixedNow.addingTimeInterval(5_184_000))
        XCTAssertEqual(session.user.id, "0b9c6a4e-6f5e-4d2a-9a51-3f7d2c1e8b10")
        XCTAssertEqual(session.user.displayName, "Marcel")
        XCTAssertEqual(session.user.provider, "google")
        XCTAssertTrue(session.user.emailVerified)
        XCTAssertEqual(session.user.createdAt.map(APITimestamp.string(from:)), "2026-10-09T12:00:00.000000Z")
    }

    func testRefreshKeepsUserWhenAnswerHasNone() async throws {
        var json = TestData.tokenJSON(access: "jwt-2", refresh: "rt-2")
        json["user"] = nil
        let reply = FakeTransport.api(200, json)
        let transport = FakeTransport { _, _ in reply }
        let old = TestData.session()
        let fresh = try await TestData.client(transport).refresh(old)
        XCTAssertEqual(transport.requests.first?.formFields, ["grant_type": "refresh_token", "refresh_token": "refresh-A"])
        XCTAssertEqual(fresh.refreshToken, "rt-2")
        XCTAssertEqual(fresh.user, old.user)
    }

    func testMalformedTokenAnswerIsInvalidResponse() async {
        let transport = FakeTransport { _, _ in FakeTransport.api(200, ["access_token": "x"]) }
        do {
            _ = try await TestData.client(transport).refresh(TestData.session())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CloudError, .invalidResponse)
        }
    }

    func testNativeAppleBody() async throws {
        let transport = FakeTransport { _, _ in FakeTransport.api(200, TestData.tokenJSON()) }
        _ = try await TestData.client(transport).signInWithApple(identityToken: "id.tok.en", rawNonce: "raw",
                                                                 authorizationCode: "c0de",
                                                                 fullName: "  " + String(repeating: "N", count: 150))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/auth/apple/native")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = request.jsonBody
        XCTAssertEqual(body["identity_token"] as? String, "id.tok.en")
        XCTAssertEqual(body["raw_nonce"] as? String, "raw")
        XCTAssertEqual(body["authorization_code"] as? String, "c0de")
        XCTAssertEqual((body["full_name"] as? String)?.count, 100)
    }

    func testLogoutSendsRefreshTokenAndBearerAndIgnoresErrors() async {
        let transport = FakeTransport { _, _ in FakeTransport.foreign(502) }
        await TestData.client(transport).logout(TestData.session())
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.path, "/v1/auth/logout")
        XCTAssertEqual(request?.formFields, ["refresh_token": "refresh-A"])
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer access-A")
    }

    func testMeAndDisplayName() async throws {
        let transport = FakeTransport { request, _ in
            FakeTransport.api(200, ["user": (TestData.tokenJSON()["user"] as! [String: Any]).merging(["display_name": "Neu"]) { $1 },
                                    "identities": [["provider": "google", "email": "a@b.at"]]])
        }
        let client = TestData.client(transport)
        let me = try await client.me(session: TestData.session())
        XCTAssertEqual(me.displayName, "Neu")
        _ = try await client.updateDisplayName("  Neu  ", session: TestData.session())
        _ = try await client.updateDisplayName(nil, session: TestData.session())
        let requests = transport.requests
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-A")
        XCTAssertEqual(requests[1].httpMethod, "PATCH")
        XCTAssertEqual(requests[1].jsonBody["display_name"] as? String, "Neu")
        XCTAssertTrue(requests[2].jsonBody["display_name"] is NSNull)
    }

    func testDeleteAccountUsesLongTimeout() async throws {
        let transport = FakeTransport { _, _ in FakeTransport.api(200, ["deleted": true]) }
        try await TestData.client(transport).deleteAccount(session: TestData.session())
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/account/delete")
        XCTAssertEqual(transport.requests.first?.timeoutInterval, 60)
        XCTAssertEqual(String(data: transport.requests.first?.httpBody ?? Data(), encoding: .utf8), "{}")
    }

    func testConfigDecodingIsTolerant() async throws {
        let transport = FakeTransport { _, _ in
            FakeTransport.api(200, ["api_version": 1,
                                    "providers": ["google": ["web": true], "microsoft": ["web": false],
                                                  "apple": ["web": true, "native": true], "github": ["web": true]],
                                    "min_app_version": "1.0.0", "sync_tables": ["tickets", "trips", "favorite_routes", "benefits"],
                                    "limits": ["push_max_rows": 500, "pull_max_limit": 500, "max_body_bytes": 1_048_576],
                                    "server_time": "2026-10-09T12:00:00.000000Z", "future": ["x": 1]])
        }
        let config = try await TestData.client(transport).fetchConfig()
        XCTAssertTrue(config.googleWeb)
        XCTAssertFalse(config.microsoftWeb)
        XCTAssertTrue(config.appleWeb)
        XCTAssertTrue(config.appleNative)
        XCTAssertEqual(config.minAppVersion, "1.0.0")
        XCTAssertEqual(config.syncTables.count, 4)
        XCTAssertEqual(config.pushMaxRows, 500)
        XCTAssertEqual(config.serverTime.map(APITimestamp.string(from:)), "2026-10-09T12:00:00.000000Z")

        // The cached copy decodes to the same value.
        let cached = try JSONDecoder().decode(CloudConfig.self, from: try JSONEncoder().encode(config))
        XCTAssertEqual(cached, config)

        // Missing keys: everything off, no crash.
        let empty = try JSONDecoder().decode(CloudConfig.self, from: Data(#"{"providers":{"apple":{}}}"#.utf8))
        XCTAssertFalse(empty.hasAnyProvider(native: true))
        XCTAssertEqual(empty.apiVersion, 1)
        XCTAssertEqual(empty.features, [], "a Worker before `features` supports nothing additive")
        XCTAssertFalse(empty.supports(CloudFeature.tripVia))
        XCTAssertFalse(empty.supports(CloudFeature.tripJourney))
    }

    func testConfigFeatures() throws {
        let config = try JSONDecoder().decode(CloudConfig.self, from: Data(#"{"api_version":1,"features":["trip_via","later"]}"#.utf8))
        XCTAssertTrue(config.supports(CloudFeature.tripVia))
        XCTAssertFalse(config.supports(CloudFeature.tripJourney), "a Worker before migration 0003")
        XCTAssertFalse(config.supports("unknown"))
        XCTAssertEqual(try JSONDecoder().decode(CloudConfig.self, from: try JSONEncoder().encode(config)), config)
        // A malformed list is ignored, not fatal.
        XCTAssertEqual(try JSONDecoder().decode(CloudConfig.self, from: Data(#"{"features":"trip_via"}"#.utf8)).features, [])
    }
}

final class ErrorMappingTests: XCTestCase {
    private func error(for reply: FakeTransport.Reply) async -> CloudError? {
        let client = TestData.client(FakeTransport { _, _ in reply })
        do {
            _ = try await client.refresh(TestData.session())
            return nil
        } catch {
            return error as? CloudError
        }
    }

    func testInvalidGrantFromOurAPIIsDefinitive() async {
        let e = await error(for: FakeTransport.api(400, ["error": "invalid_grant", "error_description": "refresh token reused",
                                                         "request_id": "r1"]))
        XCTAssertEqual(e, .api(status: 400, code: "invalid_grant", message: "refresh token reused"))
        XCTAssertEqual(e?.isDefinitiveAuthFailure, true)
        XCTAssertEqual(e?.errorDescription, "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an.")
    }

    func testSameJSONWithoutHeaderIsNotDefinitive() async {
        var reply = FakeTransport.api(400, ["error": "invalid_grant"])
        reply.headers["X-KB-API"] = nil
        let e = await error(for: reply)
        XCTAssertEqual(e?.status, 400)
        XCTAssertEqual(e?.isDefinitiveAuthFailure, false)
        if case .http = e {} else { XCTFail("expected .http, got \(String(describing: e))") }
    }

    func testCaptivePortalHTMLIsNeverDefinitive() async {
        for status in [200, 302, 401, 403, 404, 511] where status != 200 {
            let e = await error(for: FakeTransport.foreign(status))
            XCTAssertEqual(e?.isDefinitiveAuthFailure, false, "\(status)")
            XCTAssertEqual(e?.isUnauthorized, false, "\(status)")
            XCTAssertEqual(e?.status, status)
        }
        // A 200 HTML page instead of JSON is an invalid response, not a sign-out.
        let e = await error(for: FakeTransport.Reply(status: 200, headers: [:], body: Data("<html/>".utf8)))
        XCTAssertEqual(e, .invalidResponse)
    }

    func testSpecialStatusCodes() async {
        let upgrade = await error(for: FakeTransport.api(426, ["error": "upgrade_required", "min_app_version": "2.0.0"]))
        XCTAssertEqual(upgrade, .upgradeRequired(minVersion: "2.0.0"))
        XCTAssertEqual(upgrade?.errorDescription, "Bitte aktualisiere KlimaBilanz – diese Version wird vom Server nicht mehr unterstützt.")

        let limited = await error(for: FakeTransport.api(429, ["error": "rate_limited"], headers: ["Retry-After": "37"]))
        XCTAssertEqual(limited, .rateLimited(retryAfter: 37))

        let field = await error(for: FakeTransport.api(422, ["error": "unknown_field", "details": ["index": 0, "field": "photo"]]))
        XCTAssertEqual(field, .schemaOutdated)
        XCTAssertEqual(field?.errorDescription,
                       "Der Server ist nicht auf dem neuesten Stand. Bitte das Backend neu bereitstellen (GitHub › Actions › Backend).")

        let table = await error(for: FakeTransport.api(400, ["error": "unknown_table"]))
        XCTAssertEqual(table, .schemaOutdated)

        let row = await error(for: FakeTransport.api(422, ["error": "invalid_row", "details": ["index": 3, "field": "note", "reason": "too long"]]))
        XCTAssertEqual(row, .invalidRow(field: "note"))
        XCTAssertEqual(row?.errorDescription, "Ein Eintrag konnte nicht synchronisiert werden (ungültiges Feld „note“).")

        let unconfigured = await error(for: FakeTransport.api(503, ["error": "server_not_configured"]))
        XCTAssertEqual(unconfigured?.errorDescription, "Der Server ist noch nicht fertig eingerichtet.")

        let unauthorized = await error(for: FakeTransport.api(401, ["error": "invalid_token"]))
        XCTAssertEqual(unauthorized?.isUnauthorized, true)
        XCTAssertEqual(unauthorized?.isDefinitiveAuthFailure, false)
    }

    func testNetworkTexts() {
        XCTAssertEqual(CloudError.userMessage(for: URLError(.notConnectedToInternet)), "Keine Internetverbindung.")
        XCTAssertEqual(CloudError.userMessage(for: URLError(.timedOut)), "Der Server ist gerade nicht erreichbar.")
        XCTAssertEqual(CloudError.userMessage(for: CloudError.sessionExpired), "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an.")
        XCTAssertEqual(CloudError.userMessage(for: CloudError.api(status: 404, code: "provider_disabled", message: ""), providerName: "Apple"),
                       "Die Anmeldung mit Apple ist auf dem Server noch nicht eingerichtet.")
        XCTAssertEqual(CloudError.userMessage(for: CloudError.notConfigured), "Cloud-Anmeldung ist noch nicht eingerichtet.")
    }
}

final class WithSessionTests: XCTestCase {
    func testRefreshesAndRetriesExactlyOnceAfter401() async throws {
        let transport = FakeTransport { request, _ in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer access-B"
                ? FakeTransport.api(200, ["user": TestData.tokenJSON()["user"]!])
                : FakeTransport.api(401, ["error": "invalid_token"], headers: ["WWW-Authenticate": #"Bearer error="invalid_token""#])
        }
        let client = TestData.client(transport)
        let calls = Counter()
        let rejectedSeen = Counter()
        let provider: SessionProvider = { rejected in
            calls.increment()
            if let rejected {
                XCTAssertEqual(rejected.accessToken, "access-A")
                rejectedSeen.increment()
                return TestData.session("access-B", refresh: "refresh-B")
            }
            return TestData.session()
        }
        let user = try await CloudAPIClient.withSession(provider) { try await client.me(session: $0) }
        XCTAssertEqual(user.id, "0b9c6a4e-6f5e-4d2a-9a51-3f7d2c1e8b10")
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(rejectedSeen.value, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSecond401IsThrownWithoutAThirdAttempt() async {
        let transport = FakeTransport { _, _ in FakeTransport.api(401, ["error": "invalid_token"]) }
        let client = TestData.client(transport)
        let provider: SessionProvider = { rejected in TestData.session(rejected == nil ? "access-A" : "access-B") }
        do {
            _ = try await CloudAPIClient.withSession(provider) { try await client.me(session: $0) }
            XCTFail("expected 401")
        } catch {
            XCTAssertEqual((error as? CloudError)?.isUnauthorized, true)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testOtherErrorsAreNotRetried() async {
        let transport = FakeTransport { _, _ in FakeTransport.foreign(401) }
        let client = TestData.client(transport)
        let calls = Counter()
        let provider: SessionProvider = { _ in calls.increment(); return TestData.session() }
        _ = try? await CloudAPIClient.withSession(provider) { try await client.me(session: $0) }
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(transport.requests.count, 1)
    }
}

final class PushPullTests: XCTestCase {
    private let provider: SessionProvider = { _ in TestData.session() }

    private func pushTransport() -> FakeTransport {
        FakeTransport { request, index in
            let rows = (request.jsonBody["rows"] as? [Any])?.count ?? 0
            return FakeTransport.api(200, ["applied": rows, "skipped": 0, "server_rev": 1000 * (index + 1)])
        }
    }

    func testPushSplitsByRowCount() async throws {
        let transport = pushTransport()
        let rows = (0..<1001).map { TestData.trip($0) }
        let result = try await TestData.client(transport).push(table: "trips", rows: rows, session: provider)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests.map { ($0.jsonBody["rows"] as? [Any])?.count ?? -1 }, [500, 500, 1])
        XCTAssertEqual(result, PushResult(applied: 1001, skipped: 0, serverRev: 3000, requests: 3))
        for request in transport.requests {
            XCTAssertEqual(request.url?.path, "/v1/sync/push")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.jsonBody["table"] as? String, "trips")
        }
    }

    func testPushSplitsByBytes() async throws {
        let transport = pushTransport()
        let note = String(repeating: "ä", count: 60_000)   // 120 kB UTF-8 per row
        let rows = (0..<20).map { TestData.trip($0, note: note) }
        _ = try await TestData.client(transport).push(table: "trips", rows: rows, session: provider)
        XCTAssertGreaterThanOrEqual(transport.requests.count, 3)
        var total = 0
        for request in transport.requests {
            XCTAssertLessThanOrEqual(request.httpBody!.count, CloudAPIClient.pushMaxBytes)
            total += (request.jsonBody["rows"] as? [Any])?.count ?? 0
        }
        XCTAssertEqual(total, 20)
    }

    func testPushNeverSendsServerRevAndSkipsEmpty() async throws {
        let transport = pushTransport()
        var row = TestData.trip(1)
        row.server_rev = 77
        _ = try await TestData.client(transport).push(table: "trips", rows: [row], session: provider)
        let sent = try XCTUnwrap((transport.requests.first?.jsonBody["rows"] as? [[String: Any]])?.first)
        XCTAssertNil(sent["server_rev"])
        let none = try await TestData.client(transport).push(table: "trips", rows: [TripDTO](), session: provider)
        XCTAssertEqual(none, PushResult())
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testChunkerBoundaries() {
        let row = Data(repeating: 0x61, count: 100)
        XCTAssertEqual(CloudAPIClient.chunks([], table: "t", maxRows: 2, maxBytes: 1000).count, 0)
        XCTAssertEqual(CloudAPIClient.chunks(Array(repeating: row, count: 5), table: "t", maxRows: 2, maxBytes: 10_000).map(\.count), [2, 2, 1])
        // A single oversized row still goes (alone) – the server answers 413 for it.
        XCTAssertEqual(CloudAPIClient.chunks([Data(repeating: 0, count: 5000), row], table: "t", maxRows: 10, maxBytes: 1000).map(\.count), [1, 1])
        let body = CloudAPIClient.pushBody(table: "trips", rows: [Data("{\"a\":1}".utf8), Data("{}".utf8)])
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"table":"trips","rows":[{"a":1},{}]}"#)
    }

    /// Serves `total` rows with server_rev 1…total in pages, like the Worker.
    private static func pullReply(_ request: URLRequest, total: Int, brokenNext: Bool = false) -> FakeTransport.Reply {
        let query = request.queryFields
        let after = Int(query["after"] ?? "0") ?? 0
        let limit = Int(query["limit"] ?? "500") ?? 500
        let revs = after >= total ? [] : Array((after + 1)...total).prefix(limit)
        let rows: [[String: Any]] = revs.map { rev in
            ["id": UUID().uuidString.lowercased(), "user_id": "u1", "date": "2026-08-15T12:00:00.000000Z",
             "partner_id": "custom", "title": "t\(rev)", "saved_eur": 1.5, "note": "",
             "created_at": "2026-08-15T12:00:00.000000Z", "updated_at": "2026-08-15T12:00:00.000000Z",
             "deleted_at": NSNull(), "server_rev": rev]
        }
        let next: Any = revs.count == limit ? (brokenNext ? after : revs.last!) : NSNull()
        return FakeTransport.api(200, ["rows": rows, "next": next])
    }

    private func pullTransport(total: Int, brokenNext: Bool = false) -> FakeTransport {
        FakeTransport { request, _ in Self.pullReply(request, total: total, brokenNext: brokenNext) }
    }

    func testPullFollowsNextChain() async throws {
        let transport = pullTransport(total: 1203)
        let result: (rows: [BenefitDTO], maxRev: Int64) = try await TestData.client(transport)
            .pullAll(table: "benefits", after: 0, pageSize: 500, session: provider)
        XCTAssertEqual(result.rows.count, 1203)
        XCTAssertEqual(result.maxRev, 1203)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests.map { $0.queryFields["after"] }, ["0", "500", "1000"])
        XCTAssertEqual(transport.requests.first?.queryFields, ["table": "benefits", "after": "0", "limit": "500"])
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
    }

    func testPullExactMultipleEndsWithEmptyPage() async throws {
        let transport = pullTransport(total: 1000)
        let result: (rows: [BenefitDTO], maxRev: Int64) = try await TestData.client(transport)
            .pullAll(table: "benefits", after: 0, session: provider)
        XCTAssertEqual(result.rows.count, 1000)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testPullFromCursorWithNothingNew() async throws {
        let transport = pullTransport(total: 10)
        let result: (rows: [BenefitDTO], maxRev: Int64) = try await TestData.client(transport)
            .pullAll(table: "benefits", after: 10, session: provider)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.maxRev, 10)
    }

    func testNonAdvancingNextIsAnError() async {
        let transport = pullTransport(total: 2000, brokenNext: true)
        do {
            let _: (rows: [BenefitDTO], maxRev: Int64) = try await TestData.client(transport)
                .pullAll(table: "benefits", after: 0, session: provider)
            XCTFail("expected invalidResponse")
        } catch {
            XCTAssertEqual(error as? CloudError, .invalidResponse)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testPullStopsAfterMaxPages() async {
        let transport = pullTransport(total: 100_000)
        do {
            let _: (rows: [BenefitDTO], maxRev: Int64) = try await TestData.client(transport)
                .pullAll(table: "benefits", after: 0, pageSize: 10, maxPages: 3, session: provider)
            XCTFail("expected invalidResponse")
        } catch {
            XCTAssertEqual(error as? CloudError, .invalidResponse)
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testPull401RefreshesOnce() async throws {
        let transport = FakeTransport { request, index in
            index == 0 ? FakeTransport.api(401, ["error": "invalid_token"]) : Self.pullReply(request, total: 3)
        }
        let refreshed = Counter()
        let provider: SessionProvider = { rejected in
            if rejected != nil { refreshed.increment() }
            return TestData.session()
        }
        let result: (rows: [BenefitDTO], maxRev: Int64) = try await TestData.client(transport)
            .pullAll(table: "benefits", after: 0, session: provider)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.maxRev, 3)
        XCTAssertEqual(refreshed.value, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }
}

/// "Reise mit Etappen" keys on the wire (docs/JOURNEYS.md §3): nil = not sent (the server keeps what it has).
final class JourneyDTOTests: XCTestCase {
    func testJourneyKeysAreLeftOutWhenNil() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        var trip = TripDTO(id: UUID(), user_id: "u", date: date, from_name: "Lech", to_name: "Langen am Arlberg", mode: "bus",
                           distance_km: 16, fare_eur: 5.8, is_fare_manual: false, is_round_trip: false, travel_class: "second",
                           companions: 0, states: "V", note: "", created_at: date, updated_at: date)
        var keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: CloudCoding.encoder.encode(trip)) as? [String: Any])
        XCTAssertNil(keys["journey_id"])
        XCTAssertNil(keys["leg_index"])
        trip.journey_id = "7c1d4e2a-9b3f-4a5e-8d6c-1f2e3a4b5c6d"
        trip.leg_index = 2
        keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: CloudCoding.encoder.encode(trip)) as? [String: Any])
        XCTAssertEqual(keys["journey_id"] as? String, "7c1d4e2a-9b3f-4a5e-8d6c-1f2e3a4b5c6d")
        XCTAssertEqual(keys["leg_index"] as? Int, 2)
        let back = try CloudCoding.decoder.decode(TripDTO.self, from: CloudCoding.encoder.encode(trip))
        XCTAssertEqual(back, trip)

        var favorite = FavoriteDTO(id: UUID(), user_id: "u", title: "", from_name: "Lech", to_name: "Innsbruck Hbf", mode: "train",
                                   distance_km: 160, fare_eur: 41.8, is_round_trip: false, states: "T,V", sort_index: 0,
                                   usage_count: 0, created_at: date, updated_at: date)
        keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: CloudCoding.encoder.encode(favorite)) as? [String: Any])
        XCTAssertNil(keys["legs"])
        favorite.legs = ""
        keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: CloudCoding.encoder.encode(favorite)) as? [String: Any])
        XCTAssertEqual(keys["legs"] as? String, "")
    }
}
