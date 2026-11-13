import XCTest
@testable import KlimaCore

/// MARK: funktionen – Einstellungen › Funktionen (docs/FUNCTIONS_HUB.md): registry, stored settings, the gate and its texts.
final class FeatureGateTests: XCTestCase {
    /// Every wrapped switch on, live data ready – like a fresh install after „Aktivieren“.
    private func context(_ wrapped: [FeatureID: Bool] = [:], live: FeatureLiveState = .ready) -> FeatureContext {
        var all: [FeatureID: Bool] = [:]
        for d in FeatureRegistry.all where !d.isHubSwitch { all[d.id] = true }
        for (id, on) in wrapped { all[id] = on }
        return FeatureContext(wrapped: all, live: live)
    }

    // MARK: Registry

    func testRegistryHasNoDuplicateIDsAndEveryDescriptorNamesARecipient() {
        let ids = FeatureRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids, FeatureID.allCases)
        for d in FeatureRegistry.all {
            XCTAssertFalse(d.dataFlows.isEmpty, "\(d.id) names no recipient")
            for flow in d.dataFlows {
                XCTAssertFalse(flow.sends.isEmpty, "\(d.id)")
                XCTAssertFalse(flow.when.isEmpty, "\(d.id)")
            }
            XCTAssertFalse(d.title.isEmpty)
            XCTAssertFalse(d.line.isEmpty)
            XCTAssertTrue(d.offEffect.hasSuffix("."), "\(d.id): the off effect is a sentence")
            XCTAssertFalse(d.dependencies.contains(d.id), "\(d.id) needs itself")
            XCTAssertFalse(FeatureRegistry.requires(d.id, d.id), "\(d.id) has a dependency cycle")
            if d.isHubSwitch { XCTAssertNil(d.place) } else { XCTAssertNotNil(d.place, "\(d.id): a wrapped switch names its place") }
        }
    }

    func testEveryGroupHasFeaturesAndTheHubSwitchesAreTheNewOnes() {
        for group in FeatureGroup.allCases { XCTAssertFalse(FeatureRegistry.features(in: group).isEmpty, "\(group)") }
        let hub = FeatureRegistry.all.filter(\.isHubSwitch).map(\.id)
        XCTAssertEqual(Set(hub), [.radar, .trainSearch, .disruptions, .perksCard, .achievementsTeaser, .weekInsight])
        // A hidden entry point is what makes a hub switch visible – every new switch hides one.
        for id in hub { XCTAssertNotNil(id.descriptor.hiddenEntry, "\(id)") }
    }

    func testDependenciesAndDependents() {
        XCTAssertTrue(FeatureRegistry.requires(.radar, .liveTimetable))
        XCTAssertTrue(FeatureRegistry.requires(.trainSearch, .liveTimetable))
        XCTAssertFalse(FeatureRegistry.requires(.perksCard, .liveTimetable))
        XCTAssertEqual(Set(FeatureRegistry.dependents(of: .liveTimetable)), [.followNotices, .radar, .trainSearch, .disruptions])
        XCTAssertTrue(FeatureGate.isAffectedByOfflineMode(.radar))
        XCTAssertTrue(FeatureGate.isAffectedByOfflineMode(.livePrices))
        XCTAssertFalse(FeatureGate.isAffectedByOfflineMode(.weekInsight))
        XCTAssertFalse(FeatureGate.isAffectedByOfflineMode(.tripDetection))
    }

    // MARK: Settings

    func testDefaultsAreAllOn() {
        let settings = FeatureSettings.standard
        let ctx = context()
        XCTAssertFalse(settings.offlineMode)
        for d in FeatureRegistry.all where d.isHubSwitch {
            XCTAssertEqual(settings.hubSwitch(d.id), true, "\(d.id)")
            XCTAssertTrue(FeatureGate.isOn(d.id, settings: settings, context: ctx), "\(d.id)")
            XCTAssertEqual(FeatureGate.statusLine(d.id, settings: settings, context: ctx), "an")
            XCTAssertNil(FeatureGate.explain(d.id, settings: settings, context: ctx))
        }
        XCTAssertEqual(FeatureGate.onCount(settings: settings, context: ctx), FeatureID.allCases.count)
        XCTAssertTrue(FeatureGate.hiddenNotes(settings: settings, context: ctx).isEmpty)
    }

    func testOverrideBeatsDefaultAndOnlyDifferencesAreStored() {
        var settings = FeatureSettings()
        settings.set(.radar, false)
        XCTAssertEqual(settings.overrides, [.radar: false])
        XCTAssertFalse(FeatureGate.isOn(.radar, settings: settings, context: context()))
        settings.set(.radar, true)
        XCTAssertTrue(settings.overrides.isEmpty, "back to the default stores nothing")
        // Wrapped ids live elsewhere: the hub never stores them.
        settings.set(.liveTimetable, false)
        XCTAssertTrue(settings.overrides.isEmpty)
        XCTAssertNil(settings.hubSwitch(.liveTimetable))
    }

    func testStorageRoundTrip() {
        var settings = FeatureSettings(offlineMode: true)
        settings.set(.weekInsight, false)
        settings.set(.trainSearch, false)
        let decoded = FeatureSettings.decode(settings.encoded())
        XCTAssertEqual(decoded, settings)
        let json = String(decoding: settings.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"version\":1"), json)
        XCTAssertEqual(FeatureSettings.storageKey, "features.v1")
    }

    func testGarbageGivesDefaults() {
        XCTAssertEqual(FeatureSettings.decode(nil), .standard)
        XCTAssertEqual(FeatureSettings.decode(Data()), .standard)
        XCTAssertEqual(FeatureSettings.decode(Data("not json".utf8)), .standard)
        XCTAssertEqual(FeatureSettings.decode(Data("[1,2,3]".utf8)), .standard)
        XCTAssertEqual(FeatureSettings.decode(Data("\"radar\"".utf8)), .standard)
        XCTAssertEqual(FeatureSettings.decode(Data("{\"version\":0,\"offlineMode\":true}".utf8)), .standard)
        XCTAssertEqual(FeatureSettings.decode(Data("{\"offlineMode\":true}".utf8)), .standard, "no version: not ours")
    }

    func testUnknownIdsAndBadValuesAreIgnored() {
        let json = """
        {"version":1,"offlineMode":"yes","overrides":{"radar":false,"teleporter":false,"liveTimetable":false,"weekInsight":"off","perksCard":0,"disruptions":false}}
        """
        let settings = FeatureSettings.decode(Data(json.utf8))
        XCTAssertEqual(settings.overrides, [.radar: false, .disruptions: false])
        XCTAssertFalse(settings.offlineMode, "a non-boolean offline value is ignored")
        // A newer version keeps the keys it shares with this one.
        let newer = FeatureSettings.decode(Data("{\"version\":2,\"offlineMode\":true,\"overrides\":{\"radar\":false},\"extra\":1}".utf8))
        XCTAssertTrue(newer.offlineMode)
        XCTAssertEqual(newer.overrides, [.radar: false])
    }

    // MARK: Gate

    func testRadarIsOffWhenTheTimetableIsOffWithTheExplanation() {
        let settings = FeatureSettings()
        let ctx = context([.liveTimetable: false])
        let status = FeatureGate.status(.radar, settings: settings, context: ctx)
        XCTAssertTrue(status.switchIsOn, "the radar's own switch stays on")
        XCTAssertEqual(status.offReason, .needs(.liveTimetable))
        XCTAssertFalse(FeatureGate.isOn(.trainSearch, settings: settings, context: ctx))
        XCTAssertFalse(FeatureGate.isOn(.disruptions, settings: settings, context: ctx))
        XCTAssertTrue(FeatureGate.isOn(.weekInsight, settings: settings, context: ctx))
        XCTAssertEqual(FeatureGate.statusLine(.radar, settings: settings, context: ctx), "ausgeblendet · braucht Fahrplan & Echtzeit")
        XCTAssertEqual(FeatureGate.explain(.radar, settings: settings, context: ctx),
                       "Zug-Radar braucht „Fahrplan & Echtzeit“. Der Radar-Knopf im Fahrplan ist ausgeblendet; Widget-Knopf und Link öffnen dann diese Seite.")
        XCTAssertEqual(FeatureGate.statusLine(.followNotices, settings: settings, context: context([.liveTimetable: false])),
                       "pausiert · braucht Fahrplan & Echtzeit")
        let notes = FeatureGate.hiddenNotes(settings: settings, context: ctx).map(\.text)
        XCTAssertEqual(notes.first, "Zug-Radar braucht Fahrplan & Echtzeit – der Radar-Knopf im Fahrplan ist ausgeblendet.")
        XCTAssertEqual(notes.count, 3)
    }

    func testOwnSwitchExplainsFirst() {
        var settings = FeatureSettings(offlineMode: true)
        settings.set(.radar, false)
        let ctx = context([.liveTimetable: false])
        XCTAssertEqual(FeatureGate.status(.radar, settings: settings, context: ctx).offReason, .switchedOff)
        XCTAssertEqual(FeatureGate.statusLine(.radar, settings: settings, context: ctx), "aus")
        XCTAssertEqual(FeatureGate.explain(.radar, settings: settings, context: ctx),
                       "Zug-Radar ist aus. Der Radar-Knopf im Fahrplan ist ausgeblendet; Widget-Knopf und Link öffnen dann diese Seite.")
        XCTAssertEqual(FeatureGate.hiddenNotes(settings: settings, context: ctx).first?.text,
                       "Zug-Radar ist aus – der Radar-Knopf im Fahrplan ist ausgeblendet.")
    }

    func testOfflineModeWinsOverSwitches() {
        let settings = FeatureSettings(offlineMode: true)
        let ctx = context()
        for id in [FeatureID.liveTimetable, .livePrices, .radar, .trainSearch, .disruptions, .followNotices] {
            XCTAssertEqual(FeatureGate.status(id, settings: settings, context: ctx).offReason, .offlineMode, "\(id)")
            XCTAssertTrue(FeatureGate.status(id, settings: settings, context: ctx).switchIsOn, "\(id): the switch itself is untouched")
        }
        for id in [FeatureID.perksCard, .weekInsight, .achievementsTeaser, .assistant, .haptics, .officialLogos, .tripDetection,
                   .renewalReminders, .weeklySummary] {
            XCTAssertTrue(FeatureGate.isOn(id, settings: settings, context: ctx), "\(id) does not use live data")
        }
        XCTAssertEqual(FeatureGate.statusLine(.radar, settings: settings, context: ctx), "ausgeblendet · Offline-Modus")
        XCTAssertEqual(FeatureGate.statusLine(.livePrices, settings: settings, context: ctx), "pausiert · Offline-Modus")
        XCTAssertEqual(FeatureGate.explain(.livePrices, settings: settings, context: ctx),
                       "Der Offline-Modus ist an. Preise kommen aus den Tarif-Tabellen auf dem iPhone.")
        XCTAssertEqual(FeatureGate.hiddenNotes(settings: settings, context: ctx).map(\.id), [.radar, .trainSearch, .disruptions])
        XCTAssertEqual(FeatureGate.hiddenNotes(settings: settings, context: ctx).first?.text,
                       "Offline-Modus – der Radar-Knopf im Fahrplan ist ausgeblendet.")
    }

    func testWaitingForLiveDataIsOnWithAStatusLine() {
        let settings = FeatureSettings()
        XCTAssertEqual(FeatureGate.statusLine(.radar, settings: settings, context: context(live: .consentOpen)), "an · wartet auf Live-Daten")
        XCTAssertEqual(FeatureGate.statusLine(.radar, settings: settings, context: context(live: .declined)), "an · Live-Daten sind abgelehnt")
        XCTAssertEqual(FeatureGate.statusLine(.livePrices, settings: settings, context: context(live: .remoteOff)),
                       "an · ÖBB-Abfrage gerade abgeschaltet")
        XCTAssertEqual(FeatureGate.statusLine(.trainSearch, settings: settings, context: context(live: .noInternet)), "an · kein Internet")
        XCTAssertTrue(FeatureGate.isOn(.radar, settings: settings, context: context(live: .consentOpen)), "consent is not a switch of the hub")
        XCTAssertEqual(FeatureGate.statusLine(.weekInsight, settings: settings, context: context(live: .consentOpen)), "an")
        XCTAssertNil(FeatureGate.status(.weekInsight, settings: settings, context: context(live: .declined)).waiting)
    }

    func testWrappedSwitchesComeFromTheContext() {
        let settings = FeatureSettings()
        XCTAssertFalse(FeatureGate.isOn(.weeklySummary, settings: settings, context: context([.weeklySummary: false])))
        XCTAssertEqual(FeatureGate.statusLine(.weeklySummary, settings: settings, context: context([.weeklySummary: false])), "aus")
        XCTAssertEqual(FeatureGate.explain(.weeklySummary, settings: settings, context: context([.weeklySummary: false])),
                       "Wochenrückblick ist aus. Sonntags kommt kein Wochenrückblick.")
        // A missing wrapped value counts as off; nothing is invented.
        XCTAssertFalse(FeatureGate.isOn(.haptics, settings: settings, context: FeatureContext()))
    }

    func testExplainTextsForEveryState() {
        for d in FeatureRegistry.all {
            var off = FeatureSettings()
            off.set(d.id, false)
            let ctx = d.isHubSwitch ? context() : context([d.id: false])
            let text = FeatureGate.explain(d.id, settings: off, context: ctx)
            XCTAssertEqual(text, "\(d.title) ist aus. \(d.offEffect)", "\(d.id)")
            XCTAssertEqual(FeatureGate.statusLine(d.id, settings: off, context: ctx), "aus")
            if FeatureGate.isAffectedByOfflineMode(d.id) {
                XCTAssertEqual(FeatureGate.explain(d.id, settings: FeatureSettings(offlineMode: true), context: context()),
                               "Der Offline-Modus ist an. \(d.offEffect)")
            }
        }
    }

    // MARK: Privacy

    func testPrivacyTableCoversEveryRemoteFlow() {
        let table = FeaturePrivacy.recipients()
        XCTAssertEqual(table.map(\.recipient), FeaturePrivacy.remoteOrder)
        XCTAssertFalse(table.contains { $0.recipient == .device })
        for entry in table { XCTAssertFalse(entry.items.isEmpty, "\(entry.recipient) receives nothing") }
        let flows = FeatureRegistry.all.flatMap(\.dataFlows).filter(\.recipient.isRemote).count + FeatureService.allCases.count
        XCTAssertEqual(table.flatMap(\.items).count, flows)
        let ids = table.flatMap(\.items).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(table.first?.items.first?.title, "Fahrplan & Echtzeit")
        XCTAssertTrue(FeaturePrivacy.localFeatures.contains(.weekInsight))
        XCTAssertFalse(FeaturePrivacy.localFeatures.contains(.radar))
        XCTAssertEqual(FeatureRecipient.oebbTimetable.liveProvider, .oebbHafas)
        XCTAssertNil(FeatureRecipient.cloud.liveProvider)
    }

    func testCounterLine() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(FeaturePrivacy.counterLine(.zero, lastText: nil), "Keine Anfrage seit dem Start der App")
        XCTAssertEqual(FeaturePrivacy.counterLine(RequestCounters(lastMinute: 3, total: 41, last: date), lastText: "14:31:12"),
                       "3 Anfragen in der letzten Minute, 41 seit dem Start · zuletzt 14:31:12")
        XCTAssertEqual(FeaturePrivacy.counterLine(RequestCounters(lastMinute: 1, total: 1, last: date), lastText: "09:00:00"),
                       "1 Anfrage in der letzten Minute, 1 seit dem Start · zuletzt 09:00:00")
        XCTAssertEqual(FeaturePrivacy.counterLine(RequestCounters(lastMinute: 0, total: 7, last: date), lastText: nil),
                       "0 Anfragen in der letzten Minute, 7 seit dem Start")
    }
}

