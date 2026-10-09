import XCTest
@testable import KlimaCore

/// Every TripSearch / Reconstruction fixture decodes and matches `FX/golden.json` (SPEC §D2 WP-A 4).
final class HafasDecodeTripSearchTests: XCTestCase {
    /// Golden keys with journeys (TripSearch, paging, Reconstruction, legacy mgate).
    static var journeyScenarios: [String] {
        Fixture.goldenKeys(prefix: "hafas/").filter { key in
            ((try? Fixture.golden(key))?["journeys"]) != nil
        }.map { String($0.dropFirst("hafas/".count)) }
    }

    static func value<T>(_ any: Any?) -> T? { any is NSNull ? nil : any as? T }

    /// Line-name rule of §D2: compare with spaces removed ("RJX19960" ≙ "RJX 19960").
    static func squash(_ s: String?) -> String? { s?.replacingOccurrences(of: " ", with: "") }

    func testScenarioListIsComplete() {
        let s = Self.journeyScenarios
        XCTAssertGreaterThanOrEqual(s.count, 17, "\(s)")
        XCTAssertTrue(s.contains("legacy_mgate141_tripsearch_st_anton_innsbruck"))
        XCTAssertTrue(s.contains("reconstruction_innsbruck_lech_outReconL"))
    }

    func testAllJourneyFixturesMatchGolden() throws {
        for scenario in Self.journeyScenarios {
            let g = try Fixture.golden("hafas/\(scenario)")
            let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/\(scenario).response"))
            let ctx = "[\(scenario)]"
            XCTAssertEqual(page.journeys.count, g["journeyCount"] as? Int, ctx)
            XCTAssertEqual(page.laterContext != nil, (g["hasLaterRef"] as? Bool) ?? false, ctx)
            XCTAssertEqual(page.earlierContext != nil, (g["hasEarlierRef"] as? Bool) ?? false, ctx)
            if let ts: String = Self.value(g["planrtTS"]), let v = Double(ts) {
                XCTAssertEqual(page.realtimeUpdatedAt, Date(timeIntervalSince1970: v), ctx)
            }
            let goldenJourneys = try XCTUnwrap(g["journeys"] as? [[String: Any]], ctx)
            for (i, gj) in goldenJourneys.enumerated() {
                try assertJourney(page.journeys[i], matches: gj, context: "\(ctx) journey \(i)")
            }
            for (i, j) in page.journeys.enumerated() { assertInvariants(j, context: "\(ctx) journey \(i)") }
        }
    }

