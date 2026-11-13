import XCTest
@testable import KlimaCore

// MARK: radarmodes – the radar filter v2 and its one matcher (docs/RADAR_MODES.md §6).
final class RadarFilterCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_796_500)

    private func vehicle(_ name: String, category: String? = nil, number: String? = nil, cls: Int, mode: TransportMode = .train,
                         op: String? = "ÖBB", admin: String? = nil, delay: Int? = 0, cancelled: Bool = false, id: String? = nil) -> RadarVehicle {
        let planned = now.addingTimeInterval(300)
        let event = StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval(TimeInterval($0)) })
        let stop = Stopover(location: Location(lid: "x", kind: .station, extId: nil, name: "Wien Hbf", coordinate: GeoPoint(latitude: 48.18, longitude: 16.37)),
                            arrival: event, index: 0)
        return RadarVehicle(tripID: id ?? name, line: Line(name: name, fullName: name, category: category, lineNumber: number, admin: admin,
                                                           operatorName: op, productClass: cls, mode: mode),
                            coordinate: GeoPoint(latitude: 48.2, longitude: 16.37), stopovers: [stop], isCancelled: cancelled)
    }

    func testZugartClassification() {
        let table: [(String, RadarTrainClass)] = [("RJX", .rjx), ("RJ", .rj), ("IC", .icec), ("EC", .icec), ("ICE", .icec), ("IR", .icec),
                                                  ("D", .icec), ("NJ", .njen), ("EN", .njen), ("WB", .wb), ("CJX", .cjx), ("REX", .rex),
                                                  ("R", .r), ("S", .s), ("XYZ", .other), ("", .other)]
        for (category, expected) in table { XCTAssertEqual(RadarTrainClass.of(category: category), expected, category) }
        XCTAssertEqual(RadarTrainClass.of(vehicle("WB 912", category: "WB", cls: 4096).line), .wb)
        XCTAssertEqual(RadarTrainClass.of(vehicle("S 45", category: "S", number: "45", cls: 32, mode: .sBahn).line), .s)
        XCTAssertNil(RadarTrainClass.of(vehicle("Bus 13A", category: "Bus", number: "13A", cls: 64, mode: .bus).line))
        XCTAssertNil(RadarTrainClass.of(vehicle("SEV", category: "Bus", cls: 2, mode: .bus).line))
        XCTAssertEqual(RadarTrainClass.allCases.map(\.title), ["RJX", "RJ", "IC/EC", "NJ/EN", "WB", "CJX", "REX", "R", "S", "Andere"])
        XCTAssertEqual(RadarTrainClass.njen.spoken, "Nachtzug")
    }

    func testZugartNeverHidesABusBimOrUBahn() {
        let filter = RadarFilter(trainClasses: [.rjx])
        XCTAssertTrue(filter.matches(vehicle("RJX 66", category: "RJX", cls: 1), now: now))
        XCTAssertFalse(filter.matches(vehicle("REX 2", category: "REX", number: "2", cls: 16), now: now))
        XCTAssertTrue(filter.matches(vehicle("Bus 13A", category: "Bus", number: "13A", cls: 64, mode: .bus), now: now))
        XCTAssertTrue(filter.matches(vehicle("Tram D", category: "Tram", number: "D", cls: 512, mode: .tram), now: now))
        XCTAssertTrue(filter.matches(vehicle("U6", category: "U", number: "U6", cls: 256, mode: .metro), now: now))
    }

    func testLinesMatchCompactTitles() {
        let bus = vehicle("Bus 13A", category: "Bus", number: "13A", cls: 64, mode: .bus)
        let u6 = vehicle("U6", category: "U", number: "U6", cls: 256, mode: .metro)
        let s45 = vehicle("S 45", category: "S", number: "45", cls: 32, mode: .sBahn)
        let rjx = vehicle("RJX 66", category: "RJX", number: nil, cls: 1)
        XCTAssertTrue(RadarFilter(lines: ["13a"]).matches(bus, now: now))
        XCTAssertTrue(RadarFilter(lines: ["Bus 13A"]).matches(bus, now: now))
        XCTAssertTrue(RadarFilter(lines: ["u 6"]).matches(u6, now: now))
        XCTAssertTrue(RadarFilter(lines: ["S45"]).matches(s45, now: now))
        XCTAssertTrue(RadarFilter(lines: ["RJX 66"]).matches(rjx, now: now))
        XCTAssertFalse(RadarFilter(lines: ["13A"]).matches(u6, now: now))
        XCTAssertFalse(RadarFilter(lines: ["13"]).matches(bus, now: now), "a line is the whole name, not a part")
        XCTAssertTrue(RadarFilter(lines: ["13A", "U6"]).matches(u6, now: now))
    }

    func testOperators() {
        XCTAssertEqual(RadarOperator.name(of: Line(name: "R", admin: "81____", operatorName: "Postbus")), "ÖBB")
        XCTAssertEqual(RadarOperator.name(of: Line(name: "WB", admin: "3236__")), "WESTbahn")
        XCTAssertEqual(RadarOperator.name(of: Line(name: "R", operatorName: "Nahreisezug")), "ÖBB")
        XCTAssertEqual(RadarOperator.name(of: Line(name: "R", operatorName: "OEBB Personenverkehr AG Kundenservice")), "ÖBB")
        XCTAssertEqual(RadarOperator.name(of: Line(name: "WB", operatorName: "WESTbahn Management GmbH")), "WESTbahn")
        XCTAssertEqual(RadarOperator.name(of: Line(name: "Bus 13A", operatorName: "Stadtverkehr")), "Stadtverkehr")
        XCTAssertEqual(RadarOperator.name(of: Line(name: "Bus")), "Unbekannt")
        XCTAssertEqual(RadarOperator.name(of: nil), "Unbekannt")
        let filter = RadarFilter(operators: ["ÖBB"])
        XCTAssertTrue(filter.matches(vehicle("REX 2", category: "REX", cls: 16, op: "Nahreisezug"), now: now))
        XCTAssertFalse(filter.matches(vehicle("Bus 13A", category: "Bus", cls: 64, mode: .bus, op: "Stadtverkehr"), now: now))
        let counts = RadarOperator.counts([vehicle("a", cls: 1, op: "Nahreisezug"), vehicle("b", cls: 1, op: "ÖBB"), vehicle("c", cls: 64, op: "X")])
        XCTAssertEqual(counts.map(\.name), ["ÖBB", "X"])
        XCTAssertEqual(counts.map(\.count), [2, 1])
    }

    func testTheModeOfAVehicleIsItsClassBitNotItsLineMode() {
        // Rail replacement is `.bus` for the codec; a mode filter would not treat it as a bus, and Zugart does not hide it.
        let sev = vehicle("SEV", category: "Bus", cls: 2, mode: .bus)
        XCTAssertNil(RadarMode.of(sev))
        XCTAssertTrue(RadarFilter(trainClasses: [.rjx]).matches(sev, now: now))
        XCTAssertEqual(RadarModeCounts(productClasses: [sev.line!.productClass], shownModes: [.bus]).line, "Bus 0 · Andere 1")
    }

    func testRealtimeAndDelay() {
        let onTime = vehicle("REX 1", category: "REX", cls: 16, delay: 60)
        let late = vehicle("REX 2", category: "REX", cls: 16, delay: 420)
        let noRealtime = vehicle("REX 3", category: "REX", cls: 16, delay: nil)
        let cancelled = vehicle("REX 4", category: "REX", cls: 16, delay: nil, cancelled: true)
        let realtime = RadarFilter(onlyRealtime: true)
        XCTAssertTrue(realtime.matches(onTime, now: now))
        XCTAssertTrue(realtime.matches(late, now: now))
        XCTAssertFalse(realtime.matches(noRealtime, now: now))
        XCTAssertTrue(realtime.matches(cancelled, now: now), "a cancelled run counts as one with realtime")
        let lateOnly = RadarFilter(onlyLate: true)
        XCTAssertEqual([onTime, late, noRealtime, cancelled].filter { lateOnly.matches($0, now: now) }.map(\.tripID), ["REX 2"])
        XCTAssertEqual([onTime, late, noRealtime, cancelled].filter { RadarFilter(delays: [.onTime, .cancelled]).matches($0, now: now) }.map(\.tripID),
                       ["REX 1", "REX 4"])
    }

    func testBothMatchersAgree() {
        let vehicles = [vehicle("RJX 66", category: "RJX", cls: 1), vehicle("REX 2", category: "REX", number: "2", cls: 16, delay: 400),
                        vehicle("S 45", category: "S", number: "45", cls: 32, mode: .sBahn, delay: nil),
                        vehicle("Bus 13A", category: "Bus", number: "13A", cls: 64, mode: .bus, op: "Stadtverkehr"),
                        vehicle("U6", category: "U", number: "U6", cls: 256, mode: .metro, delay: 600)]
        let filters = [RadarFilter(), RadarFilter(trainClasses: [.rjx]), RadarFilter(trainClasses: [.rex, .s]), RadarFilter(lines: ["13A"]),
                       RadarFilter(lines: ["U6", "S 45"]), RadarFilter(operators: ["ÖBB"]), RadarFilter(operators: ["Stadtverkehr"]),
                       RadarFilter(onlyLate: true), RadarFilter(onlyRealtime: true), RadarFilter(delays: [.onTime]), RadarFilter(delays: [.unknown]),
                       RadarFilter(state: .wien), RadarFilter(categories: ["RJX"]), RadarFilter(trainClasses: [.other]),
                       RadarFilter(onlyLate: true, trainClasses: [.rex]), RadarFilter(lines: ["RJX66"]), RadarFilter(operators: ["Unbekannt"]),
                       RadarFilter(delays: [.late, .cancelled]), RadarFilter(lines: ["S45"], onlyRealtime: true), RadarFilter(trainClasses: [.wb])]
        XCTAssertEqual(filters.count, 20)
        for filter in filters {
            for vehicle in vehicles {
                let pin = RadarTimePin(tripID: vehicle.tripID, vehicle: vehicle, coordinate: vehicle.coordinate, bearing: nil, phase: .atStop(0),
                                       path: .atStop, distanceToAnswer: 0, delaySeconds: RadarDelay.currentDelay(of: vehicle, now: now))
                XCTAssertEqual(pin.delayState, RadarDelay.state(of: vehicle, now: now))
                XCTAssertEqual(filter.matches(vehicle, now: now), filter.matches(pin), "\(filter.summary) / \(vehicle.tripID)")
            }
        }
    }

    func testStorageRoundTripAndTolerance() {
        let filter = RadarFilter(state: .tirol, trainClasses: [.rjx, .rj], lines: ["13A", "U6"], operators: ["ÖBB"], onlyRealtime: true)
        XCTAssertEqual(RadarFilter(storage: filter.storageValue), filter)
        XCTAssertEqual(RadarFilter(storage: RadarFilter(onlyLate: true).storageValue), RadarFilter(onlyLate: true))
        XCTAssertEqual(RadarFilter(storage: ""), RadarFilter())
        XCTAssertEqual(RadarFilter(storage: "garbage"), RadarFilter())
        XCTAssertEqual(RadarFilter(storage: "[1,2]"), RadarFilter())
        let unknown = #"{"version":2,"trainClasses":["rjx","zeppelin"],"delays":["late","maybe"],"state":"atlantis","future":true}"#
        XCTAssertEqual(RadarFilter(storage: unknown), RadarFilter(delays: [.late], trainClasses: [.rjx]))
        // v1: the old sheet's categories become Zugarten where they are one.
        let v1 = #"{"categories":["RJX","REX","BUS"],"onlyLate":true}"#
        XCTAssertEqual(RadarFilter(storage: v1), RadarFilter(onlyLate: true, trainClasses: [.rjx, .rex]))
    }

    func testSummaryForTheRowOnTheMap() {
        XCTAssertEqual(RadarFilter(onlyLate: true, trainClasses: [.rj, .rjx]).summary, "RJX, RJ · nur verspätet")
        XCTAssertEqual(RadarFilter(lines: ["U6", "13A"]).summary, "13A, U6")
        XCTAssertEqual(RadarFilter().summary, "")
        XCTAssertFalse(RadarFilter().isActive)
        XCTAssertTrue(RadarFilter(onlyRealtime: true).isActive)
    }
}