/// MARK: funktionen – the request counters of `RequestThrottle` (Funktionen › Datenschutz).
final class FeatureGateThrottleCounterTests: XCTestCase {
    static let start = ISO.date("2026-11-13T10:00:00Z")!

    func testCountersAfterNAcquiresAndAfterTheWindowSlides() async throws {
        let clock = FakeClock(Self.start)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        var zero = await throttle.counters(.oebbHafas)
        XCTAssertEqual(zero, .zero)
        for _ in 0..<5 { try await throttle.acquire(.oebbHafas, minInterval: 0.3, perMinute: 40) }
        var counters = await throttle.counters(.oebbHafas)
        XCTAssertEqual(counters.lastMinute, 5)
        XCTAssertEqual(counters.total, 5)
        XCTAssertEqual(counters.last?.timeIntervalSince(Self.start) ?? -1, 1.2, accuracy: 1e-5)
        let total = await throttle.totalAcquired(.oebbHafas)
        XCTAssertEqual(total, 5)
        let last = await throttle.lastAcquired(.oebbHafas)
        XCTAssertEqual(last, counters.last)
        // Providers are counted apart.
        zero = await throttle.counters(.oebbShop)
        XCTAssertEqual(zero, .zero)

        // The window slides: a minute later the minute is empty, the total stays.
        clock.advance(61)
        counters = await throttle.counters(.oebbHafas)
        XCTAssertEqual(counters.lastMinute, 0)
        XCTAssertEqual(counters.total, 5)
        try await throttle.acquire(.oebbHafas, minInterval: 0.3, perMinute: 40)
        counters = await throttle.counters(.oebbHafas)
        XCTAssertEqual(counters.lastMinute, 1)
        XCTAssertEqual(counters.total, 6)
        XCTAssertEqual(counters.last, clock.now)
        let all = await throttle.allCounters()
        XCTAssertEqual(all.count, LiveProvider.allCases.count)
        XCTAssertEqual(all[.oebbHafas], counters)
    }

