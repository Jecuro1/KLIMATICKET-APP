import XCTest
@testable import KlimaCore

/// Zugsuche (HAFAS JourneyMatch): encoder key set, decoding rules and the name parser. Offline. The response bodies are
/// synthetic and follow the shape the codec reads (reference `parse/trip.js`, `tripsByName`); they are not live captures.
final class JourneyMatchTests: XCTestCase {
    static let synthetic = """
    {"err":"OK","svcResL":[{"meth":"JourneyMatch","err":"OK","res":{
      "common":{
        "locL":[
          {"type":"S","lid":"A=1@L=8103000@","extId":"8103000","name":"Wien Hbf"},
          {"type":"S","lid":"A=1@L=8100108@","extId":"8100108","name":"Innsbruck Hbf"},
          {"type":"S","lid":"A=1@L=8100197@","extId":"8100197","name":"Feldkirch Bahnhof"}
        ],
        "prodL":[{"name":"RJX 66","cls":1,"number":"66","prodCtx":{"catOut":"RJX","catOutS":"RJX","num":"66","line":"RJX"},"oprX":0}],
        "opL":[{"name":"ÖBB"}]
      },
      "planrtTS":"20261014093000",
      "jnyL":[
        {"jid":"1|#VN#1#ST#1#","date":"20261014","prodX":0,"dirTxt":"Feldkirch Bahnhof","isCncl":false,
         "stopL":[
           {"locX":1,"idx":1,"aTimeS":"113000","dTimeS":"113200"},
           {"locX":2,"idx":2,"aTimeS":"120000","aTimeR":"120500"},
           {"locX":0,"idx":0,"dTimeS":"093000","dTimeR":"093000"}
         ]},
        {"jid":"1|#VN#1#ST#1#","date":"20261014","prodX":0,"dirTxt":"Duplikat","stopL":[]},
        {"jid":"1|#VN#2#ST#2#","date":"20261014","prodX":0,"dirTxt":"Innsbruck Hbf","isCncl":true}
      ]
    }}]}
    """

