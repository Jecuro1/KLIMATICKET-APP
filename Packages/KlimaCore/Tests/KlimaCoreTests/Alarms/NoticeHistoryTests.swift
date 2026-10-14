import XCTest
@testable import KlimaCore

/// Alarme einsehen: the on-device history keeps the newest 30 delivered notices, each once.
final class NoticeHistoryTests: XCTestCase {
    private func notice(_ index: Int, kind: AlarmKind = .departure) -> DeliveredNotice {
        DeliveredNotice(id: "n\(index)", kind: kind, title: "Titel \(index)", body: "Text \(index)",
                        deliveredAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 60))
    }

    func testKeepsTheNewestThirtyNewestFirst() {
        var history = NoticeHistory()
        for index in 0..<35 { history.record(notice(index)) }
        XCTAssertEqual(history.entries.count, NoticeHistory.limit)
        XCTAssertEqual(history.entries.first?.id, "n34")
        XCTAssertEqual(history.entries.last?.id, "n5")
        XCTAssertFalse(history.entries.contains { $0.id == "n4" })
    }

    func testAnIdentifierIsRecordedOnce() {
        var history = NoticeHistory()
        XCTAssertTrue(history.record(notice(1)))
        let changed = DeliveredNotice(id: "n1", kind: .other, title: "Anders", body: "", deliveredAt: Date())
        XCTAssertFalse(history.record(changed))
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.title, "Titel 1")
    }

    func testMergeAddsOnlyWhatIsNewAndKeepsOrder() {
        var history = NoticeHistory(entries: [notice(10), notice(11)])
        history.merge([notice(11), notice(12), notice(3)])
        XCTAssertEqual(history.entries.map(\.id), ["n12", "n11", "n10", "n3"])
    }

    func testInitSortsAndTrims() {
        let shuffled = (0..<40).map { notice($0) }.reversed()
        let history = NoticeHistory(entries: Array(shuffled))
        XCTAssertEqual(history.entries.count, 30)
        XCTAssertEqual(history.entries.first?.id, "n39")
    }

    func testClearEmptiesTheHistory() {
        var history = NoticeHistory(entries: [notice(1), notice(2)])
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testHistoryRoundTripsThroughCodable() throws {
        let history = NoticeHistory(entries: [notice(1, kind: .weeklySummary), notice(2, kind: .routeReminder)])
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(NoticeHistory.self, from: data), history)
    }
}
