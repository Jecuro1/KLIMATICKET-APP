import XCTest
@testable import KlimaCore

/// Buffer, dedup, ranking, timetable, log and valuation of the trip detection.
final class DetectionSupportTests: XCTestCase {
    typealias F = DetectFixtures

    private func candidate(from: Station = F.innsbruck, to: Station = F.landeck, dep: String = "08:05", arr: String = "09:10",
                           fromDistance: Double = 40, toDistance: Double = 40, speed: Double = 58) -> DetectedCandidate {
        let a = StationMatch(station: from, distanceMeters: fromDistance), b = StationMatch(station: to, distanceMeters: toDistance)
        let km = F.km(from, to)
        let evidence = CandidateEvidence(source: .background, from: a, to: b, straightKm: km, averageSpeedKmh: speed, dwellAtStart: 900, dwellAtEnd: 900,
                                         knownRelation: F.relations.contains(PairHistory.key(from.id, to.id)))
        return DetectedCandidate(id: UUID(), source: .background, from: a, to: b, via: [], departure: F.nov12(dep), arrival: F.nov12(arr),
                                 straightKm: km, pathKm: nil, averageSpeedKmh: speed, dwellAtStart: 900, dwellAtEnd: 900, mode: .train,
                                 evidence: evidence, rank: CandidateRanking.rank(evidence), sketch: RouteSketch.make(from: from.location, to: to.location, track: []),
                                 evidenceStart: F.nov12("07:50"), evidenceEnd: F.nov12(arr))
    }

    // MARK: Rolling buffer

