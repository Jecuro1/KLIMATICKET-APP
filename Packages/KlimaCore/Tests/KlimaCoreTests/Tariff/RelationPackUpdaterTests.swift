import Foundation
import XCTest
@testable import KlimaCore

/// The refresh chain with a stub downloader: a valid pack replaces the table in use, an invalid one never does, no network
/// leaves everything untouched, and the 24-hour and version rules hold.
final class RelationPackUpdaterTests: XCTestCase {
    private typealias F = TariffFixtures

    private var directory: URL!
    private let tariffsURL = URL(string: "https://github.com/o/r/releases/latest/download/tariffs.json")!
    private let now = TariffFixtures.vienna(2026, 12, 5)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("relpack-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A small table that is "in use" (version 1) and a pack for the timetable change built next to it.
    private struct Setup {
        var table: RelationPriceTable
        var reference: RelationPackValidator.Reference
        var pack: Data
        var info: RelationsPackInfo
    }

    private func setup(version: Int = 2, validFrom: String = "2026-12-13", increase: Double = 1.04) -> Setup {
        let (ids, pairs) = PackBuilder.smallPairs()
        let triples = Data(pairs.flatMap { PackBuilder.le16($0.0) + PackBuilder.le16($0.1) + PackBuilder.le16($0.2) })
        let table = RelationPriceTable(validFrom: "2025-12-14", source: "test", pointIDs: ids, triples: triples, version: 1)
        let raised = pairs.map { ($0.0, $0.1, Int((Double($0.2) * increase).rounded())) }
        let pack = PackBuilder.make(version: version, validFrom: validFrom, pointIDs: ids, pairs: raised)
        return Setup(table: table, reference: .init(table: table), pack: pack,
                     info: PackBuilder.info(for: pack, version: version, validFrom: validFrom))
    }

    private func updater() -> RelationPackUpdater {
        RelationPackUpdater(store: RelationPackStore(directory: directory), validator: PackBuilder.validator)
    }

    /// Counts the calls of the stub downloader.
    private final class Downloads: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var urls: [URL] = []
        func record(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    }

    private func refresh(_ s: Setup, serving data: Data?, info: RelationsPackInfo? = nil, versionInUse: Int = 1,
                         lastAttempt: Date? = nil, force: Bool = false, downloads: Downloads = Downloads(),
                         anchored: Bool = true) async -> RelationPackUpdater.Result {
        await updater().refresh(info: info ?? s.info, tariffsURL: anchored ? tariffsURL : nil, versionInUse: versionInUse,
                                reference: s.reference, lastAttempt: lastAttempt, now: now, force: force) { url, _ in
            downloads.record(url)
            guard let data else { throw URLError(.notConnectedToInternet) }
            return data
        }
    }

    private func storedFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: A valid pack replaces the table in use

    func testAValidPackIsInstalledAndPreferredFromItsValidFromDay() async throws {
        let s = setup()
        let downloads = Downloads()
        let result = await refresh(s, serving: s.pack, downloads: downloads)
        XCTAssertEqual(result, .init(outcome: .installed(version: 2), attempted: true))
        XCTAssertEqual(downloads.urls.map(\.absoluteString),
                       ["https://github.com/o/r/releases/latest/download/relations-pack.bin"])
        XCTAssertEqual(storedFiles(), ["relations-pack-meta.json", "relations-pack.bin"], "no temporary files are left behind")

        let store = RelationPackStore(directory: directory)
        let loaded = try XCTUnwrap(store.loadValidated(validator: PackBuilder.validator, reference: s.reference, bundledVersion: 1))
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(store.readMeta()?.pack, s.info)
        XCTAssertEqual(store.readMeta()?.installedAt, now)

        // Before 13 December the bundled table stays; from that day the pack's prices.
        let id0 = "at:test:0", id1 = "at:test:1"
        let early = RelationPriceTable.preferred(bundled: s.table, pack: loaded.table(), today: "2026-12-12")
        XCTAssertEqual(early.price(from: id0, to: id1), 10.0)
        let late = RelationPriceTable.preferred(bundled: s.table, pack: loaded.table(), today: "2026-12-13")
        XCTAssertEqual(late.price(from: id0, to: id1), 10.4, "€ 10,00 + 4 % in 10-cent units")
    }

    // MARK: An invalid pack never does

    func testNoInvalidPackIsEverInstalled() async throws {
        let s = setup()
        var tampered = [UInt8](s.pack)
        tampered[tampered.count - 3] ^= 0x55
        var wrongMagic = [UInt8](s.pack)
        wrongMagic[0] = 0x58
        let junk = Data(repeating: 0x41, count: s.info.bytes)
        let cases: [(String, Data, RelationPackError?)] = [
            ("changed byte", Data(tampered), .hashMismatch),
            ("wrong magic", Data(wrongMagic), .hashMismatch),
            ("junk of the promised size", junk, .hashMismatch),
            ("shorter than promised", s.pack.prefix(100), .sizeMismatch),
            ("empty", Data(), .sizeMismatch),
        ]
        for (name, data, expected) in cases {
            let result = await refresh(s, serving: data)
            XCTAssertEqual(result.outcome, .rejected(try XCTUnwrap(expected)), name)
            XCTAssertTrue(result.attempted, name)
            XCTAssertEqual(storedFiles(), [], "\(name): nothing written")
        }
    }

    func testAPackThatMatchesItsHashButNotTheRulesIsRejected() async throws {
        // The catalogue's hash is right for this file – the content is what is wrong (a wrong magic, a price outlier).
        let (ids, pairs) = PackBuilder.smallPairs()
        var options = PackBuilder.Options()
        options.magic = [0x4B, 0x42, 0x58, 0x58]
        let badMagic = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: pairs, options: options)
        let s = setup()
        var result = await refresh(s, serving: badMagic, info: PackBuilder.info(for: badMagic, version: 2, validFrom: "2026-12-13"))
        XCTAssertEqual(result.outcome, .rejected(.badMagic))

        let tenfold = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: PackBuilder.smallPairs(priceScale: 10).pairs)
        result = await refresh(s, serving: tenfold, info: PackBuilder.info(for: tenfold, version: 2, validFrom: "2026-12-13"))
        XCTAssertEqual(result.outcome, .rejected(.priceOutlier))