    private func assertJourney(_ j: Journey, matches g: [String: Any], context ctx: String) throws {
        XCTAssertEqual(j.legs.first?.departure.planned, ISO.date(Self.value(g["plannedDeparture"])), "\(ctx) plannedDeparture")
        XCTAssertEqual(j.legs.last?.arrival.planned, ISO.date(Self.value(g["plannedArrival"])), "\(ctx) plannedArrival")
        XCTAssertEqual(j.departure?.effective, ISO.date(Self.value(g["departure"])), "\(ctx) departure")
        XCTAssertEqual(j.arrival?.effective, ISO.date(Self.value(g["arrival"])), "\(ctx) arrival")
        XCTAssertEqual(j.durationSeconds, Self.value(g["durationSec"]), "\(ctx) durationSec")
        XCTAssertEqual(j.changes, Self.value(g["changes"]) ?? 0, "\(ctx) changes")

        let types = try XCTUnwrap(g["legTypes"] as? [String], ctx)
        XCTAssertEqual(j.legs.count, types.count, "\(ctx) leg count")
        for (leg, type) in zip(j.legs, types) {
            if type == "JNY" { XCTAssertEqual(leg.kind, .ride, "\(ctx) \(leg.id)") } else { XCTAssertNotEqual(leg.kind, .ride, "\(ctx) \(leg.id)") }
        }

        let rides = j.rideLegs
        let lines = (g["rideLines"] as? [Any] ?? []).map { Self.squash(Self.value($0)) }
        XCTAssertEqual(rides.map { Self.squash($0.line?.name) }, lines, "\(ctx) rideLines")
        let cats = (g["rideCategories"] as? [Any] ?? []).map { Self.value($0) as String? }
        XCTAssertEqual(rides.map { $0.line?.categoryShort ?? $0.line?.category }, cats, "\(ctx) rideCategories")
        let cls = (g["rideCls"] as? [Any] ?? []).map { (Self.value($0) as Int?) ?? 0 }
        XCTAssertEqual(rides.map { $0.line?.productClass ?? 0 }, cls, "\(ctx) rideCls")
        let modes = (g["rideModes"] as? [Any] ?? []).map { (Self.value($0) as String?) ?? TransportMode.other.rawValue }
        XCTAssertEqual(rides.map { $0.line?.mode.rawValue ?? "other" }, modes, "\(ctx) rideModes")
        let ops = (g["operators"] as? [Any] ?? []).map { Self.value($0) as String? }
        XCTAssertEqual(rides.map { $0.line?.operatorName }, ops, "\(ctx) operators")

        XCTAssertEqual(rides.first?.departure.platform?.text, Self.value(g["firstDeparturePlatform"]), "\(ctx) platform")
        XCTAssertEqual(rides.first?.departure.plannedPlatform?.text, Self.value(g["firstPlannedDeparturePlatform"]), "\(ctx) planned platform")
        XCTAssertEqual(rides.first?.departure.delaySeconds, Self.value(g["firstDepartureDelaySec"]), "\(ctx) delay")
        let prefix: String = Self.value(g["refreshTokenPrefix"]) ?? ""
        XCTAssertEqual(String((j.refreshToken ?? "").prefix(prefix.count)), prefix, "\(ctx) refresh token")
        if !prefix.isEmpty { XCTAssertTrue(j.refreshToken?.hasPrefix("¶HKI¶") == true, ctx) }
        XCTAssertEqual(rides.map(\.stopovers.count), g["stopoverCounts"] as? [Int], "\(ctx) stopovers")
        XCTAssertEqual(j.legs.map { $0.polyline?.count ?? 0 }, g["polylinePointCounts"] as? [Int], "\(ctx) polylines")
        XCTAssertEqual(j.remarks.count, Self.value(g["remarkCount"]), "\(ctx) remarks")
        XCTAssertEqual(j.isAlternative, (Self.value(g["isAlternative"]) as Bool?) ?? false, "\(ctx) isAlternative")
    }

    /// Ported `client.py selftest` invariants: ride legs chronological, polyline starts at the origin.
    private func assertInvariants(_ j: Journey, context ctx: String) {
        for (a, b) in zip(j.legs, j.legs.dropFirst()) where a.kind == .ride && b.kind == .ride {
            if let arr = a.arrival.planned, let dep = b.departure.planned { XCTAssertLessThanOrEqual(arr, dep, "\(ctx) chronology") }
        }
        for leg in j.legs {
            if let p = leg.polyline?.first, let o = leg.origin.coordinate {
                XCTAssertEqual(p.latitude, o.latitude, accuracy: 0.02, "\(ctx) polyline origin \(leg.id)")
                XCTAssertEqual(p.longitude, o.longitude, accuracy: 0.02, "\(ctx) polyline origin \(leg.id)")
            }
            if let d = leg.departure.planned, let a = leg.arrival.planned { XCTAssertLessThanOrEqual(d, a, "\(ctx) leg order \(leg.id)") }
        }
    }

    // MARK: - Key goldens of §D1.1

