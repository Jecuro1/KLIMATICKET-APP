import XCTest
@testable import KlimaCore

// MARK: data – checksum, file names, retention, the restore preview, the settings policy and the envelope (docs/DATA_HUB.md).

private let vienna = Calendar.vienna

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var c = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    c.timeZone = vienna.timeZone
    return vienna.date(from: c)!
}

final class DataHubChecksumTests: XCTestCase {
    func testCRC32KnownVectors() {
        XCTAssertEqual(DataHubCRC32.hex(DataHubCRC32.checksum(Data("123456789".utf8))), "cbf43926")
        XCTAssertEqual(DataHubCRC32.hex(DataHubCRC32.checksum(Data())), "00000000")
        XCTAssertEqual(DataHubCRC32.hex(DataHubCRC32.checksum(Data("The quick brown fox jumps over the lazy dog".utf8))), "414fa339")
    }

    private func sampleFile(note: String = "Pendeln") -> Data {
        let json = """
        {
          "appVersion" : "1.3.0",
          "benefits" : [
            { "note" : "\(note)", "title" : "checksum" }
          ],
          "checksum" : "crc32:00000000",
          "favorites" : [],
          "format" : "klimabilanz-backup",
          "tickets" : [],
          "trips" : [],
          "version" : 3
        }
        """
        return Data(json.utf8)
    }

    func testSealThenVerifyIsIntact() throws {
        let sealed = try XCTUnwrap(BackupChecksum.seal(sampleFile()))
        guard case .intact(let value) = BackupChecksum.verify(sealed) else { return XCTFail("not intact") }
        XCTAssertEqual(value.count, 8)
        XCTAssertTrue(String(decoding: sealed, as: UTF8.self).contains("\"checksum\" : \"crc32:\(value)\""))
    }

    func testOneChangedByteIsDetected() throws {
        var sealed = try XCTUnwrap(BackupChecksum.seal(sampleFile()))
        let index = try XCTUnwrap(String(decoding: sealed, as: UTF8.self).utf8.firstIndex(of: UInt8(ascii: "P")))
        let offset = String(decoding: sealed, as: UTF8.self).utf8.distance(from: String(decoding: sealed, as: UTF8.self).utf8.startIndex, to: index)
        sealed[sealed.startIndex + offset] = UInt8(ascii: "Q")
        XCTAssertTrue(BackupChecksum.verify(sealed).isDamaged)
        // A cut copy is damaged too (or no backup at all).
        let cut = sealed.prefix(sealed.count - 40)
        XCTAssertNotEqual(BackupInspection.inspect(Data(cut)).canRestore, true)
    }

    func testWordInANoteIsNotTheKey() throws {
        // „checksum“ as a value and as escaped text inside a note: only the real key counts.
        let file = sampleFile(note: "mein \\\"checksum\\\": \\\"crc32:12345678\\\" Test")
        let sealed = try XCTUnwrap(BackupChecksum.seal(file))
        XCTAssertFalse(BackupChecksum.verify(sealed).isDamaged)
        XCTAssertNil(BackupChecksum.seal(Data("{\"trips\":[]}".utf8)), "no placeholder, nothing to seal")
        XCTAssertEqual(BackupChecksum.verify(Data("{\"trips\":[]}".utf8)), .missing)
    }

    func testVerdictCopyIsHonest() {
        XCTAssertTrue(BackupChecksum.honestyNote.contains("erkennt beschädigte Dateien"))
        XCTAssertTrue(BackupChecksum.honestyNote.contains("beweist sie nicht"))
        XCTAssertTrue(BackupChecksum.Verdict.damaged(expected: "a", actual: "b").line.contains("nicht"))
    }
}

