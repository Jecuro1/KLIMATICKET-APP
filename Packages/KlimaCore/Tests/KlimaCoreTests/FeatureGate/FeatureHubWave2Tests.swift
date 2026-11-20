import XCTest
@testable import KlimaCore

/// MARK: integrate-wave2 – Einstellungen › Funktionen lists the features of the second wave that have a state of their own
/// (Aussteige-Wecker, Pendel-Modus, Kalender-Vorschläge, Automatik, Tägliche Sicherung): where their switch lives, what they need,
/// and what leaves the iPhone (docs/FUNCTIONS_HUB.md §3).
final class FeatureHubWave2Tests: XCTestCase {
    private let wave2: [FeatureID] = [.exitAlarm, .commute, .calendarSuggestions, .automation, .autoBackup]

    private func context(_ wrapped: [FeatureID: Bool] = [:], live: FeatureLiveState = .ready,
                         noticesBlocked: Bool = false) -> FeatureContext {
        var all: [FeatureID: Bool] = [:]
        for d in FeatureRegistry.all where !d.isHubSwitch { all[d.id] = true }
        for (id, on) in wrapped { all[id] = on }
        return FeatureContext(wrapped: all, live: live, notificationsBlocked: noticesBlocked)
    }

    func testTheyAreWrappedSwitchesWithTheirPlaceAndNoHubStorage() {
        for id in wave2 {
            let d = id.descriptor
            XCTAssertFalse(d.isHubSwitch, "\(id): its switch stays where it is")
            XCTAssertNotNil(d.place, "\(id)")
            XCTAssertNil(d.hiddenEntry, "\(id): nothing is hidden by the hub")
            XCTAssertFalse(d.usesLiveData, "\(id)")
        }
        var settings = FeatureSettings()
        settings.set(.commute, false)
        settings.set(.autoBackup, false)
        XCTAssertTrue(settings.overrides.isEmpty, "the hub never stores a wrapped switch")
        XCTAssertEqual(FeatureID.autoBackup.descriptor.control, .toggle)
        for id in [FeatureID.exitAlarm, .commute, .calendarSuggestions, .automation] {
            XCTAssertEqual(id.descriptor.control, .ownPage, "\(id): switched on its own page")
        }
    }

    func testGroupsAndOrder() {
        XCTAssertEqual(FeatureID.exitAlarm.descriptor.group, .liveData)
        XCTAssertEqual(FeatureID.commute.descriptor.group, .overview)
        XCTAssertEqual(FeatureID.calendarSuggestions.descriptor.group, .overview)
        XCTAssertEqual(FeatureID.automation.descriptor.group, .notices)
        XCTAssertEqual(FeatureRegistry.features(in: .data).map(\.id), [.autoBackup])
        XCTAssertEqual(FeatureGroup.data.title, "Daten")
        XCTAssertEqual(FeatureRegistry.features(in: .liveData).map(\.id), [.liveTimetable, .livePrices, .followNotices, .exitAlarm])
    }

    func testTheExitAlarmFollowsTheTimetableAndTheOfflineMode() {
        XCTAssertTrue(FeatureRegistry.requires(.exitAlarm, .liveTimetable))
        XCTAssertTrue(FeatureGate.isAffectedByOfflineMode(.exitAlarm))
        XCTAssertEqual(FeatureGate.statusLine(.exitAlarm, settings: FeatureSettings(), context: context()), "an")
        XCTAssertEqual(FeatureGate.statusLine(.exitAlarm, settings: FeatureSettings(offlineMode: true), context: context()),
                       "pausiert · Offline-Modus")
        XCTAssertEqual(FeatureGate.statusLine(.exitAlarm, settings: FeatureSettings(), context: context([.liveTimetable: false])),
                       "pausiert · braucht Fahrplan & Echtzeit")
        XCTAssertEqual(FeatureGate.explain(.exitAlarm, settings: FeatureSettings(offlineMode: true), context: context()),
                       "Der Offline-Modus ist an. Es lässt sich kein Wecker stellen, und ein gestellter endet mit einer Mitteilung.")
        // It waits for live data like „Live verfolgen“ does (it uses the follow's answers).
        XCTAssertEqual(FeatureGate.statusLine(.exitAlarm, settings: FeatureSettings(), context: context(live: .consentOpen)),
                       "an · wartet auf Live-Daten")
    }

    func testTheOthersDoNotDependOnLiveDataOrTheOfflineMode() {
        let offline = FeatureSettings(offlineMode: true)
        for id in [FeatureID.commute, .calendarSuggestions, .automation, .autoBackup] {
            XCTAssertFalse(FeatureGate.isAffectedByOfflineMode(id), "\(id)")
            XCTAssertEqual(FeatureGate.statusLine(id, settings: offline, context: context()), "an", "\(id)")
            XCTAssertEqual(FeatureGate.statusLine(id, settings: FeatureSettings(), context: context([id: false])), "aus", "\(id)")
        }
        XCTAssertEqual(FeatureGate.explain(.calendarSuggestions, settings: FeatureSettings(), context: context([.calendarSuggestions: false])),
                       "Kalender-Vorschläge ist aus. Die App liest keine Termine, und die Übersicht schlägt keine Fahrt zu einem Termin vor.")
    }

    func testAutomatikSaysWhenIOSRefusesItsNotices() {
        XCTAssertTrue(FeatureID.automation.descriptor.usesNotifications)
        XCTAssertEqual(FeatureGate.statusLine(.automation, settings: FeatureSettings(), context: context(noticesBlocked: true)),
                       "an · Mitteilungen sind in iOS aus")
        XCTAssertFalse(FeatureID.exitAlarm.descriptor.usesNotifications, "the wake-up alarm can ring through AlarmKit")
        XCTAssertFalse(FeatureID.autoBackup.descriptor.usesNotifications)
    }

    func testWhatLeavesTheIPhone() {
        // Only the Pendel-Karte asks the ÖBB; the rest stays on the device.
        XCTAssertTrue(FeatureID.commute.descriptor.sendsData)
        XCTAssertEqual(FeatureID.commute.descriptor.dataFlows.map(\.recipient), [.oebbTimetable])
        XCTAssertTrue(FeatureID.commute.descriptor.dataFlows[0].when.contains("einmal pro Minute"))
        for id in [FeatureID.exitAlarm, .calendarSuggestions, .automation, .autoBackup] {
            XCTAssertFalse(id.descriptor.sendsData, "\(id)")
            XCTAssertTrue(FeaturePrivacy.localFeatures.contains(id), "\(id)")
        }
        XCTAssertTrue(FeatureID.exitAlarm.descriptor.dataFlows[0].sends.contains("nie gesendet"))
        XCTAssertTrue(FeatureID.calendarSuggestions.descriptor.dataFlows[0].sends.contains("nie gespeichert"))
        let oebb = FeaturePrivacy.recipients().first { $0.recipient == .oebbTimetable }
        XCTAssertTrue(oebb?.items.contains { $0.source == .feature(.commute) } == true)
    }

    func testTheHubCountsEveryFeature() {
        XCTAssertEqual(FeatureID.allCases.count, 20)
        XCTAssertEqual(FeatureGate.onCount(settings: FeatureSettings(), context: context()), 20)
        let offWave2 = context([.commute: false, .calendarSuggestions: false, .automation: false])
        XCTAssertEqual(FeatureGate.onCount(settings: FeatureSettings(), context: offWave2), 17)
        XCTAssertTrue(FeatureGate.hiddenNotes(settings: FeatureSettings(), context: offWave2).isEmpty)
    }
}