    func testStAntonInnsbruck() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_st_anton_innsbruck.response"))
        XCTAssertEqual(page.journeys.count, 4)
        let j = page.journeys[0]
        XCTAssertEqual(j.departure?.planned, ISO.date("2026-10-09T12:33:00+02:00"))
        XCTAssertEqual(j.arrival?.planned, ISO.date("2026-10-09T13:43:00+02:00"))
        XCTAssertEqual(j.durationSeconds, 4200)
        XCTAssertEqual(j.changes, 0)
        let ride = try XCTUnwrap(j.rideLegs.first)
        XCTAssertEqual(ride.line?.category, "RJX")
        XCTAssertEqual(ride.line?.productClass, 1)
        XCTAssertEqual(ride.line?.mode, .train)
        XCTAssertEqual(ride.line?.operatorName, "Nahreisezug")
        XCTAssertEqual(ride.line?.admin, "81____")
        XCTAssertEqual(ride.departure.platform, Platform(text: "3", kind: .track))
        XCTAssertFalse(ride.departure.platformChanged)
        XCTAssertEqual(ride.stopovers.count, 4)
        XCTAssertEqual(ride.polyline?.count, 889)
        XCTAssertTrue(j.refreshToken?.hasPrefix("¶HKI¶") == true)
        XCTAssertNotNil(ride.tripID)
        XCTAssertEqual(ride.stopovers.first?.location.extId, j.origin?.extId)
        XCTAssertEqual(ride.stopovers.last?.location.extId, j.destination?.extId)
        // Stopover indices ascend and match the leg boundaries.
        let idx = ride.stopovers.compactMap(\.index)
        XCTAssertEqual(idx, idx.sorted())
    }

    func testInnsbruckLechBusWalkAndTransfer() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_innsbruck_lech_bus.response"))
        let j = page.journeys[0]
        XCTAssertEqual(j.legs.map(\.kind), [.ride, .walk, .ride])
        XCTAssertEqual(j.rideLegs.map(\.line?.name), ["RJX 19960", "Bus 750"])
        XCTAssertEqual(j.rideLegs[0].line?.fullName, "RJX19960")
        XCTAssertEqual(j.rideLegs[1].line?.operatorName, "Österreichische Postbus Aktiengesellschaft")
        XCTAssertEqual(j.rideLegs[1].line?.lineNumber, "750")
        XCTAssertEqual(j.rideLegs[1].line?.mode, .bus)
        XCTAssertEqual(j.durationSeconds, 8160)
        XCTAssertEqual(j.changes, 1)
        XCTAssertEqual(j.rideLegs.map(\.stopovers.count), [4, 10])
        let walk = j.legs[1]
        XCTAssertEqual(walk.walkDistanceMeters, 35)
        XCTAssertEqual(walk.walkDurationSeconds, 60)
        XCTAssertEqual(walk.id, "C-0:001")
        XCTAssertEqual(j.rideLegs[0].direction, "Bregenz")
        XCTAssertEqual(j.rideLegs[1].direction, "Lech")
        XCTAssertEqual(j.serviceDays, "nicht täglich")
        XCTAssertNotNil(j.serviceDaysDetail)
        XCTAssertEqual(j.checksum, "829b8c3d_3")
        XCTAssertEqual(j.rideLegs[0].isReachable, true)
        XCTAssertNotNil(j.rideLegs[0].currentPosition)
        // Realtime only where the operator delivers it: the bus has none.
        XCTAssertTrue(j.rideLegs[0].departure.hasRealtime)
        XCTAssertEqual(j.rideLegs[0].departure.prognosis, .reported)
        XCTAssertFalse(j.rideLegs[1].departure.hasRealtime)
    }

    func testWestbahnClass4096() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_wien_westbf_salzburg.response"))
        XCTAssertEqual(page.journeys.count, 8)
        let wb = page.journeys.flatMap(\.rideLegs).compactMap(\.line).filter { $0.categoryShort == "WB" }
        XCTAssertFalse(wb.isEmpty)
        XCTAssertTrue(wb.allSatisfy { $0.productClass == 4096 && $0.mode == .train && $0.product == .westbahn })
        // WESTbahn connections carry no shop link.
        for j in page.journeys where j.rideLegs.contains(where: { $0.line?.categoryShort == "WB" }) && j.rideLegs.count == 1 {
            XCTAssertNil(j.shopURL)
        }
    }

    func testKoralmUnder45MinutesWithRealtime() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_graz_klagenfurt_koralm.response"))
        XCTAssertTrue(page.journeys.contains { ($0.durationSeconds ?? .max) <= 45 * 60 })
        XCTAssertEqual(page.journeys[0].durationSeconds, 2460)
        XCTAssertEqual(page.journeys[0].rideLegs.first?.departure.delaySeconds, 180)
    }

    func testPagingContexts() throws {
        let later = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_paging_later_graz_klagenfurt.response"))
        let first = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_graz_klagenfurt_koralm.response"))
        XCTAssertNotNil(first.laterContext)
        XCTAssertNotNil(later.earlierContext)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(later.journeys.first?.departure?.planned), try XCTUnwrap(first.journeys.first?.departure?.planned))
    }

    func testArriveByLastArrivalBeforeRequestedTime() throws {
        let req = try XCTUnwrap(try Fixture.json("hafas/tripsearch_arrive_by_innsbruck_wien.request") as? [String: Any])
        let svc = try XCTUnwrap(((req["body"] as? [String: Any])?["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        XCTAssertEqual(svc["outFrwd"] as? Bool, false)
        let latest = try XCTUnwrap(HafasTime.date(base: svc["outDate"] as! String, time: svc["outTime"] as! String, tzOffsetMinutes: nil))
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_arrive_by_innsbruck_wien.response"))
        for j in page.journeys { XCTAssertLessThanOrEqual(try XCTUnwrap(j.arrival?.planned), latest) }
    }

    func testViaLinzPassesLinz() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_via_linz_maxchg0_rail.response"))
        for j in page.journeys {
            XCTAssertTrue(j.passes(Location.station(extId: "8100013", name: "Linz/Donau Hbf")), "journey \(j.id) does not pass Linz")
            XCTAssertFalse(j.passes(Location.station(extId: "8100173", name: "Graz Hbf")))
            XCTAssertEqual(j.changes, 0)
        }
    }

    func testLegacyMgateDecodesToTheSameShape() throws {
        let legacy = try HafasCodec.journeyPage(from: Fixture.data("hafas/legacy_mgate141_tripsearch_st_anton_innsbruck.response"))
        let gate = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_st_anton_innsbruck.response"))
        XCTAssertFalse(legacy.journeys.isEmpty)
        let l = legacy.journeys[0], g = gate.journeys[0]
        XCTAssertEqual(l.legs.map(\.kind), g.legs.map(\.kind))
        XCTAssertEqual(l.rideLegs.first?.line?.category, "RJX")
        XCTAssertEqual(l.rideLegs.first?.departure.plannedPlatform?.kind, .track)
        XCTAssertTrue(l.refreshToken?.hasPrefix("¶HKI¶") == true)
        XCTAssertNil(l.shopURL)
    }

    func testReconstructionGolden() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/reconstruction_innsbruck_lech_outReconL.response"))
        let g = try Fixture.golden("hafas/reconstruction_innsbruck_lech_outReconL")
        XCTAssertEqual(page.journeys.count, 1)
        XCTAssertEqual(page.journeys[0].shopURL?.absoluteString, g["shopLink"] as? String)
    }

    func testBatchErrorsAreIsolated() throws {
        let results = try HafasCodec.journeyPages(from: Fixture.data("hafas/batch_edge_cases_errors.response"))
        XCTAssertEqual(results.count, 4)
        let errors = results.map { r -> LiveError? in if case .failure(let e) = r { return e }; return nil }
        let golden = try XCTUnwrap(try Fixture.golden("hafas/batch_edge_cases_errors")["svcErrTxtOut"] as? [String])
        XCTAssertEqual(errors[0], .hafas(code: "LOCATION", message: golden[0]))
        XCTAssertEqual(errors[1], .noConnection)
        XCTAssertEqual(errors[2], .hafas(code: "PARAMETER", message: golden[2]))
        XCTAssertEqual(errors[3], .hafas(code: "H9381", message: golden[3]))
        XCTAssertEqual(try Fixture.golden("hafas/batch_edge_cases_errors")["svcErr"] as? [String], ["LOCATION", "H890", "PARAMETER", "H9381"])
    }

    /// Synthetic cancellations (never observed live, SPEC R9).
    func testSyntheticCancellation() throws {
        let json = """
        {"ver":"1.88","err":"OK","svcResL":[{"meth":"TripSearch","err":"OK","res":{"common":{
          "locL":[{"lid":"A=1@L=8100108@","type":"S","name":"Innsbruck Hbf","extId":"8100108","crd":{"x":11401019,"y":47263043}},
                  {"lid":"A=1@L=8100013@","type":"S","name":"Linz/Donau Hbf","extId":"8100013","crd":{"x":14291425,"y":48290206}}],
          "prodL":[{"name":"RJX 763","cls":1,"prodCtx":{"catOut":"RJX     ","catOutS":"RJX","num":"763"}}]},
          "outConL":[{"cid":"C-0","date":"20261009","dur":"021500","chg":0,
            "dep":{"locX":0,"dTimeS":"100000"},"arr":{"locX":1,"aTimeS":"121500"},
            "secL":[{"type":"JNY","dep":{"locX":0,"dTimeS":"100000","dTZOffset":120,"dCncl":true,"dPlatfCh":true,
                                        "dPltfS":{"type":"PL","txt":"5"},"dPltfR":{"type":"PL","txt":"7"}},
                     "arr":{"locX":1,"aTimeS":"121500","aTZOffset":120,"aCncl":true},
                     "jny":{"jid":"x","prodX":0,"isPartCncl":true,"stopL":[]}},
                    {"type":"WALK","hide":true,"dep":{"locX":1,"dTimeS":"121500"},"arr":{"locX":1,"aTimeS":"121600"}},
                    {"type":"TRSF","dep":{"locX":1,"dTimeS":"121600"},"arr":{"locX":1,"aTimeS":"122000"}},
                    {"type":"WALK","dep":{"locX":1,"dTimeS":"122000"},"arr":{"locX":1,"aTimeS":"122500"},"chg":{"durS":"000500"}}]}]}}]}
        """
        let page = try HafasCodec.journeyPage(from: Data(json.utf8))
        let j = try XCTUnwrap(page.journeys.first)
        XCTAssertEqual(j.legs.map(\.kind), [.ride, .transfer, .transfer], "hidden non-JNY sections are dropped")
        let ride = j.legs[0]
        XCTAssertTrue(ride.isCancelled)
        XCTAssertTrue(ride.isPartiallyCancelled)
        XCTAssertTrue(ride.departure.isCancelled)
        XCTAssertTrue(ride.departure.platformChanged)
        XCTAssertEqual(ride.departure.platform?.text, "7")
        XCTAssertNil(ride.departure.realtime, "no dTimeR → no realtime")
        XCTAssertEqual(ride.line?.name, "RJX 763")
        XCTAssertEqual(j.legs[2].walkDurationSeconds, 300)
        XCTAssertEqual(j.legs[1].id, "C-0-2")
    }

    func testTolerantDecodingOfDriftedTypes() throws {
        // cls as String, crd as String, unknown keys, out-of-range indices: decodes, never crashes.
        let json = """
        {"ver":"1.88","err":"OK","unknownTop":1,"svcResL":[{"meth":"TripSearch","err":"OK","res":{"common":{
          "locL":[{"lid":"A=1@L=1@","type":"S","name":"A","crd":"bogus"}],
          "prodL":[{"name":"S 4","nameS":"S 4","cls":"32","prodCtx":{"line":"4","catOutS":"s","catOut":"S       "}}]},
          "outConL":[{"cid":"C-0","date":"20261009","dur":"001000","chg":"0",
            "secL":[{"type":"JNY","dep":{"locX":0,"dTimeS":"100000"},"arr":{"locX":7,"aTimeS":"101000"},
                     "jny":{"jid":"j","prodX":0,"dirL":[{"dirX":9}],"newField":{"a":[1,2]}}}]}]}}]}
        """
        let page = try HafasCodec.journeyPage(from: Data(json.utf8))
        let leg = try XCTUnwrap(page.journeys.first?.legs.first)
        XCTAssertEqual(leg.line?.productClass, 32)
        XCTAssertEqual(leg.line?.mode, .sBahn)
        XCTAssertEqual(leg.line?.name, "S 4")
        XCTAssertNil(leg.origin.coordinate)
        XCTAssertEqual(leg.destination.name, "Unbekannter Halt")
        XCTAssertNil(leg.direction)
        XCTAssertEqual(page.journeys[0].changes, 0)
    }

    func testEmptyResultIsNoConnection() {
        let json = #"{"ver":"1.88","err":"OK","svcResL":[{"meth":"TripSearch","err":"OK","res":{"common":{},"outConL":[]}}]}"#
        XCTAssertThrowsError(try HafasCodec.journeyPage(from: Data(json.utf8))) { XCTAssertEqual($0 as? LiveError, .noConnection) }
    }
}