final class DataHubFileNameTests: XCTestCase {
    func testMakeAndParse() throws {
        let date = at(2026, 11, 19, 18, 3)
        XCTAssertEqual(BackupFileName.make(date: date, kind: .daily), "KlimaBilanz-2026-11-19-1803.json")
        XCTAssertEqual(BackupFileName.make(date: date, kind: .beforeDelete), "KlimaBilanz-2026-11-19-1803-vor-dem-Loeschen.json")
        XCTAssertEqual(BackupFileName.make(date: date, kind: .beforeRestore), "KlimaBilanz-2026-11-19-1803-vor-dem-Wiederherstellen.json")
        for kind in BackupKind.allCases {
            let parsed = try XCTUnwrap(BackupFileName.parse(BackupFileName.make(date: date, kind: kind)))
            XCTAssertEqual(parsed, .init(date: date, kind: kind))
        }
        XCTAssertEqual(BackupFileName.parse("KlimaBilanz-2026-11-19-1803~2.json")?.kind, .daily)
        XCTAssertEqual(BackupFileName.parse("KlimaBilanz-2026-11-19-1803-vor-dem-Loeschen~3.json")?.kind, .beforeDelete)
    }

    func testForeignNamesAreNotOurs() {
        for name in ["KlimaBilanz-2026-02-31-1200.json", "KlimaBilanz-2026-11-19.json", "Kopie von KlimaBilanz-2026-11-19-1803.json",
                     "KlimaBilanz-2026-11-19-1803.txt", "KlimaBilanz-2026-11-19-2460.json", "KlimaBilanz-2026-11-19-1803~x.json",
                     "KlimaBilanz-2026-11-19-1803-Backup.json"] {
            XCTAssertNil(BackupFileName.parse(name), name)
        }
    }

    func testUniqueName() {
        let taken: Set<String> = ["KlimaBilanz-2026-11-19-1803.json", "KlimaBilanz-2026-11-19-1803~2.json"]
        XCTAssertEqual(BackupFileName.unique("KlimaBilanz-2026-11-19-1803.json", exists: taken.contains), "KlimaBilanz-2026-11-19-1803~3.json")
        XCTAssertEqual(BackupFileName.unique("KlimaBilanz-2026-11-20-0800.json", exists: taken.contains), "KlimaBilanz-2026-11-20-0800.json")
    }
}

final class DataHubRetentionTests: XCTestCase {
    private func daily(_ date: Date) -> BackupRetention.Entry {
        BackupRetention.Entry(id: BackupFileName.make(date: date, kind: .daily), date: date, kind: .daily)
    }

    /// One backup every evening from September to 10 January 2027: the last 7 days, the newest of the last 4 ISO weeks (across the
    /// year's end: 28 Dec 2026 – 3 Jan 2027 is week 53 of 2026) and the newest of the last 3 months stay.
    func testSevenDailyFourWeeklyThreeMonthlyAcrossTheYearsEnd() {
        var entries: [BackupRetention.Entry] = []
        var day = at(2026, 9, 1, 18, 3)
        while day <= at(2027, 1, 10, 18, 3) {
            entries.append(daily(day))
            day = vienna.date(byAdding: .day, value: 1, to: day)!
        }
        let plan = BackupRetention.plan(entries.shuffled(), now: at(2027, 1, 10, 20))
        let expected = [at(2027, 1, 10, 18, 3), at(2027, 1, 9, 18, 3), at(2027, 1, 8, 18, 3), at(2027, 1, 7, 18, 3),
                        at(2027, 1, 6, 18, 3), at(2027, 1, 5, 18, 3), at(2027, 1, 4, 18, 3),   // daily
                        at(2027, 1, 3, 18, 3),                                                   // week 53 of 2026
                        at(2026, 12, 31, 18, 3),                                                 // December
                        at(2026, 12, 27, 18, 3), at(2026, 12, 20, 18, 3),                        // weeks 52 and 51
                        at(2026, 11, 30, 18, 3)]                                                 // November
            .map { BackupFileName.make(date: $0, kind: .daily) }
        XCTAssertEqual(plan.keep, expected)
        XCTAssertEqual(plan.keep.count + plan.delete.count, entries.count)
        XCTAssertEqual(plan.keep.first, BackupFileName.make(date: at(2027, 1, 10, 18, 3), kind: .daily), "newest first and kept")
    }

