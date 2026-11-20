import XCTest
@testable import KlimaCore

// MARK: uebersicht – order, visibility, presets and the tolerant `dash.layout.v1` (docs/DASHBOARD_LAYOUT.md §2).
final class DashLayoutTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testStandardIsTheDefaultOrderWithNothingHidden() {
        let layout = DashLayout.standard
        XCTAssertEqual(layout.order, DashSectionID.defaultOrder)
        XCTAssertTrue(layout.hidden.isEmpty)
        XCTAssertEqual(Set(DashSectionID.defaultOrder), Set(DashSectionID.allCases), "every section has a default place")
        XCTAssertEqual(DashSectionID.defaultOrder.count, DashSectionID.allCases.count, "no section twice")
    }

    func testRoundTrip() {
        var layout = DashLayout.standard
        layout.move(fromOffsets: IndexSet(integer: 6), toOffset: 1)
        layout.setHidden(.perks, true)
        let decoded = DashLayout.decode(layout.encoded())
        XCTAssertEqual(decoded, layout)
    }

    func testGarbageGivesTheDefault() {
        for text in ["", "null", "[]", "42", "\"balance\"", "{", "{\"version\":\"eins\"}", "{\"version\":9,\"order\":[\"perks\"]}",
                     "{\"order\":[\"perks\"]}", "{\"version\":1}", "{\"version\":1,\"order\":[\"radar\",\"weather\"]}"] {
            XCTAssertEqual(DashLayout.decode(json(text)), .standard, text)
        }
        XCTAssertEqual(DashLayout.decode(nil), .standard)
    }

    func testUnknownIdsAreDroppedAndBadValuesSkipped() {
        let layout = DashLayout.decode(json(#"{"version":1,"order":["perks","radar",3,"balance",null,"perks"],"hidden":["week",true,"weather"]}"#))
        XCTAssertEqual(Array(layout.order.prefix(2)), [.perks, .balance], "known ids keep their order, duplicates go")
        XCTAssertFalse(layout.order.contains { $0.rawValue == "radar" })
        XCTAssertEqual(layout.hidden, [.week])
        XCTAssertEqual(Set(layout.order), Set(DashSectionID.allCases))
    }

    func testNewIdJoinsAfterItsPredecessorOfTheDefaultOrder() {
        // A layout stored before Pendel-Modus, Jahresrückblick, Termine, Ziele and Kennzahlen existed, with an own order.
        let stored = #"{"version":1,"order":["recentTrips","balance","quickLog","suggestions","achievements","week","perks"],"hidden":["perks"]}"#
        let layout = DashLayout.decode(json(stored))
        XCTAssertEqual(layout.order, [.recentTrips, .goals, .kpis, .balance, .yearReview, .commute, .quickLog, .suggestions,
                                      .calendarSuggestions, .achievements, .week, .perks])
        XCTAssertEqual(layout.hidden, [.perks], "the person's choice stays; the new cards show")
    }

    func testNewIdWithoutPredecessorGoesFirst() {
        let layout = DashLayout(order: [.perks])
        XCTAssertEqual(layout.order.first, .balance)
        XCTAssertEqual(layout.order.last, .perks)
        XCTAssertEqual(layout.order.count, DashSectionID.allCases.count)
    }

    /// The reference: SwiftUI's `Array.move(fromOffsets:toOffset:)`, written out (the Linux harness has no SwiftUI).
    private func referenceMove<T>(_ array: [T], _ source: IndexSet, _ destination: Int) -> [T] {
        var result = array
        let moving = source.sorted().map { array[$0] }
        // Remove from the back so the offsets stay valid, then insert at the destination shifted by the removed elements before it.
        for index in source.sorted(by: >) { result.remove(at: index) }
        let shift = source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: destination - shift)
        return result
    }

    func testMoveEqualsArrayMove() {
        let base = Array(0..<8)
        let cases: [(IndexSet, Int)] = [
            (IndexSet(integer: 0), 8), (IndexSet(integer: 7), 0), (IndexSet(integer: 2), 5), (IndexSet(integer: 5), 2),
            (IndexSet(integer: 3), 3), (IndexSet(integer: 3), 4), (IndexSet([1, 4]), 7), (IndexSet([1, 4]), 0),
            (IndexSet([0, 7]), 4), (IndexSet([2, 3, 4]), 8),
        ]
        for (source, destination) in cases {
            XCTAssertEqual(DashLayout.moved(base, fromOffsets: source, toOffset: destination),
                           referenceMove(base, source, destination), "\(Array(source)) → \(destination)")
        }
        // Known SwiftUI results.
        XCTAssertEqual(DashLayout.moved([0, 1, 2, 3], fromOffsets: IndexSet(integer: 0), toOffset: 2), [1, 0, 2, 3])
        XCTAssertEqual(DashLayout.moved([0, 1, 2, 3], fromOffsets: IndexSet(integer: 3), toOffset: 1), [0, 3, 1, 2])
        // Out of range: unchanged.
        XCTAssertEqual(DashLayout.moved([0, 1, 2], fromOffsets: IndexSet(integer: 0), toOffset: 9), [0, 1, 2])
    }

    func testMoveOnTheLayout() {
        var layout = DashLayout.standard
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: layout.order.count)
        XCTAssertEqual(layout.order.last, .balance, "the Bilanz may move, it only cannot hide")
        XCTAssertTrue(layout.moveUp(.balance))
        XCTAssertEqual(layout.order[layout.order.count - 2], .balance)
        XCTAssertTrue(layout.moveDown(.balance))
        XCTAssertFalse(layout.moveDown(.balance), "already at the bottom")
        var top = DashLayout.standard
        XCTAssertFalse(top.moveUp(.balance), "already at the top")
        XCTAssertEqual(top, .standard)
    }

    func testHideIsIdempotentAndCoreStays() {
        var layout = DashLayout.standard
        layout.setHidden(.perks, true)
        let once = layout
        layout.setHidden(.perks, true)
        XCTAssertEqual(layout, once)
        layout.setHidden(.balance, true)
        XCTAssertFalse(layout.isHidden(.balance), "the Bilanz is core")
        XCTAssertFalse(layout.visibleOrder.contains(.perks))
        layout.setHidden(.perks, false)
        layout.setHidden(.perks, false)
        XCTAssertEqual(layout, .standard)
        // A stored file that hides the core section still shows it.
        let decoded = DashLayout.decode(json(#"{"version":1,"order":["balance"],"hidden":["balance","week"]}"#))
        XCTAssertEqual(decoded.hidden, [.week])
    }

    func testPresets() {
        XCTAssertEqual(DashPreset.standard.layout, .standard)
        XCTAssertEqual(DashPreset.all.layout, .standard)
        XCTAssertTrue(DashPreset.all.fillsEmptyKpis)
        XCTAssertTrue(DashPreset.numbers.fillsEmptyKpis)
        XCTAssertFalse(DashPreset.quiet.fillsEmptyKpis)

        let quiet = DashPreset.quiet.layout
        XCTAssertEqual(quiet.order, DashSectionID.defaultOrder)
        XCTAssertEqual(quiet.hidden, DashPreset.quietHidden)
        for id in [DashSectionID.balance, .quickLog, .recentTrips, .suggestions] {
            XCTAssertFalse(quiet.isHidden(id), "\(id) stays in Ruhig")
        }

        let numbers = DashPreset.numbers.layout
        XCTAssertEqual(Array(numbers.order.prefix(4)), [.balance, .kpis, .goals, .week])
        XCTAssertEqual(numbers.hidden, [.perks])
        XCTAssertEqual(Set(numbers.order), Set(DashSectionID.allCases))

        XCTAssertEqual(DashPreset.matching(.standard), .standard)
        XCTAssertEqual(DashPreset.matching(quiet), .quiet)
        XCTAssertEqual(DashPreset.matching(numbers), .numbers)
        var custom = DashLayout.standard
        custom.setHidden(.week, true)
        XCTAssertNil(DashPreset.matching(custom))
    }

    func testPlace() {
        var layout = DashLayout.standard
        layout.place(.perks, after: .balance)
        XCTAssertEqual(Array(layout.order.prefix(2)), [.balance, .perks])
        layout.place(.perks, after: .perks)
        XCTAssertEqual(Array(layout.order.prefix(2)), [.balance, .perks])
        XCTAssertEqual(layout.order.count, DashSectionID.allCases.count)
    }

    func testRawValuesAreStable() {
        // Stored strings – a rename would wipe everyone's layout.
        XCTAssertEqual(DashSectionID.allCases.map(\.rawValue), [
            "balance", "yearReview", "commute", "quickLog", "suggestions", "calendarSuggestions", "recentTrips", "goals", "kpis",
            "achievements", "week", "perks",
        ])
        XCTAssertEqual(DashLayout.storageKey, "dash.layout.v1")
        XCTAssertTrue(BackupSettingsPolicy.allows(DashLayout.storageKey))
        XCTAssertTrue(BackupSettingsPolicy.allows(KpiSelection.storageKey))
        XCTAssertTrue(BackupSettingsPolicy.allows(GoalList.storageKey))
        XCTAssertTrue(BackupSettingsPolicy.allows(GoalLedger.storageKey))
    }

    func testEveryTitleAndHintIsSet() {
        for id in DashSectionID.allCases {
            XCTAssertFalse(id.title.isEmpty)
            XCTAssertFalse(id.whenShown.isEmpty)
            XCTAssertFalse(id.symbol.isEmpty)
        }
    }
}
