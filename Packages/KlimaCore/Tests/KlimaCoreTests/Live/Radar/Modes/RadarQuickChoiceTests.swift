import XCTest
@testable import KlimaCore

// MARK: radarmodes – „Schnellwahl“.
final class RadarQuickChoiceTests: XCTestCase {
    func testTheFiveChoices() {
        XCTAssertEqual(RadarQuickChoice.allCases.map(\.title), ["Alles", "Fernverkehr", "Regional & S-Bahn", "Öffis in der Stadt", "Nur Verspätete"])
        let start = (RadarModeSelection.default, RadarFilter(state: .tirol, trainClasses: [.rex]))
        let all = RadarQuickChoice.all.apply(to: start.0, filter: start.1)
        XCTAssertEqual(all.0.modes, Set(RadarMode.allCases))
        XCTAssertFalse(all.1.isActive)
        let long = RadarQuickChoice.longDistance.apply(to: start.0, filter: start.1)
        XCTAssertEqual(long.0.modes, [.rail])
        XCTAssertEqual(long.1.trainClasses, [.rjx, .rj, .icec, .njen, .wb])
        let regional = RadarQuickChoice.regional.apply(to: start.0, filter: start.1)
        XCTAssertEqual(regional.0.modes, [.rail, .suburban])
        XCTAssertEqual(regional.1.trainClasses, [.cjx, .rex, .r, .s])
        let city = RadarQuickChoice.city.apply(to: start.0, filter: start.1)
        XCTAssertEqual(city.0.modes, [.suburban, .bus, .tram, .subway])
        XCTAssertFalse(city.1.isActive)
    }

    func testOnlyLateKeepsTheModesAndTheRegion() {
        let selection = RadarModeSelection([.rail, .bus])
        let (modes, filter) = RadarQuickChoice.lateOnly.apply(to: selection, filter: RadarFilter(state: .wien, trainClasses: [.rjx]))
        XCTAssertEqual(modes, selection)
        XCTAssertEqual(filter, RadarFilter(state: .wien, onlyLate: true))
    }

    func testTheCurrentChoiceIsRecognisedAndLostAfterAManualChange() {
        for choice in RadarQuickChoice.allCases {
            let (modes, filter) = choice.apply(to: .default, filter: RadarFilter())
            XCTAssertEqual(RadarQuickChoice.current(selection: modes, filter: filter), choice, choice.title)
        }
        var (modes, filter) = RadarQuickChoice.longDistance.apply(to: .default, filter: RadarFilter())
        filter.trainClasses.remove(.wb)
        XCTAssertNil(RadarQuickChoice.current(selection: modes, filter: filter))
        (modes, filter) = RadarQuickChoice.all.apply(to: .default, filter: RadarFilter())
        modes.toggle(.tram)
        XCTAssertNil(RadarQuickChoice.current(selection: modes, filter: filter))
        XCTAssertNil(RadarQuickChoice.current(selection: .default, filter: RadarFilter()), "the default is none of the five")
    }
}