    /// Daylight saving time ends on 25 October 2026: 00:30 and 23:30 of that Sunday are one day in Vienna.
    func testDaysFollowViennaAcrossDST() {
        let entries = [at(2026, 10, 24, 23, 30), at(2026, 10, 25, 0, 30), at(2026, 10, 25, 23, 30), at(2026, 10, 26, 0, 30)].map(daily)
        let plan = BackupRetention.plan(entries, now: at(2026, 10, 26, 12))
        XCTAssertEqual(plan.delete, [BackupFileName.make(date: at(2026, 10, 25, 0, 30), kind: .daily)])
        // And when it begins (28 March 2027, 02:00 → 03:00).
        let simple = [at(2027, 3, 28, 1, 30), at(2027, 3, 28, 23, 30)].map(daily)
        XCTAssertEqual(BackupRetention.plan(simple, now: at(2027, 3, 29)).delete, [BackupFileName.make(date: at(2027, 3, 28, 1, 30), kind: .daily)])
    }

    func testNewestIsNeverDeleted() {
        let old = BackupRetention.Entry(id: "a", date: at(2026, 1, 1), kind: .beforeDelete)
        XCTAssertEqual(BackupRetention.plan([old], now: at(2026, 11, 19)).keep, ["a"], "the only backup stays even after 30 days")
        let older = BackupRetention.Entry(id: "b", date: at(2025, 12, 1), kind: .beforeRestore)
        XCTAssertEqual(BackupRetention.plan([old, older], now: at(2026, 11, 19)), .init(keep: ["a"], delete: ["b"]))
        XCTAssertEqual(BackupRetention.plan([], now: at(2026, 11, 19)), .init(keep: [], delete: []))
        // Fuzz: whatever the set, the newest file stays.
        for seed in 0..<50 {
            var generator = DataHubSeededGenerator(seed: UInt64(seed + 1))
            let entries = (0..<Int.random(in: 1...60, using: &generator)).map { index -> BackupRetention.Entry in
                let date = at(2026, 1, 1).addingTimeInterval(Double.random(in: 0...(330 * 86_400), using: &generator))
                let kind = BackupKind.allCases.randomElement(using: &generator)!
                return .init(id: "f\(index)", date: date, kind: kind)
            }
            let newest = entries.max { ($0.date, $0.id) < ($1.date, $1.id) }!
            let plan = BackupRetention.plan(entries, now: at(2026, 11, 30))
            XCTAssertTrue(plan.keep.contains(newest.id))
            XCTAssertEqual(Set(plan.keep).union(plan.delete).count, entries.count)
        }
    }

    func testSafetyBackupsStayThirtyDays() {
        let entries = (0..<19).map { daily(at(2026, 11, 19 - $0, 18)) }
        let young = BackupRetention.Entry(id: "young", date: at(2026, 11, 1, 14), kind: .beforeDelete)
        let old = BackupRetention.Entry(id: "old", date: at(2026, 10, 15, 14), kind: .beforeRestore)
        let plan = BackupRetention.plan(entries + [young, old], now: at(2026, 11, 19, 20))
        XCTAssertTrue(plan.keep.contains("young"))
        XCTAssertTrue(plan.delete.contains("old"))
    }

    func testFutureDatedFilesStay() {
        let entries = (1...15).map { daily(at(2026, 11, $0, 18)) } + [daily(at(2027, 5, 1, 18))]
        let plan = BackupRetention.plan(entries, now: at(2026, 11, 15, 20))
        XCTAssertTrue(plan.keep.contains(BackupFileName.make(date: at(2027, 5, 1, 18), kind: .daily)))
        XCTAssertTrue(plan.keep.contains(BackupFileName.make(date: at(2026, 11, 15, 18), kind: .daily)))
    }
}

final class DataHubDiffTests: XCTestCase {
    private let t1 = at(2026, 10, 1), t2 = at(2026, 10, 2), t3 = at(2026, 10, 3)