    func testBufferDropsEverythingOlderThan36Hours() {
        let now = F.nov12("12:00")
        var buffer = RollingPointBuffer()
        buffer.append(CoarsePoint(time: now.addingTimeInterval(-37 * 3600), at: F.innsbruck.location), now: now)
        buffer.append(CoarsePoint(time: now.addingTimeInterval(-35 * 3600), at: F.innsbruck.location), now: now)
        buffer.upsert(F.visit(F.hall, arrival: now.addingTimeInterval(-40 * 3600), departure: now.addingTimeInterval(-39 * 3600)), now: now)
        buffer.upsert(F.visit(F.hall, arrival: now.addingTimeInterval(-3 * 3600), departure: nil), now: now)
        XCTAssertEqual(buffer.points.count, 1)
        XCTAssertEqual(buffer.visits.count, 1)
        // An hour later the 35-hour-old point is gone as well.
        buffer.prune(now: now.addingTimeInterval(3600 + 1))
        XCTAssertTrue(buffer.points.isEmpty)
        XCTAssertEqual(buffer.visits.count, 1)
        buffer.prune(now: now.addingTimeInterval(40 * 3600))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testBufferKeepsOrderIgnoresDuplicatesAndFuturePoints() {
        let now = F.nov12("12:00")
        var buffer = RollingPointBuffer()
        let a = CoarsePoint(time: now.addingTimeInterval(-600), at: F.innsbruck.location)
        let b = CoarsePoint(time: now.addingTimeInterval(-1200), at: F.hall.location)
        buffer.append(a, now: now)
        buffer.append(a, now: now)
        buffer.append(b, now: now)
        buffer.append(CoarsePoint(time: now.addingTimeInterval(7200), at: F.hall.location), now: now)   // from the future: clock error
        buffer.append(CoarsePoint(time: now, latitude: .nan, longitude: 1), now: now)
        XCTAssertEqual(buffer.points.map(\.time), [b.time, a.time])
    }

    func testBufferCapsTheNumberOfPoints() {
        let now = F.nov12("12:00")
        var buffer = RollingPointBuffer()
        for i in 0..<(RollingPointBuffer.maxPoints + 50) {
            buffer.append(CoarsePoint(time: now.addingTimeInterval(-Double(RollingPointBuffer.maxPoints + 50 - i)), at: F.innsbruck.location), now: now)
        }
        XCTAssertEqual(buffer.points.count, RollingPointBuffer.maxPoints)
        XCTAssertEqual(buffer.points.last?.time, now.addingTimeInterval(-1))
    }

    /// iOS (and the region exit) report a visit twice: first arrival, then departure.
    func testBufferCompletesAnOpenVisit() {
        let now = F.nov12("12:00")
        var buffer = RollingPointBuffer()
        let arrival = F.nov12("10:00")
        buffer.upsert(F.visit(F.innsbruck, arrival: arrival, departure: nil, observed: F.nov12("10:10")), now: now)
        buffer.upsert(F.visit(F.innsbruck, offset: 60, arrival: arrival, departure: F.nov12("10:40"), observed: F.nov12("10:41")), now: now)
        XCTAssertEqual(buffer.visits.count, 1)
        XCTAssertEqual(buffer.visits[0].arrival, arrival)
        XCTAssertEqual(buffer.visits[0].departure, F.nov12("10:40"))
        // A region exit closes the open visit of that station.
        buffer.upsert(F.visit(F.hall, arrival: F.nov12("11:00"), departure: nil), now: now)
        buffer.closeOpenVisit(near: F.hall.location, departure: F.nov12("11:20"), now: now)
        XCTAssertEqual(buffer.visits.last?.departure, F.nov12("11:20"))
    }

    func testRemovingEvidenceKeepsTheOpenDestinationVisit() {
        let now = F.nov12("12:00")
        var buffer = RollingPointBuffer()
        buffer.append(CoarsePoint(time: F.nov12("08:30"), at: F.telfs.location), now: now)
        buffer.append(CoarsePoint(time: F.nov12("11:30"), at: F.hall.location), now: now)
        buffer.upsert(F.visit(F.innsbruck, arrival: F.nov12("07:50"), departure: F.nov12("08:05")), now: now)
        buffer.upsert(F.visit(F.landeck, arrival: F.nov12("09:10"), departure: nil, observed: F.nov12("09:10")), now: now)
        buffer.remove(from: F.nov12("07:50"), to: F.nov12("09:10"))
        XCTAssertEqual(buffer.points.map(\.time), [F.nov12("11:30")])
        XCTAssertEqual(buffer.visits.count, 1, "the person may still be at the destination")
        XCTAssertEqual(buffer.visits[0].arrival, F.nov12("09:10"))
    }

    func testBufferRemoveAllAndTolerantDecoding() throws {
        let now = F.nov12("12:00")
        var buffer = RollingPointBuffer()
        buffer.append(CoarsePoint(time: now.addingTimeInterval(-60), at: F.hall.location), now: now)
        buffer.upsert(F.visit(F.hall, arrival: now.addingTimeInterval(-600), departure: nil), now: now)
        let data = try JSONEncoder().encode(buffer)
        XCTAssertEqual(try JSONDecoder().decode(RollingPointBuffer.self, from: data), buffer)
        XCTAssertEqual(try JSONDecoder().decode(RollingPointBuffer.self, from: Data("{}".utf8)), RollingPointBuffer())
        XCTAssertEqual(try JSONDecoder().decode(RollingPointBuffer.self, from: Data(#"{"points":"nonsense"}"#.utf8)), RollingPointBuffer())
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
    }

    // MARK: Dedup with entered rides

    func testEnteredRideCoversTheDetectedOne() {
        let ride = ExistingRide(date: F.nov12("18:30"), fromStationID: F.innsbruck.id, toStationID: F.landeck.id, fromName: "Innsbruck Hbf", toName: "Landeck-Zams")
        let split = CandidateDedup.split([candidate()], rides: [ride])
        XCTAssertTrue(split.fresh.isEmpty, "entered later the same day: the time of entry is not the time of the ride")
        XCTAssertEqual(split.covered.count, 1)
    }

    func testEnteredRideMatchedByNameWhenTheIDsDiffer() {
        let ride = ExistingRide(date: F.nov12("08:00"), fromName: "Innsbruck Hbf", toName: "Landeck-Zams")
        XCTAssertTrue(CandidateDedup.split([candidate()], rides: [ride]).fresh.isEmpty)
    }

    func testOtherDayOrOtherPairOrOtherDirectionIsNotCovered() {
        let ride = ExistingRide(date: F.nov12("08:00"), fromStationID: F.innsbruck.id, toStationID: F.landeck.id, fromName: "", toName: "")
        let yesterday = ExistingRide(date: F.date("2026-11-11T08:00:00+01:00"), fromStationID: F.innsbruck.id, toStationID: F.landeck.id, fromName: "", toName: "")
        let otherPair = ExistingRide(date: F.nov12("08:00"), fromStationID: F.innsbruck.id, toStationID: F.hall.id, fromName: "Innsbruck Hbf", toName: "Hall in Tirol")
        XCTAssertEqual(CandidateDedup.split([candidate()], rides: [yesterday, otherPair]).fresh.count, 1)
        // The way back is a ride of its own.
        let back = candidate(from: F.landeck, to: F.innsbruck, dep: "17:20", arr: "18:25")
        XCTAssertEqual(CandidateDedup.split([back], rides: [ride]).fresh.count, 1)
    }

    /// "Hin & Retour" is one entry for both directions; an entry without it covers one ride only.
    func testRoundTripCoversBothDirectionsAndOneEntryOnlyOneRide() {
        let there = candidate(), back = candidate(from: F.landeck, to: F.innsbruck, dep: "17:20", arr: "18:25")
        let round = ExistingRide(date: F.nov12("08:00"), fromStationID: F.innsbruck.id, toStationID: F.landeck.id, fromName: "", toName: "", isRoundTrip: true)
        XCTAssertTrue(CandidateDedup.split([there, back], rides: [round]).fresh.isEmpty)
        let single = ExistingRide(date: F.nov12("08:00"), fromStationID: F.innsbruck.id, toStationID: F.landeck.id, fromName: "", toName: "")
        let twiceThere = [there, candidate(dep: "17:20", arr: "18:25")]
        let split = CandidateDedup.split(twiceThere, rides: [single])
        XCTAssertEqual(split.covered.count, 1)
        XCTAssertEqual(split.fresh.count, 1, "a commuter who rides A → B twice and entered one of them still gets the other proposed")
    }

    func testRideAcrossMidnightIsCoveredByAnEntryOnEitherDay() {
        let late = candidate(from: F.wienHbf, to: F.stPoelten, dep: "23:25", arr: "23:59")
        var c = late
        c.arrival = F.date("2026-11-13T00:20:00+01:00")
        let nextDay = ExistingRide(date: F.date("2026-11-13T00:05:00+01:00"), fromStationID: F.wienHbf.id, toStationID: F.stPoelten.id, fromName: "", toName: "")
        XCTAssertTrue(CandidateDedup.split([c], rides: [nextDay]).fresh.isEmpty)
        let nextEvening = ExistingRide(date: F.date("2026-11-13T21:00:00+01:00"), fromStationID: F.wienHbf.id, toStationID: F.stPoelten.id, fromName: "", toName: "")
        XCTAssertEqual(CandidateDedup.split([c], rides: [nextEvening]).fresh.count, 1, "an entry of the evening after the arrival is another ride")
    }

    // MARK: Inbox reconcile

    func testReDetectionOfTheSameRideIsSkipped() {
        let known = KnownCandidate(fromStationID: F.innsbruck.id, toStationID: F.landeck.id, departure: F.nov12("08:03"), arrival: F.nov12("09:12"), isPending: true)
        XCTAssertEqual(CandidateDedup.reconcile(candidate(), known: [known]), .skip)
        let decided = KnownCandidate(fromStationID: F.innsbruck.id, toStationID: F.landeck.id, departure: F.nov12("08:03"), arrival: F.nov12("09:12"), isPending: false)
        XCTAssertEqual(CandidateDedup.reconcile(candidate(), known: [decided]), .skip, "a dismissed ride does not come back")
    }

    /// The train stopped at Imst for four minutes (a pending A → Imst) and went on: A → Landeck replaces it.
    func testLongerRideReplacesAPendingShorterOne() {
        let shorter = KnownCandidate(fromStationID: F.innsbruck.id, toStationID: F.imst.id, departure: F.nov12("08:05"), arrival: F.nov12("08:50"), isPending: true)
        XCTAssertEqual(CandidateDedup.reconcile(candidate(), known: [shorter]), .replace([0]))
        var decided = shorter
        decided.isPending = false
        XCTAssertEqual(CandidateDedup.reconcile(candidate(), known: [decided]), .skip, "a decided ride is never replaced")
    }

    func testUnrelatedKnownCandidateDoesNotMatter() {
        let other = KnownCandidate(fromStationID: F.wienHbf.id, toStationID: F.stPoelten.id, departure: F.nov12("08:05"), arrival: F.nov12("09:00"), isPending: true)
        let evening = KnownCandidate(fromStationID: F.innsbruck.id, toStationID: F.landeck.id, departure: F.nov12("17:00"), arrival: F.nov12("18:00"), isPending: true)
        XCTAssertEqual(CandidateDedup.reconcile(candidate(), known: [other, evening]), .insert)
    }

    // MARK: Ranking

    func testRankingScoresAreStableAndExplained() {
        let platform = candidate()
        XCTAssertEqual(platform.rank.score, 0.30 + 0.15 + 0.15 + 0.15 + 0.10 + 0.10, accuracy: 0.0001)
        XCTAssertEqual(platform.rank.confidence, .wahrscheinlich)
        XCTAssertEqual(platform.rank.positives.count, 6)
        XCTAssertTrue(platform.rank.negatives.isEmpty)
        for reason in platform.rank.reasons { XCTAssertFalse(reason.text.isEmpty) }
    }

    func testSicherNeedsTheTimetableAndPlatformNearRailStations() {
        let a = StationMatch(station: F.innsbruck, distanceMeters: 60), b = StationMatch(station: F.landeck, distanceMeters: 80)
        func rank(_ verdict: TimetableVerdict, _ b: StationMatch = b) -> CandidateRank {
            CandidateRanking.rank(CandidateEvidence(source: .background, from: a, to: b, straightKm: 63, averageSpeedKmh: 58, knownRelation: true,
                                                    timetable: verdict))
        }
        let connection = TimetableConnection(departure: F.nov12("08:07"), arrival: F.nov12("09:12"), line: "REX 5429")
        XCTAssertEqual(rank(.unavailable).confidence, .wahrscheinlich)
        XCTAssertEqual(rank(.confirmed(connection)).confidence, .sicher)
        XCTAssertFalse(rank(.confirmed(connection)).carNotExcluded, "the card then says: Auto unwahrscheinlich")
        XCTAssertTrue(rank(.unavailable).carNotExcluded)
        XCTAssertLessThan(rank(.noMatch).score, rank(.unavailable).score)
        XCTAssertTrue(rank(.noMatch).negatives.contains { $0.code == "timetable.none" })
        // At 280 m from the station the timetable still confirms, but the label stays "wahrscheinlich".
        let farther = StationMatch(station: F.landeck, distanceMeters: 280)
        XCTAssertEqual(rank(.confirmed(connection), farther).confidence, .wahrscheinlich)
    }

    func testTimetableAnswerReRanksACandidate() {
        let base = candidate(fromDistance: 60, toDistance: 80)
        XCTAssertEqual(base.confidence, .wahrscheinlich)
        let connection = TimetableConnection(departure: F.nov12("08:07"), arrival: F.nov12("09:12"), line: "REX 5429")
        let confirmed = base.ranked(with: .confirmed(connection))
        XCTAssertEqual(confirmed.confidence, .sicher)
        XCTAssertEqual(confirmed.rank.score, base.rank.score + 0.35, accuracy: 0.0001)
        XCTAssertEqual(confirmed.id, base.id)
        XCTAssertLessThan(base.ranked(with: .noMatch).rank.score, base.rank.score)
        XCTAssertEqual(base.ranked(with: .unavailable).rank.score, base.rank.score, accuracy: 0.0001)
    }

    func testConfidenceOrderingAndLabels() {
        XCTAssertLessThan(DetectionConfidence.vielleicht, .wahrscheinlich)
        XCTAssertLessThan(DetectionConfidence.wahrscheinlich, .sicher)
        XCTAssertEqual(DetectionConfidence.sicher.label, "Sicher")
        XCTAssertEqual(DetectionConfidence.vielleicht.label, "Vielleicht")
    }

    func testDismissalsAreCappedAndAcceptancesHelp() {
        let a = StationMatch(station: F.innsbruck, distanceMeters: 60), b = StationMatch(station: F.landeck, distanceMeters: 80)
        func score(_ h: PairHistory) -> Double {
            CandidateRanking.rank(CandidateEvidence(source: .background, from: a, to: b, straightKm: 63, averageSpeedKmh: 58, knownRelation: true, history: h)).score
        }
        let key = PairHistory.key(F.innsbruck.id, F.landeck.id)
        let base = score(.empty)
        XCTAssertEqual(score(PairHistory(dismissed: [key: 1])), base - 0.2, accuracy: 0.001)
        XCTAssertEqual(score(PairHistory(dismissed: [key: 3])), base - 0.6, accuracy: 0.001)
        XCTAssertEqual(score(PairHistory(dismissed: [key: 9])), base - 0.6, accuracy: 0.001, "capped")
        XCTAssertEqual(score(PairHistory(accepted: [key: 4])), base + 0.1, accuracy: 0.001)
    }

    // MARK: Timetable

    func testTimetableVerdict() {
        let dep = F.nov12("08:05"), arr = F.nov12("09:10")
        let good = TimetableConnection(departure: F.nov12("08:07"), arrival: F.nov12("09:12"), line: "REX 5429")
        let better = TimetableConnection(departure: F.nov12("08:05"), arrival: F.nov12("09:10"), line: "RJX 662")
        let late = TimetableConnection(departure: F.nov12("08:40"), arrival: F.nov12("09:45"))
        XCTAssertEqual(TimetableConfirmation.verdict(departure: dep, arrival: arr, connections: [late, good]), .confirmed(good))
        XCTAssertEqual(TimetableConfirmation.verdict(departure: dep, arrival: arr, connections: [good, better]), .confirmed(better))
        XCTAssertEqual(TimetableConfirmation.verdict(departure: dep, arrival: arr, connections: [late]), .noMatch)
        XCTAssertEqual(TimetableConfirmation.verdict(departure: dep, arrival: arr, connections: []), .noMatch)
        XCTAssertEqual(TimetableConfirmation.verdict(departure: dep, arrival: arr, connections: nil), .unavailable)
        XCTAssertEqual(good.summary, "REX 5429 fährt um 08:07")
        XCTAssertEqual(late.summary, "Zug um 08:40 zwischen beiden Bahnhöfen")
    }

    // MARK: Log

    func testLogIsDeduplicatedPrunedAndCarriesNoCoordinates() {
        let now = F.nov12("12:00")
        var log = DetectionLog()
        let rejection = DetectionRejection(reason: .tooSlow(kmh: 5), departure: F.nov12("10:00"), arrival: F.nov12("11:36"),
                                           fromName: F.innsbruck.name, toName: F.hall.name, straightKm: 8, averageSpeedKmh: 5)
        let outcome = DetectionOutcome(candidates: [], rejections: [rejection])
        log.record(outcome, at: now)
        log.record(outcome, at: now.addingTimeInterval(60))   // the next run sees the same movement
        XCTAssertEqual(log.entries.count, 1)
        let entry = log.entries[0]
        XCTAssertEqual(entry.kind, .rejected)
        XCTAssertEqual(entry.title, "Innsbruck Hauptbahnhof → Hall in Tirol")
        XCTAssertTrue(entry.detail.contains("zu langsam"), entry.detail)
        XCTAssertFalse(entry.detail.contains("47."), "no coordinates")

        log.add(.proposed(candidate(), at: now), now: now)
        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries[0].kind, .proposed)
        XCTAssertTrue(log.entries[0].detail.hasPrefix("Vorgeschlagen (wahrscheinlich)"), log.entries[0].detail)
        XCTAssertTrue(log.entries[0].detail.contains("Auto nicht ausgeschlossen"))

        log.prune(now: now.addingTimeInterval(15 * 86_400))
        XCTAssertTrue(log.entries.isEmpty)
        for i in 0..<(DetectionLog.maxEntries + 20) {
            log.add(DetectionLogEntry(loggedAt: now, kind: .info, title: "Eintrag \(i)", detail: "x"), now: now)
        }
        XCTAssertEqual(log.entries.count, DetectionLog.maxEntries)
    }

    func testRejectionTextsAreGermanAndPrecise() {
        let r = DetectionRejection(reason: .noStationAtEnd(nearestKm: 1.84), departure: .distantPast, arrival: .distantPast, fromName: "A", toName: nil,
                                   straightKm: 12, averageSpeedKmh: 70)
        XCTAssertEqual(r.text, "Ziel ohne Haltestelle in 500 m (nächste: 1,8 km)")
        XCTAssertEqual(DetectionRejection(reason: .tooShort(km: 3.3), departure: .distantPast, arrival: .distantPast, straightKm: 3.3).text, "Luftlinie nur 3,3 km (ab 5 km)")
    }

    // MARK: Valuation = the trip editor's numbers

    func testConfirmedRideHasTheNumbersOfAManuallyEnteredOne() {
        let estimator = FareEstimator(catalog: PricingFixtures.catalog(), relations: PricingFixtures.relations)
        let from = PricingFixtures.innsbruck, to = PricingFixtures.landeck
        let date = F.nov12("08:05")
        let facts = CandidateValuation.facts(from: from, to: to, mode: .train, date: date, estimator: estimator, travelClass: .second, discount: .none)
        // What the trip editor computes for the same inputs (TripEditorModel.recompute).
        let manual = estimator.estimate(from: from, via: [], to: to, mode: .train, travelClass: .second, discount: .none, date: date)
        XCTAssertEqual(facts.fareEUR, manual.fareEUR)
        XCTAssertEqual(facts.distanceKm, manual.distanceKm)
        XCTAssertEqual(facts.method, .officialTable)
        XCTAssertEqual(facts.priceSource, .table)
        XCTAssertEqual(facts.states, ["T"])
        XCTAssertGreaterThan(facts.fareEUR, 0)

        let discounted = CandidateValuation.facts(from: from, to: to, mode: .train, date: date, estimator: estimator, travelClass: .first, discount: .vorteilscard)
        XCTAssertEqual(discounted.fareEUR, estimator.estimate(from: from, via: [], to: to, mode: .train, travelClass: .first, discount: .vorteilscard, date: date).fareEUR)
        XCTAssertNotEqual(discounted.fareEUR, facts.fareEUR)
    }

    func testValuationStatesFollowAllStopsSorted() {
        let estimator = FareEstimator(catalog: PricingFixtures.catalog(), relations: PricingFixtures.relations)
        let facts = CandidateValuation.facts(from: PricingFixtures.wienHbf, to: PricingFixtures.salzburg, via: [PricingFixtures.innsbruck],
                                             mode: .train, date: F.nov12("09:00"), estimator: estimator)
        XCTAssertEqual(facts.states, ["S", "T", "W"])
    }

    // MARK: Station matcher

    func testMatcherPrefersARailStationOverANearerBusStop() {
        let near = DetectionGeo.offset(F.imst.location, meters: 250, bearingDegrees: 0)
        // The bus stop is 40 m from the point, the station 250 m.
        let busStop = Station(id: "at:47:bus9", name: "Imst Bahnhofstraße", lat: DetectionGeo.offset(near, meters: 40, bearingDegrees: 90).latitude,
                              lon: DetectionGeo.offset(near, meters: 40, bearingDegrees: 90).longitude, state: "T", kind: .stop, products: PlaceProducts.bus.rawValue)
        let matcher = StationMatcher(lookup: StationList([F.imst, busStop]))
        XCTAssertEqual(matcher.best(near: near)?.station.id, F.imst.id)
        XCTAssertEqual(matcher.candidates(near: near).map(\.station.id), [F.imst.id, busStop.id])
        XCTAssertNil(matcher.best(near: DetectionGeo.offset(F.imst.location, meters: 900, bearingDegrees: 0)))
    }

    func testStationIndexIsAStationLookup() {
        let index = StationIndex(stations: [F.innsbruck, F.hall, F.landeck])
        let hits = index.stations(near: DetectionGeo.offset(F.innsbruck.location, meters: 120, bearingDegrees: 45), withinMeters: 500, limit: 5)
        XCTAssertEqual(hits.map(\.station.id), [F.innsbruck.id])
        XCTAssertEqual(hits[0].distanceMeters, 120, accuracy: 3)
    }

    // MARK: Provider

    func testScriptedProviderDeliversThePointsInOrder() async {
        let points = ScriptedTrack.coarseLine(from: F.innsbruck.location, to: F.landeck.location, start: F.nov12("08:00"), end: F.nov12("09:00"), count: 5)
        let provider = ScriptedTrackProvider(script: points.reversed())
        var received: [CoarsePoint] = []
        for await point in provider.positions() { received.append(point) }
        XCTAssertEqual(received, points)
    }

    func testScriptedProviderStops() async {
        let points = ScriptedTrack.stay(at: F.hall.location, from: F.nov12("08:00"), to: F.nov12("12:00"))
        let provider = ScriptedTrackProvider(script: points, pace: 0.01)
        var count = 0
        for await _ in provider.positions() {
            count += 1
            if count == 3 { provider.stop() }
        }
        XCTAssertLessThan(count, points.count)
        XCTAssertGreaterThanOrEqual(count, 3)
    }
}