final class ShopLinkDecodeTests: XCTestCase {
    func testShopLinkGolden() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_getTariff_true_innsbruck_wien.response"))
        let g = try Fixture.golden("hafas/tripsearch_getTariff_true_innsbruck_wien")
        let link = try XCTUnwrap(g["shopLink"] as? String)
        XCTAssertEqual(page.journeys.first?.shopURL?.absoluteString, link)
        XCTAssertEqual(link, "https://shop.oebbtickets.at/de/ticket?cref=scotty&connectionDatetimeDeparture=2026-10-09T13:58&connectionDatetimeArrival=2026-10-09T18:32&connectionOrigEva=8100108&connectionDestEva=8103000&stationOrigName=Innsbruck%20Hbf&stationDestName=Wien%20Hbf%20(Bahnsteige%203-12)")
    }

    func testClickoutFallbackAndMissing() throws {
        XCTAssertEqual(HafasCodec.shopURL(nil), nil)
        let json = #"{"clickout":"https://shop.oebbtickets.at/de/ticket?x=1"}"#
        let trf = try JSONDecoder().decode(HafasRawTariffResult.self, from: Data(json.utf8))
        XCTAssertEqual(HafasCodec.shopURL(trf)?.absoluteString, "https://shop.oebbtickets.at/de/ticket?x=1")
    }
}