    func testCountsFollowTheMergeRule() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID(), f = UUID(), g = UUID(), h = UUID()
        let current: [BackupTable: [BackupRowStamp]] = [.trips: [
            .init(id: a, updatedAt: t1, isDeleted: false),
            .init(id: b, updatedAt: t1, isDeleted: false),
            .init(id: c, updatedAt: t2, isDeleted: true),
            .init(id: f, updatedAt: t3, isDeleted: false),
            .init(id: g, updatedAt: t1, isDeleted: false),
            .init(id: h, updatedAt: t3, isDeleted: true),
        ]]
        let file: [BackupTable: [BackupRowStamp]] = [
            .trips: [
                .init(id: a, updatedAt: t1, isDeleted: false),   // unchanged
                .init(id: b, updatedAt: t2, isDeleted: false),   // changed
                .init(id: c, updatedAt: t3, isDeleted: false),   // deleted here, alive and newer in the file: back
                .init(id: d, updatedAt: t1, isDeleted: false),   // new
                .init(id: d, updatedAt: t2, isDeleted: false),   // the same row twice counts once
                .init(id: e, updatedAt: t1, isDeleted: true),    // a deletion the iPhone never saw: nothing visible
                .init(id: f, updatedAt: t1, isDeleted: false),   // newer here
                .init(id: g, updatedAt: t2, isDeleted: true),    // deleted in the newer file: removed
                .init(id: h, updatedAt: t1, isDeleted: false),   // deleted here later: the older copy does not bring it back
            ],
            .tickets: [.init(id: UUID(), updatedAt: t1, isDeleted: false)],
        ]
        let diff = BackupDiff.make(file: file, current: current)
        let trips = diff.table(.trips)
        XCTAssertEqual([trips.added, trips.changed, trips.removed, trips.deletedInFile, trips.unchanged, trips.newerHere, trips.deletedHere],
                       [2, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(diff.table(.tickets).added, 1)
        XCTAssertEqual(diff.table(.benefits).changes, 0)
        XCTAssertEqual(diff.changes, 5)
        XCTAssertEqual(diff.headline, "Das ändert sich: 2 neue Fahrten, 1 geänderte, 1 entfernte, 1 unverändert; dazu 1 Ticket.")
        XCTAssertEqual(diff.keepsLine, "1 Eintrag ist auf diesem iPhone neuer und bleibt, wie er ist. "
                       + "1 Eintrag, den du hier nach dieser Sicherung gelöscht hast, bleibt gelöscht.")
        XCTAssertEqual(trips.line, "2 neu · 1 geändert · 1 entfernt · 1 unverändert · 1 hier neuer · 1 hier gelöscht")
    }

    func testSpecExampleSentence() {
        var current: [BackupRowStamp] = []
        var file: [BackupRowStamp] = []
        for _ in 0..<140 { let id = UUID(); current.append(.init(id: id, updatedAt: t1, isDeleted: false)); file.append(.init(id: id, updatedAt: t1, isDeleted: false)) }
        for _ in 0..<3 { let id = UUID(); current.append(.init(id: id, updatedAt: t1, isDeleted: false)); file.append(.init(id: id, updatedAt: t2, isDeleted: false)) }
        for _ in 0..<12 { file.append(.init(id: UUID(), updatedAt: t2, isDeleted: false)) }
        let diff = BackupDiff.make(file: [.trips: file], current: [.trips: current])
        XCTAssertEqual(diff.headline, "Das ändert sich: 12 neue Fahrten, 3 geänderte, 140 unverändert.")
        XCTAssertNil(diff.keepsLine)
    }

    /// A backup keeps whole seconds; the iPhone keeps fractions. The same version must count as unchanged, not as „hier neuer“
    /// (the first screenshots said „75 hier neuer“ for a file of the same data).
    func testWholeSecondsOfAFileAreTheSameVersion() {
        let a = UUID(), b = UUID(), c = UUID()
        let current: [BackupTable: [BackupRowStamp]] = [.trips: [
            .init(id: a, updatedAt: t1.addingTimeInterval(0.73), isDeleted: false),
            .init(id: b, updatedAt: t1.addingTimeInterval(0.4), isDeleted: true),
            .init(id: c, updatedAt: t1.addingTimeInterval(1.2), isDeleted: false),
        ]]
        let file: [BackupTable: [BackupRowStamp]] = [.trips: [
            .init(id: a, updatedAt: t1, isDeleted: false),
            .init(id: b, updatedAt: t1, isDeleted: true),
            .init(id: c, updatedAt: t1, isDeleted: false),
        ]]
        let trips = BackupDiff.make(file: file, current: current).table(.trips)
        XCTAssertEqual([trips.unchanged, trips.newerHere, trips.changes, trips.deletedHere], [1, 1, 0, 0])
    }

    func testNothingChanges() {
        let id = UUID()
        let rows: [BackupTable: [BackupRowStamp]] = [.favorites: [.init(id: id, updatedAt: t2, isDeleted: false)]]
        let diff = BackupDiff.make(file: rows, current: rows)
        XCTAssertEqual(diff.changes, 0)
        XCTAssertTrue(diff.headline.hasPrefix("Nichts ändert sich"))
        XCTAssertEqual(diff.table(.favorites).line, "1 unverändert")
        let other = BackupDiff.make(file: [.benefits: [.init(id: UUID(), updatedAt: t1, isDeleted: false)]], current: [:])
        XCTAssertEqual(other.headline, "Das ändert sich: 1 Vorteil.")
    }
}

final class DataHubSettingsPolicyTests: XCTestCase {
    func testAllowListPasses() {
        let values: [String: BackupSettingValue] = [
            "appearance": .string("dark"), "theme.v1": .data(Data("{\"palette\":\"glacier\"}".utf8)),
            "features.v1": .data(Data("{}".utf8)), "radar.display.v1": .string("{}"), "defaultDiscount": .string("vorteilscard"),
            "homeStationID": .string("8100108"), "hapticsEnabled": .bool(true), "rules.v1": .data(Data("[]".utf8)),
            "dash.layout.v1": .strings(["hero", "trips"]), "goals.v1": .int(3), "radar2.mine.v1": .double(1.5),
        ]
        let result = BackupSettingsPolicy.filter(values)
        XCTAssertEqual(Set(result.kept.keys), Set(values.keys))
        XCTAssertEqual(result.refused, [])
    }

