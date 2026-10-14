import XCTest
@testable import KlimaCore

/// Live verfolgen: notice policy (switches, delay choices, quiet hours, dedupe ledger).
final class FollowNoticePolicyTests: XCTestCase {
    private func at(_ hhmm: String) -> Date { FollowFixture.at(hhmm) }

    private var vienna: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal
    }

    // MARK: Ledger

    func testLedgerDeliversEachNoticeOnce() {
        var ledger = FollowNoticeLedger()
        XCTAssertTrue(ledger.claim(.arrivingSoon(stop: "Wien Hbf", minutes: 10)))
        XCTAssertFalse(ledger.claim(.arrivingSoon(stop: "Wien Hbf", minutes: 9)), "the same kind is one notice per follow")
        XCTAssertTrue(ledger.claim(.departed(stop: "Salzburg Hbf")))
        XCTAssertFalse(ledger.claim(.departed(stop: "Salzburg Hbf")))
    }

    func testLedgerRecoveryClearsDelayKeys() {
        var ledger = FollowNoticeLedger()
        XCTAssertTrue(ledger.claim(.delay(minutes: 7, stop: "Wien Hbf")))
        XCTAssertFalse(ledger.claim(.delay(minutes: 7, stop: "Wien Hbf")))
        XCTAssertTrue(ledger.claim(.delayRecovered(stop: "Wien Hbf")))
        XCTAssertTrue(ledger.claim(.delay(minutes: 7, stop: "Wien Hbf")), "after a recovery the same delay is news again")
    }

    func testLedgerKeepsPlatformsApart() {
        var ledger = FollowNoticeLedger()
        XCTAssertTrue(ledger.claim(.platform(stop: "Salzburg Hbf", from: "5", to: "6", isBoarding: true)))
        XCTAssertTrue(ledger.claim(.platform(stop: "Wien Hbf", from: "11", to: "12", isBoarding: false)))
        XCTAssertFalse(ledger.claim(.platform(stop: "Salzburg Hbf", from: "5", to: "6", isBoarding: true)))
    }

    func testLedgerRoundTripsThroughCodable() throws {
        var ledger = FollowNoticeLedger()
        ledger.claim(.cancelled(stop: "Salzburg Hbf"))
        let data = try JSONEncoder().encode(ledger)
        var decoded = try JSONDecoder().decode(FollowNoticeLedger.self, from: data)
        XCTAssertEqual(decoded, ledger)
        XCTAssertFalse(decoded.claim(.cancelled(stop: "Salzburg Hbf")))
    }

    // MARK: Kinds

    func testEveryNoticeHasAKind() {
        XCTAssertEqual(LiveFollowNotice.delayRecovered(stop: "Wien Hbf").kind, .delay)
        XCTAssertEqual(LiveFollowNotice.delay(minutes: 6, stop: "Wien Hbf").kind, .delay)
        XCTAssertEqual(LiveFollowNotice.tightTransfer(station: "Wien Hbf", bufferMinutes: 2).kind, .tightTransfer)
        XCTAssertEqual(LiveFollowNotice.arrivingSoon(stop: "Wien Hbf", minutes: 8).kind, .arrivingSoon)
        XCTAssertEqual(FollowNoticeKind.allCases.count, 7)
    }

    // MARK: Quiet hours

    func testQuietHoursWrapMidnight() {
        let quiet = QuietHours.standard
        XCTAssertTrue(quiet.contains(at("22:00"), calendar: vienna))
        XCTAssertTrue(quiet.contains(at("23:30"), calendar: vienna))
        XCTAssertTrue(quiet.contains(at("06:59"), calendar: vienna))
        XCTAssertFalse(quiet.contains(at("07:00"), calendar: vienna), "the end hour is outside the window")
        XCTAssertFalse(quiet.contains(at("21:59"), calendar: vienna))
        XCTAssertFalse(quiet.contains(at("12:00"), calendar: vienna))
    }

    func testQuietHoursWithinOneDay() {
        let lunch = QuietHours(isEnabled: true, startHour: 13, endHour: 14)
        XCTAssertTrue(lunch.contains(at("13:30"), calendar: vienna))
        XCTAssertFalse(lunch.contains(at("14:00"), calendar: vienna))
    }

    func testQuietHoursOffOrEmpty() {
        XCTAssertFalse(QuietHours(isEnabled: false).contains(at("23:00"), calendar: vienna))
        XCTAssertFalse(QuietHours(isEnabled: true, startHour: 5, endHour: 5).contains(at("05:00"), calendar: vienna))
    }

    func testQuietHoursAreClamped() {
        XCTAssertEqual(QuietHours(startHour: 30, endHour: -4).startHour, 23)
        XCTAssertEqual(QuietHours(startHour: 30, endHour: -4).endHour, 0)
    }

    // MARK: Settings

    func testDefaultsAreOffAndQuietFromTenToSeven() {
        let settings = FollowNoticeSettings()
        XCTAssertFalse(settings.isEnabled, "nothing is on until the user switches it on")
        XCTAssertEqual(settings.delayThresholdMinutes, 5)
        XCTAssertEqual(settings.quietHours, QuietHours(isEnabled: true, startHour: 22, endHour: 7))
        XCTAssertEqual(Set(FollowNoticeKind.allCases), settings.kinds)
    }

    func testMasterSwitchBlocksEverything() {
        let settings = FollowNoticeSettings(isEnabled: false)
        XCTAssertFalse(settings.allows(.departed(stop: "Salzburg Hbf"), at: at("12:00"), calendar: vienna))
    }

    func testPerKindSwitch() {
        let settings = FollowNoticeSettings(isEnabled: true, kinds: [.delay, .platform])
        XCTAssertTrue(settings.allows(.delay(minutes: 6, stop: "Wien Hbf"), at: at("12:00"), calendar: vienna))
        XCTAssertTrue(settings.allows(.delayRecovered(stop: "Wien Hbf"), at: at("12:00"), calendar: vienna))
        XCTAssertFalse(settings.allows(.departed(stop: "Salzburg Hbf"), at: at("12:00"), calendar: vienna))
    }

    func testQuietHoursHoldBackNotices() {
        let settings = FollowNoticeSettings(isEnabled: true)
        XCTAssertFalse(settings.allows(.arrivingSoon(stop: "Wien Hbf", minutes: 8), at: at("23:05"), calendar: vienna))
        XCTAssertTrue(settings.allows(.arrivingSoon(stop: "Wien Hbf", minutes: 8), at: at("07:05"), calendar: vienna))
    }

    func testDelayChoicesAreNormalised() {
        XCTAssertEqual(FollowNoticeSettings(delayThresholdMinutes: 10).delayThresholdSeconds, 600)
        XCTAssertEqual(FollowNoticeSettings(delayThresholdMinutes: 7).delayThresholdMinutes, 5)
        XCTAssertEqual(FollowNoticeSettings.delayChoices, [3, 5, 10])
    }

    func testSettingsRoundTripThroughCodable() throws {
        let settings = FollowNoticeSettings(isEnabled: true, delayThresholdMinutes: 3, kinds: [.arrivingSoon],
                                            quietHours: QuietHours(isEnabled: false, startHour: 1, endHour: 2))
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(FollowNoticeSettings.self, from: data), settings)
    }
}