/// Envelope-level goldens for every `hafas/*` key (top `err`, per-service `err`/`meth`) and the error mapping of §A3.2.
final class HafasEnvelopeGoldenTests: XCTestCase {
    func testEveryHafasGoldenEnvelope() throws {
        let keys = Fixture.goldenKeys(prefix: "hafas/")
        XCTAssertGreaterThanOrEqual(keys.count, 34)
        for key in keys {
            let g = try Fixture.golden(key)
            let scenario = String(key.dropFirst("hafas/".count))
            let raw = try HafasCodec.decodeRaw(Fixture.data("hafas/\(scenario).response"))
            XCTAssertEqual(raw.err, g["topErr"] as? String, key)
            XCTAssertEqual((raw.svcResL ?? []).map { $0.err ?? "" }, g["svcErr"] as? [String], key)
            XCTAssertEqual((raw.svcResL ?? []).map { $0.meth ?? "" }, g["meth"] as? [String], key)
            // Request fixture exists next to every response and is a valid envelope.
            let req = try XCTUnwrap(try Fixture.json("hafas/\(scenario).request") as? [String: Any], key)
            XCTAssertNotNil((req["body"] as? [String: Any])?["svcReqL"], key)
        }
    }

    func testTopLevelErrorMapping() throws {
        let auth = try Fixture.golden("hafas/error_auth_invalid_aid")
        XCTAssertEqual(auth["errTxt"] as? String, "HCI Core: Authorization fail")
        XCTAssertEqual(HafasCodec.envelopeError(try Fixture.data("hafas/error_auth_invalid_aid.response")), .blocked(.oebbHafas))
        XCTAssertEqual(HafasCodec.envelopeError(try Fixture.data("hafas/error_auth_invalid_aid.response"), provider: .vaoTariff), .blocked(.vaoTariff))
        for scenario in ["error_parse_invalid_enum_rtmode", "error_parse_unknown_field", "error_parse_reconstruction_ctxRecon_v188"] {
            let g = try Fixture.golden("hafas/\(scenario)")
            XCTAssertEqual(g["topErr"] as? String, "PARSE", scenario)
            XCTAssertEqual(HafasCodec.envelopeError(try Fixture.data("hafas/\(scenario).response")), .decoding(try XCTUnwrap(g["errTxt"] as? String)), scenario)
        }
        XCTAssertNil(HafasCodec.envelopeError(try Fixture.data("hafas/serverinfo.response")))
        XCTAssertNil(HafasCodec.envelopeError(try Fixture.data("hafas/batch_edge_cases_errors.response")), "service errors are not envelope errors")
        XCTAssertEqual(HafasCodec.serviceError(try Fixture.data("hafas/batch_edge_cases_errors.response"), serviceIndex: 1), .noConnection)
        let hamm = #"{"ver":"1.88","err":"HAMM","hammError":"client.v must be int"}"#
        XCTAssertEqual(HafasCodec.envelopeError(Data(hamm.utf8)), .decoding("client.v must be int"))
        let other = #"{"ver":"1.88","err":"FAIL","errTxt":"x"}"#
        XCTAssertEqual(HafasCodec.envelopeError(Data(other.utf8)), .hafas(code: "FAIL", message: "x"))
        guard case .decoding? = HafasCodec.envelopeError(Data("<html>".utf8)) else { return XCTFail("non-JSON → .decoding") }
        // svc H9380 / H9381 keep the German errTxtOut for „Start und Ziel sind zu nah beieinander.“
        XCTAssertEqual(HafasCodec.serviceError(code: "H9380", errTxtOut: "zu nah", errTxt: "x"), .hafas(code: "H9380", message: "zu nah"))
        XCTAssertEqual(HafasCodec.serviceError(code: "FOO", errTxtOut: nil, errTxt: "fallback"), .hafas(code: "FOO", message: "fallback"))
    }
}