    func testARefusedRequestIsNotCounted() async throws {
        let clock = FakeClock(Self.start)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        for _ in 0..<12 { try await throttle.acquire(.oebbShop, minInterval: 1, perMinute: 12) }
        do { try await throttle.acquire(.oebbShop, minInterval: 1, perMinute: 12); XCTFail() } catch {}
        let counters = await throttle.counters(.oebbShop)
        XCTAssertEqual(counters.total, 12)
        XCTAssertEqual(counters.lastMinute, 12)
    }

    func testCountersMoveWithTheRequestsAClientSends() async throws {
        let clock = FakeClock(Self.start)
        let transport = FixtureTransport(routes: [.init(urlSuffix: "fahrplan.oebb.at/gate",
                                                        response: try Fixture.hafasResponse("locmatch_innsbruck"))])
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        let client = HafasClient(config: .default, transport: transport, throttle: throttle, health: LiveHealth(clock: clock.closure),
                                 appVersion: "1", clock: clock.closure, sleeper: clock.sleeper)
        for i in 0..<3 { _ = try await client.locations("Innsbruck \(i)", types: .all, maxResults: 8) }
        let counters = await throttle.counters(.oebbHafas)
        XCTAssertEqual(counters.total, transport.recorded.count)
        XCTAssertEqual(counters.total, 3)
        XCTAssertEqual(counters.lastMinute, 3)
        let shop = await throttle.counters(.oebbShop)
        XCTAssertEqual(shop.total, 0)
    }
}