    static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(try HafasEncoderTests.encode(value) as? [String: Any])
    }

    // MARK: - Encoder

    func testRequestHasExactKeysWithoutDay() throws {
        let body = try Self.encode(HafasRequests.journeyMatch(TrainSearchQuery(input: "RJX 66", products: .highSpeed)))
        XCTAssertEqual(Set(body.keys), ["meth", "cfg", "req"])
        XCTAssertEqual(body["meth"] as? String, "JourneyMatch")
        XCTAssertEqual((body["cfg"] as? [String: Any])?["polyEnc"] as? String, "GPA")
        let req = try XCTUnwrap(body["req"] as? [String: Any])
        XCTAssertEqual(Set(req.keys), ["input", "onlyCR", "jnyFltrL"], "no date or time unless a day is set")
        XCTAssertEqual(req["input"] as? String, "RJX 66")
        XCTAssertEqual(req["onlyCR"] as? Bool, false)
        let filter = try XCTUnwrap((req["jnyFltrL"] as? [[String: Any]])?.first)
        XCTAssertEqual(filter["type"] as? String, "PROD")
        XCTAssertEqual(filter["mode"] as? String, "INC")
        XCTAssertEqual(filter["value"] as? String, "1")
    }

    func testRequestCarriesDayAndTimeOnlyWhenSet() throws {
        let day = HafasEncoderTests.vienna(2026, 10, 14, 9, 30)
        let body = try Self.encode(HafasRequests.journeyMatch(TrainSearchQuery(input: "66", products: .rail, onlyRunning: true, date: day)))
        let req = try XCTUnwrap(body["req"] as? [String: Any])
        XCTAssertEqual(req["date"] as? String, HafasTime.dateString(day))
        XCTAssertEqual(req["time"] as? String, HafasTime.timeString(day))
        XCTAssertEqual(req["onlyCR"] as? Bool, true)
        XCTAssertEqual((req["jnyFltrL"] as? [[String: Any]])?.first?["value"] as? String, String(ProductMask.rail.rawValue))
    }

    func testInputIsSentVerbatim() throws {
        let body = try Self.encode(HafasRequests.journeyMatch(TrainSearchQuery(input: "RJX66", products: .highSpeed)))
        XCTAssertEqual((body["req"] as? [String: Any])?["input"] as? String, "RJX66")
    }

    // MARK: - Decoder

    func testDecodesRunsWithFirstAndLastStopByIndexAndDropsDuplicates() throws {
        let result = try HafasCodec.trainSearch(from: Data(Self.synthetic.utf8))
        XCTAssertEqual(result.source, .journeyMatch)
        XCTAssertEqual(result.runs.count, 2, "the second entry repeats the first trip id and is dropped; the cancelled run without stops is kept")

        let run = try XCTUnwrap(result.runs.first)
        XCTAssertEqual(run.tripID, "1|#VN#1#ST#1#")
        XCTAssertEqual(run.line?.name, "RJX 66")
        XCTAssertEqual(run.direction, "Feldkirch Bahnhof")
        XCTAssertEqual(run.origin?.location.name, "Wien Hbf", "origin is the stop with the lowest idx, whatever the list order")
        XCTAssertEqual(run.destination?.location.name, "Feldkirch Bahnhof", "destination is the stop with the highest idx")
        XCTAssertEqual(run.destination?.arrival?.delaySeconds, 300, "realtime arrival 12:05 against planned 12:00")
        XCTAssertEqual(run.delaySeconds, 300)
        XCTAssertNotNil(run.plannedDate)
        XCTAssertTrue(run.hasRealtime)
        XCTAssertFalse(run.isCancelled)
    }

    func testRunWithoutStopListKeepsNilEndpoints() throws {
        let result = try HafasCodec.trainSearch(from: Data(Self.synthetic.utf8))
        let run = try XCTUnwrap(result.runs.last)
        XCTAssertEqual(run.tripID, "1|#VN#2#ST#2#")
        XCTAssertNil(run.origin)
        XCTAssertNil(run.destination)
        XCTAssertNil(run.plannedDate)
        XCTAssertNil(run.delaySeconds)
        XCTAssertTrue(run.isCancelled)
    }

    /// Live shape (`journeymatch_rjx66_highspeed`, one request on 2026-10-14, sanitized: see docs/OEBB_LIVE.md §R9). 15 runs,
    /// no `idx`, no `dirTxt`, no realtime; four runs are "RJX 66", the rest are name-prefix matches "RJX 660" to "RJX 669".
    func testLiveShapeFixtureDecodesAndFiltersToTheNamedTrain() throws {
        let data = try Fixture.data("hafas/journeymatch_rjx66_highspeed.response")
        let result = try HafasCodec.trainSearch(from: data)
        XCTAssertEqual(result.runs.count, 15)
        XCTAssertTrue(result.runs.allSatisfy { $0.origin != nil && $0.destination != nil }, "every run has a two-stop list")
        XCTAssertTrue(result.runs.allSatisfy { $0.direction == nil }, "the live answer has no dirTxt")

        let exact = result.runs(for: try XCTUnwrap(TrainName("RJX 66")))
        XCTAssertEqual(exact.count, 4)
        XCTAssertEqual(exact.first?.origin?.location.name, "Budapest-Keleti")
        XCTAssertEqual(exact.first?.destination?.location.name, "München Hbf")
        XCTAssertTrue(exact.allSatisfy { !$0.hasRealtime && $0.delaySeconds == nil }, "no realtime in this answer: shown as Plan")
        let dates = exact.compactMap(\.plannedDate)
        XCTAssertEqual(dates, dates.sorted(), "date order")
        XCTAssertEqual(result.runs(for: try XCTUnwrap(TrainName("66"))).count, 4, "a bare number matches the same four runs")
    }

    func testFollowTargetUsesFirstAndLastStop() throws {
        let data = try Fixture.data("hafas/journeymatch_rjx66_highspeed.response")
        let run = try XCTUnwrap(try HafasCodec.trainSearch(from: data).runs(for: try XCTUnwrap(TrainName("RJX 66"))).first)
        let target = try XCTUnwrap(run.followTarget)
        XCTAssertEqual(target.tripID, run.tripID)
        XCTAssertEqual(target.boardingStop.name, "Budapest-Keleti")
        XCTAssertEqual(target.alightStop.name, "München Hbf")
        XCTAssertEqual(target.lineName, LinePresentation.title(try XCTUnwrap(run.line)))
        XCTAssertNil(TrainRun(tripID: "x").followTarget, "a run without stops cannot be followed")
    }

    func testRunIsActiveOnlyOnItsOwnDayInVienna() throws {
        let day = HafasEncoderTests.vienna(2026, 10, 14, 9, 30)
        let stop = Stopover(location: Location.station(extId: "8100108", name: "Innsbruck Hbf"),
                             departure: StopEvent(planned: day), index: 0)
        let run = TrainRun(tripID: "t", origin: stop)
        XCTAssertTrue(run.isActive(on: HafasEncoderTests.vienna(2026, 10, 14, 18, 0)))
        XCTAssertFalse(run.isActive(on: HafasEncoderTests.vienna(2026, 10, 15, 8, 0)))
        XCTAssertFalse(TrainRun(tripID: "none").isActive(on: day))
    }

    /// NO_MATCH is the answer "no run with this name": an empty result, not an error.
    func testNoMatchIsAnEmptyResult() throws {
        let body = """
        {"err":"OK","svcResL":[{"meth":"JourneyMatch","err":"NO_MATCH","errTxt":"Nothing found.",
        "errTxtOut":"Während der Suche ist leider ein interner Fehler aufgetreten."}]}
        """
        let result = try HafasCodec.trainSearch(from: Data(body.utf8))
        XCTAssertEqual(result, .empty)
    }

    func testOtherServiceErrorsStayErrors() {
        let body = """
        {"err":"OK","svcResL":[{"meth":"JourneyMatch","err":"PARAMETER","errTxtOut":"Ungültige Eingabe"}]}
        """
        XCTAssertThrowsError(try HafasCodec.trainSearch(from: Data(body.utf8))) { error in
            XCTAssertEqual(error as? LiveError, .hafas(code: "PARAMETER", message: "Ungültige Eingabe"))
        }
    }

    func testTopLevelParseErrorIsDecodingError() {
        let body = #"{"err":"PARSE","errTxt":"unknown field"}"#
        XCTAssertThrowsError(try HafasCodec.trainSearch(from: Data(body.utf8))) { error in
            guard case .decoding = error as? LiveError else { return XCTFail("expected decoding, got \(error)") }
        }
    }

    // MARK: - Name

    func testTrainNameParsesTypedForms() {
        XCTAssertEqual(TrainName("RJX 66")?.hafasInput, "RJX 66")
        XCTAssertEqual(TrainName("rjx66")?.hafasInput, "RJX 66")
        XCTAssertEqual(TrainName("RJX-66")?.hafasInput, "RJX 66")
        XCTAssertEqual(TrainName("  S 45 ")?.category, "S")
        XCTAssertEqual(TrainName("66")?.hafasInput, "66")
        XCTAssertNil(TrainName("66")?.category)
        XCTAssertEqual(TrainName("1830")?.number, "1830")
    }

    func testTrainNameRejectsWordsAndMixedText() {
        for text in ["", "   ", "Wien Hbf", "RJX", "66a", "ÖBB 5", "123456", "RJX 66 Wien"] {
            XCTAssertNil(TrainName(text), "\(text) is not a train name")
        }
    }

    func testTrainNameMatchesOnlyTheNamedTrain() {
        let rjx66 = Line(name: "RJX 66", category: "RJX", lineNumber: nil, productClass: 1, mode: .train)
        XCTAssertTrue(TrainName("RJX 66")!.matches(rjx66))
        XCTAssertTrue(TrainName("66")!.matches(rjx66), "a bare number matches any category")
        XCTAssertFalse(TrainName("REX 66")!.matches(rjx66), "a different category is a different train")
        XCTAssertFalse(TrainName("RJX 67")!.matches(rjx66))
        XCTAssertFalse(TrainName("66")!.matches(nil))
    }

    // MARK: - Suggestions

    func testSuggestionsFromTypedText() {
        let recent = ["RJX 66", "EC 90"]
        XCTAssertEqual(TrainSearchSuggestions.make(for: "", recent: recent), recent)
        XCTAssertEqual(TrainSearchSuggestions.make(for: "rj", recent: recent), ["RJX", "RJ", "RJX 66"])
        XCTAssertEqual(TrainSearchSuggestions.make(for: "RJX 66", recent: recent).first, "RJX 66")
        XCTAssertEqual(Array(TrainSearchSuggestions.make(for: "66", recent: []).prefix(2)), ["RJX 66", "RJ 66"])
        XCTAssertEqual(TrainSearchSuggestions.make(for: "66", recent: [], limit: 3).count, 3)
        XCTAssertEqual(TrainSearchSuggestions.make(for: "Wien", recent: recent), [], "a word matches no recent search")
    }
}