    func testPlantedTokenAndConsentAreRefused() {
        let values: [String: BackupSettingValue] = [
            "radar.authToken": .string("abc"),                 // allowed prefix, denied word: refused and reported
            "features.liveConsent": .string("granted"),        // the consent under an allowed prefix
            "liveConsent": .string("granted"),                 // the real consent key: never asked for
            "auth.session": .string("x"), "cloud.config": .string("y"), "sync.lastSync": .double(1),
            "backup.lastCommitStamp": .string("z"), "letters.sender.v1": .data(Data()), "KBScreenshot": .string("a"),
            "theme.v1": .string("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N"),   // a JWT value
            "dash.huge": .data(Data(count: BackupSettingsPolicy.maxValueBytes + 1)),
            "rules.log.v1": .data(Data()), "rules.ledger.v1": .data(Data()),
        ]
        let result = BackupSettingsPolicy.filter(values)
        XCTAssertEqual(result.kept, [:])
        XCTAssertEqual(Set(result.refused), ["radar.authToken", "features.liveConsent", "theme.v1", "dash.huge"])
        // Refused by key (the value checks refuse theme.v1 and dash.huge, whose keys are fine).
        for key in values.keys where key != "theme.v1" && key != "dash.huge" { XCTAssertFalse(BackupSettingsPolicy.allows(key), key) }
        XCTAssertTrue(BackupSettingsPolicy.isDenied("liveConsent"))
        XCTAssertTrue(BackupSettingsPolicy.isDenied("radar.userID"))
    }

    func testValuesRoundTripAndChanges() throws {
        let values: [String: BackupSettingValue] = ["a": .bool(true), "b": .int(7), "c": .double(0.25), "d": .string("x"),
                                                    "e": .strings(["1", "2"]), "f": .data(Data([0, 1, 2]))]
        let data = try JSONEncoder().encode(values)
        XCTAssertEqual(try JSONDecoder().decode([String: BackupSettingValue].self, from: data), values)
        XCTAssertEqual(BackupSettingValue(plist: true), .bool(true))
        XCTAssertEqual(BackupSettingValue(plist: 3), .int(3))
        XCTAssertEqual(BackupSettingValue(plist: 2.5), .double(2.5))
        XCTAssertEqual(BackupSettingValue(plist: ["a"]), .strings(["a"]))
        XCTAssertNil(BackupSettingValue(plist: ["a": 1]))
        let changes = BackupSettingsPolicy.changes(file: ["appearance": .string("dark"), "homeStationID": .string("1"), "liveConsent": .string("granted")],
                                                   current: ["appearance": .string("light"), "homeStationID": .string("1")])
        XCTAssertEqual(changes, ["appearance"])
    }
}

final class DataHubEnvelopeTests: XCTestCase {
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// A version-2 reader: the keys an app of version 1.2 decodes.
    private struct V2Reader: Decodable {
        struct Row: Decodable { var id: UUID }
        var version: Int
        var tickets: [Row]
        var trips: [Row]
        var favorites: [Row]
        var benefits: [Row]?
    }