        let few = PackBuilder.make(version: 2, validFrom: "2026-12-13", pointIDs: ids, pairs: Array(pairs.prefix(100)))
        result = await refresh(s, serving: few, info: PackBuilder.info(for: few, version: 2, validFrom: "2026-12-13"))
        XCTAssertEqual(result.outcome, .rejected(.pairCountOutlier(100)))
        XCTAssertEqual(storedFiles(), [])
    }

    func testAnOversizeAnnouncementIsNotEvenDownloaded() async {
        let s = setup()
        var info = s.info
        info.bytes = RelationPack.maxBytes + 1
        let downloads = Downloads()
        let result = await refresh(s, serving: s.pack, info: info, downloads: downloads)
        XCTAssertEqual(result, .init(outcome: .rejected(.tooLarge), attempted: false))
        XCTAssertEqual(downloads.urls, [])
    }

    func testAnInvalidPackNeverReplacesAnInstalledOne() async throws {
        let s = setup()
        _ = await refresh(s, serving: s.pack)
        let before = try Data(contentsOf: directory.appendingPathComponent("relations-pack.bin"))
        let metaBefore = try Data(contentsOf: directory.appendingPathComponent("relations-pack-meta.json"))

        // Version 3 is announced, but the file served is damaged.
        let v3 = setup(version: 3)
        var damaged = [UInt8](v3.pack)
        damaged[100] ^= 0xFF
        let result = await refresh(v3, serving: Data(damaged), versionInUse: 2)
        XCTAssertEqual(result.outcome, .rejected(.hashMismatch))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("relations-pack.bin")), before)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("relations-pack-meta.json")), metaBefore)
    }

    // MARK: Airplane mode

    func testNoNetworkLeavesEverythingUntouched() async {
        let s = setup()
        let result = await refresh(s, serving: nil)
        XCTAssertEqual(result, .init(outcome: .unreachable, attempted: true))
        XCTAssertEqual(storedFiles(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "not even the directory is created")
        // The table in use is the bundled one.
        XCTAssertEqual(RelationPriceTable.preferred(bundled: s.table, pack: nil, today: "2026-12-14").validFrom, "2025-12-14")
    }

    // MARK: The rules about when to download

    func testNothingIsDownloadedUnlessTheVersionIsNewer() async {
        let s = setup(version: 2)
        let downloads = Downloads()
        let same = await refresh(s, serving: s.pack, versionInUse: 2, downloads: downloads)
        let older = await refresh(s, serving: s.pack, versionInUse: 5, force: true, downloads: downloads)
        XCTAssertEqual(same, .init(outcome: .notNewer, attempted: false))
        XCTAssertEqual(older, .init(outcome: .notNewer, attempted: false), "not even when forced")
        XCTAssertEqual(downloads.urls, [])
    }

    func testAtMostOneDownloadPer24Hours() async {
        let s = setup()
        let downloads = Downloads()
        let recent = now.addingTimeInterval(-23 * 3600)
        let throttled = await refresh(s, serving: s.pack, lastAttempt: recent, downloads: downloads)
        XCTAssertEqual(throttled, .init(outcome: .throttled, attempted: false))
        XCTAssertEqual(downloads.urls.count, 0)

        let forced = await refresh(s, serving: s.pack, lastAttempt: recent, force: true, downloads: downloads)
        XCTAssertEqual(forced.outcome, .installed(version: 2), "Jetzt prüfen")
        XCTAssertEqual(downloads.urls.count, 1)

        try? FileManager.default.removeItem(at: directory)
        let due = await refresh(s, serving: s.pack, lastAttempt: now.addingTimeInterval(-25 * 3600), downloads: downloads)
        XCTAssertEqual(due.outcome, .installed(version: 2))
        XCTAssertEqual(downloads.urls.count, 2)
    }

    func testAFailedAttemptCountsAgainstTheLimitToo() async {
        let s = setup()
        let first = await refresh(s, serving: nil)
        XCTAssertTrue(first.attempted, "the caller stores `now` as the last attempt, so a missing network is not retried every minute")
        // A clock set back does not block the download forever.
        let future = await refresh(s, serving: s.pack, lastAttempt: now.addingTimeInterval(3600))
        XCTAssertEqual(future.outcome, .installed(version: 2))
    }

    func testNoPackBlockMeansNothingToDo() async {
        let s = setup()
        let result = await updater().refresh(info: nil, tariffsURL: tariffsURL, versionInUse: 1, reference: s.reference,
                                             lastAttempt: nil, now: now, force: true) { _, _ in
            XCTFail("no download without a pack block")
            return Data()
        }
        XCTAssertEqual(result, .init(outcome: .unavailable, attempted: false))
    }

    func testOnlyTheOwnersHostIsContacted() async {
        var s = setup()
        let downloads = Downloads()
        s.info.url = "https://evil.example/relations-pack.bin"
        var result = await refresh(s, serving: s.pack, downloads: downloads)
        XCTAssertEqual(result, .init(outcome: .blockedURL, attempted: false))
        s.info.url = "http://github.com/o/r/releases/latest/download/relations-pack.bin"
        result = await refresh(s, serving: s.pack, downloads: downloads)
        XCTAssertEqual(result.outcome, .blockedURL)
        result = await refresh(setup(), serving: setup().pack, anchored: false)
        XCTAssertEqual(result.outcome, .blockedURL, "no tariffs document, no anchor")
        XCTAssertEqual(downloads.urls, [])
    }

    // MARK: The stored pack

    func testATamperedCacheIsRemovedAndIgnored() async throws {
        let s = setup()
        _ = await refresh(s, serving: s.pack)
        var bytes = [UInt8](try Data(contentsOf: directory.appendingPathComponent("relations-pack.bin")))
        bytes[200] ^= 0x01
        try Data(bytes).write(to: directory.appendingPathComponent("relations-pack.bin"))
        let store = RelationPackStore(directory: directory)
        XCTAssertNil(store.loadValidated(validator: PackBuilder.validator, reference: s.reference, bundledVersion: 1))
        XCTAssertEqual(storedFiles(), [], "a damaged cache is deleted, the bundled table is used")
    }

    func testAMissingMetaOrPackFileRemovesTheRest() async throws {
        let s = setup()
        _ = await refresh(s, serving: s.pack)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("relations-pack-meta.json"))
        let store = RelationPackStore(directory: directory)
        XCTAssertNil(store.loadValidated(validator: PackBuilder.validator, reference: s.reference, bundledVersion: 1))
        XCTAssertEqual(storedFiles(), [])
        // Nothing stored at all: nil, nothing to delete.
        XCTAssertNil(store.loadValidated(validator: PackBuilder.validator, reference: s.reference, bundledVersion: 1))
    }

    func testACachedPackThatTheBundledTableHasCaughtUpWithIsDeleted() async throws {
        let s = setup(version: 2)
        _ = await refresh(s, serving: s.pack)
        let store = RelationPackStore(directory: directory)
        // An app update ships table version 2 (or newer): the cache is dead weight.
        XCTAssertNil(store.loadValidated(validator: PackBuilder.validator, reference: s.reference, bundledVersion: 2))
        XCTAssertEqual(storedFiles(), [])
    }

    func testANewerPackReplacesTheInstalledOne() async throws {
        let v2 = setup(version: 2)
        _ = await refresh(v2, serving: v2.pack)
        let v3 = setup(version: 3, validFrom: "2027-12-12", increase: 1.05)
        let result = await refresh(v3, serving: v3.pack, versionInUse: 2)
        XCTAssertEqual(result.outcome, .installed(version: 3))
        let store = RelationPackStore(directory: directory)
        XCTAssertEqual(store.loadValidated(validator: PackBuilder.validator, reference: v3.reference, bundledVersion: 1)?.version, 3)
        XCTAssertEqual(storedFiles().count, 2)
    }
}
