import XCTest
@testable import KlimaCore

/// `HafasClient` over `FixtureTransport` with a fake clock and sleeper (SPEC §A3.1, §A3.2, §A2.3; §D2 WP-A 9).
final class HafasErrorTests: XCTestCase {
    static let start = ISO.date("2026-10-09T10:15:00Z")!
    static let ibk = Location.station(extId: "8100108", name: "Innsbruck Hbf")
    static let wien = Location.station(extId: "1290401", name: "Wien Hbf (U)")

    static func query(_ minute: Int = 0) -> JourneyQuery {
        JourneyQuery(origin: ibk, destination: wien, date: start.addingTimeInterval(TimeInterval(minute * 60)))
    }

    static func json(_ status: Int = 200, _ body: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    static let gate = "fahrplan.oebb.at/gate"
    static let mgate = "fahrplan.oebb.at/bin/mgate.exe"

    func testBatchMapsEachServiceResult() async throws {
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: try Fixture.hafasResponse("batch_edge_cases_errors"))])
        let (client, health) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        let results = try await client.journeys(batch: [Self.query(), Self.query(1), Self.query(2), Self.query(3)])
        let errors = results.map { r -> LiveError? in if case .failure(let e) = r { return e }; return nil }
        let texts = try XCTUnwrap(try Fixture.golden("hafas/batch_edge_cases_errors")["svcErrTxtOut"] as? [String])
        XCTAssertEqual(errors, [.hafas(code: "LOCATION", message: texts[0]), .noConnection,
                                .hafas(code: "PARAMETER", message: texts[2]), .hafas(code: "H9381", message: texts[3])])
        XCTAssertEqual(t.recorded.count, 1, "one envelope for the whole batch")
        let svc = try XCTUnwrap(try t.jsonBody(0)["svcReqL"] as? [[String: Any]])
        XCTAssertEqual(svc.count, 4)
        let status = await health.status()[.oebbHafas]
        XCTAssertEqual(status?.consecutiveFailures, 0)
        XCTAssertNil(status?.openUntil, "service errors never open the circuit")
    }

    func testAuthOnPrimaryFallsBackToLegacyProfileFor6Hours() async throws {
        let clock = FakeClock(Self.start)
        let t = FixtureTransport(routes: [
            .init(urlSuffix: Self.gate, response: try Fixture.hafasResponse("error_auth_invalid_aid")),
            .init(urlSuffix: Self.mgate, response: try Fixture.hafasResponse("legacy_mgate141_tripsearch_st_anton_innsbruck")),
        ])
        let (client, health) = HafasClient.testClient(t, clock: clock)
        let page = try await client.journeys(Self.query())
        XCTAssertFalse(page.journeys.isEmpty)
        XCTAssertEqual(t.recorded.map(\.url.absoluteString), ["https://fahrplan.oebb.at/gate", "https://fahrplan.oebb.at/bin/mgate.exe"])
        let isFallback = await client.isUsingFallback
        XCTAssertTrue(isFallback)
        let status = await health.status()[.oebbHafas]
        XCTAssertEqual(status?.lastError, .blocked(.oebbHafas), "primary AUTH reported in Settings")
        XCTAssertNil(status?.openUntil)
        // The legacy envelope: ver 1.41, client v String, other aid.
        let legacy = try t.jsonBody(1)
        XCTAssertEqual(legacy["ver"] as? String, "1.41")
        XCTAssertEqual((legacy["auth"] as? [String: Any])?["aid"] as? String, "OWDL4fE4ixNiPBBm")

        // The next call goes straight to the fallback …
        _ = try await client.journeys(Self.query(5))
        XCTAssertEqual(t.recorded.last?.url.absoluteString, "https://fahrplan.oebb.at/bin/mgate.exe")
        XCTAssertEqual(t.recorded.count, 3)
        // … until 6 h have passed.
        clock.advance(6 * 3600 + 1)
        _ = try await client.journeys(Self.query(10))
        XCTAssertEqual(t.recorded[3].url.absoluteString, "https://fahrplan.oebb.at/gate")
    }

    func testAuthOnBothProfilesIsBlockedAndOpensCircuit6Hours() async throws {
        let clock = FakeClock(Self.start)
        let auth = try Fixture.hafasResponse("error_auth_invalid_aid")
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: auth), .init(urlSuffix: Self.mgate, response: auth)])
        let (client, health) = HafasClient.testClient(t, clock: clock)
        do {
            _ = try await client.journeys(Self.query())
            XCTFail("expected .blocked")
        } catch {
            XCTAssertEqual(error as? LiveError, .blocked(.oebbHafas))
        }
        XCTAssertEqual(t.recorded.count, 2, "one fallback attempt, no further retries")
        let open = await health.status()[.oebbHafas]?.openUntil
        XCTAssertEqual(open, clock.now.addingTimeInterval(6 * 3600))
        // While open: no I/O at all.
        do {
            _ = try await client.locations("Innsbruck", types: .all, maxResults: 8)
            XCTFail("expected .circuitOpen")
        } catch {
            guard case .circuitOpen(.oebbHafas, _)? = error as? LiveError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(t.recorded.count, 2)
    }

    func testParseMapsToDecoding() async throws {
        var config = LiveConfig.default
        config.hafasFallback = nil
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: try Fixture.hafasResponse("error_parse_unknown_field"))])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start), config: config)
        let errTxt = try XCTUnwrap(try Fixture.golden("hafas/error_parse_unknown_field")["errTxt"] as? String)
        do {
            _ = try await client.serverInfo()
            XCTFail("expected .decoding")
        } catch {
            XCTAssertEqual(error as? LiveError, .decoding(errTxt))
        }
        XCTAssertEqual(t.recorded.count, 1)
    }

    func testParseOnBothProfilesIsDecoding() async throws {
        let parse = try Fixture.hafasResponse("error_parse_invalid_enum_rtmode")
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: parse), .init(urlSuffix: Self.mgate, response: parse)])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        do {
            _ = try await client.journeys(Self.query())
            XCTFail("expected .decoding")
        } catch {
            guard case .decoding? = error as? LiveError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(t.recorded.count, 2)
    }

    func test503TwiceRetriesOnceThenHTTP() async throws {
        let clock = FakeClock(Self.start)
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: Self.json(503, "Service Unavailable"))])
        let (client, health) = HafasClient.testClient(t, clock: clock)
        do {
            _ = try await client.journeys(Self.query())
            XCTFail("expected .http")
        } catch {
            guard case .http(503, _)? = error as? LiveError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(t.recorded.count, 2, "exactly one automatic retry")
        XCTAssertTrue(clock.sleeps.contains(1.5), "retry after 1.5 s: \(clock.sleeps)")
        let failures = await health.status()[.oebbHafas]?.consecutiveFailures
        XCTAssertEqual(failures, 1, "one logical failure")
    }

    func test503ThenSuccess() async throws {
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: Self.json(503, "x"),
                                                sequence: [Self.json(503, "x"), try Fixture.hafasResponse("tripsearch_innsbruck_wien_hbf")])])
        let (client, health) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        let page = try await client.journeys(Self.query())
        XCTAssertFalse(page.journeys.isEmpty)
        XCTAssertEqual(t.recorded.count, 2)
        let status = await health.status()[.oebbHafas]
        XCTAssertNotNil(status?.lastSuccess)
        XCTAssertEqual(status?.consecutiveFailures, 0)
    }

    func testHTMLBodyIsHTTPAndNotRetried() async throws {
        let html = HTTPResponse(status: 200, headers: ["Content-Type": "text/html"], body: Data("<html><body>Wartung</body></html>".utf8))
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: html)])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        do {
            _ = try await client.journeys(Self.query())
            XCTFail("expected .http")
        } catch {
            guard case .http(200, let excerpt)? = error as? LiveError else { return XCTFail("\(error)") }
            XCTAssertTrue(excerpt.contains("Wartung"))
        }
        XCTAssertEqual(t.recorded.count, 1)
    }

    func testCloudflare403AndRateLimit() async throws {
        let block = HTTPResponse(status: 403, headers: ["Content-Type": "text/html"], body: Data("<!DOCTYPE html><title>Attention Required!</title>".utf8))
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: block)])
        let (client, health) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        do { _ = try await client.journeys(Self.query()); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .blocked(.oebbHafas)) }
        XCTAssertEqual(t.recorded.count, 1, "never retry a block")
        let open = await health.status()[.oebbHafas]?.openUntil
        XCTAssertNotNil(open)

        let t2 = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: HTTPResponse(status: 429, headers: ["Retry-After": "30"], body: Data()))])
        let (c2, _) = HafasClient.testClient(t2, clock: FakeClock(Self.start))
        do { _ = try await c2.journeys(Self.query()); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .rateLimited(.oebbHafas, retryAfter: 30)) }
        XCTAssertEqual(t2.recorded.count, 1)
    }

    func testKillSwitchAndDisabledProviderMakeNoIO() async throws {
        let t = FixtureTransport(routes: [])
        var config = LiveConfig.default
        config.killSwitch = true
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start), config: config)
        let calls: [() async throws -> Void] = [
            { _ = try await client.locations("Innsbruck", types: .all, maxResults: 8) },
            { _ = try await client.nearby(GeoPoint(latitude: 47.26, longitude: 11.4), maxDistanceMeters: 400, maxResults: 10, products: .all) },
            { _ = try await client.journeys(Self.query()) },
            { _ = try await client.journeys(batch: [Self.query()]) },
            { _ = try await client.refresh("¶HKI¶x", includeStopovers: true, includePolyline: false) },
            { _ = try await client.refresh(batch: ["¶HKI¶x"]) },
            { _ = try await client.trip("2|#VN#1", includePolyline: true) },
            { _ = try await client.board(BoardQuery(station: Self.ibk, date: Self.start)) },
            { _ = try await client.remarks(RemarksQuery(from: Self.start, to: Self.start.addingTimeInterval(3600))) },
            { _ = try await client.serverInfo() },
        ]
        for call in calls {
            do { try await call(); XCTFail("expected .disabled") } catch { XCTAssertEqual(error as? LiveError, .disabled(.oebbHafas)) }
        }
        XCTAssertTrue(t.recorded.isEmpty)

        // Provider toggle (hafas.enabled = false) and a remote update at runtime behave the same.
        var off = LiveConfig.default
        off.hafas.enabled = false
        let t2 = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: try Fixture.hafasResponse("locmatch_innsbruck"))])
        let (c2, _) = HafasClient.testClient(t2, clock: FakeClock(Self.start))
        _ = try await c2.locations("Innsbruck", types: .all, maxResults: 8)
        await c2.update(config: off)
        do { _ = try await c2.locations("Innsbruck", types: .all, maxResults: 8); XCTFail() } catch {
            XCTAssertEqual(error as? LiveError, .disabled(.oebbHafas), "even a cached query is refused")
        }
        XCTAssertEqual(t2.recorded.count, 1)
    }

    func testHeadersAreHonestAndCookieFree() async throws {
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: try Fixture.hafasResponse("serverinfo"))])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        let info = try await client.serverInfo()
        XCTAssertEqual(info.hciVersion, "1.96")
        let r = try XCTUnwrap(t.recorded.first)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.headers["User-Agent"], "KlimaBilanz/1.0.0 (iPhone; iOS; private, low-volume)")
        XCTAssertEqual(r.headers["Content-Type"], "application/json")
        XCTAssertEqual(r.headers["Accept"], "application/json")
        XCTAssertEqual(r.headers["Accept-Encoding"], "gzip")
        XCTAssertNil(r.headers["Cookie"])
        XCTAssertEqual(r.timeout, 20)
        let body = try t.jsonBody(0)
        XCTAssertEqual(body["ver"] as? String, "1.88")
        XCTAssertEqual(body["ext"] as? String, "OEBB.14")
    }

    func testOfflineIsNotRetriedAndNotAFailure() async throws {
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: Self.json(200, "{}"), error: .offline)])
        let (client, health) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        do { _ = try await client.journeys(Self.query()); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .offline) }
        XCTAssertEqual(t.recorded.count, 1)
        let failures = await health.status()[.oebbHafas]?.consecutiveFailures ?? 0
        XCTAssertEqual(failures, 0)
    }

    func testTimeoutRetriesOnce() async throws {
        let clock = FakeClock(Self.start)
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: Self.json(200, "{}"), error: .timeout)])
        let (client, health) = HafasClient.testClient(t, clock: clock)
        for i in 0..<3 {
            do { _ = try await client.journeys(Self.query(i)); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .timeout) }
        }
        XCTAssertEqual(t.recorded.count, 6)
        // Three logical failures → circuit open for 2 minutes.
        let open = await health.status()[.oebbHafas]?.openUntil
        XCTAssertNotNil(open)
        do { _ = try await client.journeys(Self.query(9)); XCTFail() } catch {
            guard case .circuitOpen? = error as? LiveError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(t.recorded.count, 6)
    }

    func testCachesAndThrottleSpacing() async throws {
        let clock = FakeClock(Self.start)
        let t = FixtureTransport(routes: [
            .init(urlSuffix: Self.gate, bodyContains: "\"LocMatch\"", response: try Fixture.hafasResponse("locmatch_innsbruck")),
            .init(urlSuffix: Self.gate, bodyContains: "\"TripSearch\"", response: try Fixture.hafasResponse("tripsearch_innsbruck_wien_hbf")),
            .init(urlSuffix: Self.gate, bodyContains: "\"StationBoard\"", response: try Fixture.hafasResponse("stationboard_dep_innsbruck_hbf")),
            .init(urlSuffix: Self.gate, bodyContains: "\"JourneyDetails\"", response: try Fixture.hafasResponse("journeydetails_rjx133_koralm_polyline")),
            .init(urlSuffix: Self.gate, bodyContains: "\"Reconstruction\"", response: try Fixture.hafasResponse("reconstruction_innsbruck_lech_outReconL")),
        ])
        let (client, _) = HafasClient.testClient(t, clock: clock)
        let a = try await client.locations("Innsbruck", types: .all, maxResults: 8)
        let b = try await client.locations("innsbruck ", types: .all, maxResults: 8)
        XCTAssertEqual(a, b)
        XCTAssertEqual(t.recorded.count, 1, "LocMatch cached (normalized query)")

        _ = try await client.journeys(Self.query())
        _ = try await client.journeys(Self.query())
        XCTAssertEqual(t.recorded.count, 2, "identical TripSearch within 30 s is de-duplicated")
        clock.advance(31)
        _ = try await client.journeys(Self.query())
        XCTAssertEqual(t.recorded.count, 3)

        let bq = BoardQuery(station: Self.ibk, date: Self.start, durationMinutes: 30)
        _ = try await client.board(bq)
        _ = try await client.board(bq)
        XCTAssertEqual(t.recorded.count, 4, "board cached 20 s")
        _ = try await client.trip("jid", includePolyline: true)
        _ = try await client.trip("jid", includePolyline: true)
        XCTAssertEqual(t.recorded.count, 5, "JourneyDetails cached 60 s")
        let r1 = try await client.refresh("¶HKI¶x", includeStopovers: true, includePolyline: false)
        let r2 = try await client.refresh("¶HKI¶x", includeStopovers: true, includePolyline: false)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(t.recorded.count, 7, "Reconstruction is never cached")
        // Requests were spaced by at least 0.3 s (fake sleeper).
        XCTAssertTrue(clock.sleeps.allSatisfy { $0 <= 0.3 + 1e-5 }, "\(clock.sleeps)")
    }

    func testRefreshBatchAndOtherMethodsDecode() async throws {
        let t = FixtureTransport(routes: [
            .init(urlSuffix: Self.gate, bodyContains: "\"Reconstruction\"", response: try Fixture.hafasResponse("reconstruction_innsbruck_lech_outReconL")),
            .init(urlSuffix: Self.gate, bodyContains: "\"HimSearch\"", response: try Fixture.hafasResponse("himsearch_disruptions_rail")),
            .init(urlSuffix: Self.gate, bodyContains: "\"LocGeoPos\"", response: try Fixture.hafasResponse("locgeopos_nearby_innsbruck_hbf")),
        ])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        let refreshed = try await client.refresh(batch: ["¶HKI¶a"])
        XCTAssertEqual(refreshed.count, 1)
        if case .success(let j) = refreshed[0] { XCTAssertNotNil(j.refreshToken) } else { XCTFail("\(refreshed)") }
        let remarks = try await client.remarks(RemarksQuery(from: Self.start, to: Self.start.addingTimeInterval(86_400), products: .rail))
        XCTAssertEqual(remarks.count, 15)
        let near = try await client.nearby(GeoPoint(latitude: 47.26304, longitude: 11.40102), maxDistanceMeters: 400, maxResults: 10, products: .all)
        XCTAssertEqual(near.first?.extId, "8100108")
        let geo = try t.jsonBody(2)
        let ring = (((geo["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])?["ring"] as? [String: Any])?["cCrd"] as? [String: Any]
        XCTAssertEqual(ring?["x"] as? Int, 11_401_000, "coordinates rounded to 3 decimals before leaving the device")
        let empty = try await client.locations("   ", types: .all, maxResults: 8)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(t.recorded.count, 3)
    }

    func testThrottleRejectionIsNotABreakerFailure() async throws {
        let clock = FakeClock(Self.start)
        let t = FixtureTransport(routes: [.init(urlSuffix: Self.gate, response: try Fixture.hafasResponse("locmatch_innsbruck"))])
        let health = LiveHealth(clock: clock.closure)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: { _ in }) // never advances: the bucket fills up
        let client = HafasClient(config: .default, transport: t, throttle: throttle, health: health, appVersion: "1", clock: clock.closure,
                                 sleeper: { _ in })
        for i in 0..<40 {
            _ = try await client.locations("Innsbruck \(i)", types: .all, maxResults: 8)
            clock.advance(0.3)
        }
        do {
            _ = try await client.locations("Innsbruck 41", types: .all, maxResults: 8)
            XCTFail("41st request within a minute")
        } catch {
            XCTAssertEqual(error as? LiveError, .rateLimited(.oebbHafas, retryAfter: nil))
        }
        XCTAssertEqual(t.recorded.count, 40)
        let status = await health.status()[.oebbHafas]
        XCTAssertNil(status?.openUntil)
    }
}