    private struct V3File: Encodable {
        struct Row: Encodable { var id: UUID; var note: String }
        var format = BackupFormat.name
        var version = BackupFormat.currentVersion
        var exportedAt = at(2026, 11, 19, 18, 3)
        var appVersion = "1.3.0"
        var tickets: [Row] = [Row(id: UUID(), note: "")]
        var trips: [Row] = [Row(id: UUID(), note: "Mit „Umlaut“, Komma; und \"checksum\"")]
        var favorites: [Row] = []
        var benefits: [Row] = []
        var settings: [String: BackupSettingValue] = ["appearance": .string("dark")]
        var checksum = BackupChecksum.placeholder
    }

    func testV3OpensInAVersion2Reader() throws {
        let file = V3File()
        let sealed = try XCTUnwrap(BackupChecksum.seal(try encoder().encode(file)))
        let old = try JSONDecoder().decode(V2Reader.self, from: sealed)
        XCTAssertEqual(old.version, 3)
        XCTAssertEqual(old.trips.map(\.id), file.trips.map(\.id))
        let inspection = BackupInspection.inspect(sealed)
        XCTAssertTrue(inspection.canRestore)
        XCTAssertEqual(inspection.envelope?.settings, ["appearance": .string("dark")])
        XCTAssertEqual(inspection.envelope?.exportedAt, at(2026, 11, 19, 18, 3))
        if case .intact = inspection.verdict {} else { XCTFail("sealed file must be intact") }
    }

    func testVersion2FileStillReads() throws {
        let v2 = """
        {"format":"klimabilanz-backup","version":2,"exportedAt":"2026-10-09T16:00:00Z","appVersion":"1.1.0",
         "tickets":[],"trips":[],"favorites":[],"benefits":[]}
        """
        let inspection = BackupInspection.inspect(Data(v2.utf8))
        XCTAssertTrue(inspection.canRestore)
        XCTAssertEqual(inspection.verdict, .missing)
        XCTAssertEqual(inspection.envelope?.version, 2)
        XCTAssertNil(inspection.envelope?.settings)
        let v1 = #"{"tickets":[],"trips":[],"favorites":[]}"#
        XCTAssertEqual(BackupInspection.inspect(Data(v1.utf8)).envelope?.version, 1)
    }

    func testCorruptedFilesAreRefused() throws {
        var sealed = try XCTUnwrap(BackupChecksum.seal(try encoder().encode(V3File())))
        let range = try XCTUnwrap(sealed.range(of: Data("1.3.0".utf8)))
        sealed.replaceSubrange(range, with: Data("1.3.1".utf8))
        let damaged = BackupInspection.inspect(sealed)
        XCTAssertEqual(damaged.problem, .damaged)
        XCTAssertFalse(damaged.canRestore)
        XCTAssertTrue(damaged.problem!.message.contains("nichts geändert"))
        XCTAssertEqual(BackupInspection.inspect(Data("kein json".utf8)).problem, .notABackup)
        XCTAssertEqual(BackupInspection.inspect(Data(#"{"trips":[]}"#.utf8)).problem, .notABackup)
        XCTAssertEqual(BackupInspection.inspect(Data(#"{"format":"other","tickets":[],"trips":[],"favorites":[]}"#.utf8)).problem,
                       .otherFormat("other"))
        let future = #"{"format":"klimabilanz-backup","version":9,"tickets":[],"trips":[],"favorites":[]}"#
        XCTAssertTrue(BackupInspection.inspect(Data(future.utf8)).isFromNewerApp)
    }
}

/// A small deterministic generator for the fuzz loops.
struct DataHubSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
