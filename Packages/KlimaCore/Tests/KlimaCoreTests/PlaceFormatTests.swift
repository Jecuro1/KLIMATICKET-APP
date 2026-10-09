import Foundation
import XCTest
@testable import KlimaCore

/// Step 0 fixtures (Fixtures/places/v2, written by scripts/places_v2_fixtures.py with the encode_v2.py prototype):
/// the Warth / St. Anton / Floridsdorf subset as KBPL v1 and v2, a foreign-BASE OSM layer, corrupt files and the
/// RFC 1951 vectors.
enum V2Fixtures {
    static let dir = PlaceFixtures.dir.appendingPathComponent("v2")

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    static func data(_ name: String) -> Data {
        guard let d = try? Data(contentsOf: url(name)) else { fatalError("missing fixture \(url(name).path)") }
        return d
    }

    static func json(_ name: String) -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: data(name)) as? [String: Any] else { fatalError(name) }
        return o
    }

    static let manifest = json("manifest.json")
    static var counts: [String: Int] { manifest["counts"] as! [String: Int] }

    /// Section → (codec, raw length, crc32) of a fixture file as recorded by the generator.
    static func sections(_ file: String) -> [String: (codec: Int, raw: Int, crc: UInt32)] {
        let s = (manifest["sections"] as! [String: Any])[file] as! [String: [String: Any]]
        return s.mapValues { (($0["codec"] as! NSNumber).intValue, ($0["raw"] as! NSNumber).intValue,
                              UInt32(($0["crc32"] as! NSNumber).uint32Value)) }
    }

    /// `x = (x * 1103515245 + 12345) & 0x7FFFFFFF; byte = (x >> 16) & 0xFF` (vectors.json).
    static func lcg(_ n: Int, seed: Int) -> [UInt8] {
        var x = UInt64(seed)
        return (0..<n).map { _ in
            x = (x &* 1_103_515_245 &+ 12_345) & 0x7FFF_FFFF
            return UInt8((x >> 16) & 0xFF)
        }
    }

    static func repeated(_ text: String, _ n: Int) -> [UInt8] {
        let t = Array(text.utf8)
        return (0..<n).map { t[$0 % t.count] }
    }
}

/// Deterministic generator for the fuzz tests (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// WP-C1: KBPL v2 container, pure-Swift Inflate + CRC-32, v1 compatibility, the OSM layer with its BASE check and the
/// loader (docs/ENRICH_SPEC.md §1.2–§1.3, M1, AT-C1–AT-C3 format parts).
final class PlaceFormatTests: XCTestCase {
    typealias ReadError = PlaceDataset.ReadError

    // MARK: Inflate (AT-C1)

    func testInflateVectorsDecodeByteExactly() throws {
        let v = V2Fixtures.json("inflate/vectors.json")
        let text = [UInt8](V2Fixtures.data("inflate/text.txt"))
        let vectors = v["vectors"] as! [[String: Any]]
        XCTAssertEqual(Set(vectors.map { $0["name"] as! String }),
                       ["empty", "stored", "fixed", "dynamic", "huffman_only", "rle", "repetitive_1mib", "match258_dist32768"])
        for vec in vectors {
            let name = vec["name"] as! String
            let rawLength = (vec["rawLength"] as! NSNumber).intValue
            let crc = UInt32((vec["crc32"] as! NSNumber).uint32Value)
            let e = vec["expect"] as! [String: Any]
            let int = { (k: String) in (e[k] as! NSNumber).intValue }
            let expected: [UInt8]
            switch e["kind"] as! String {
            case "bytes": expected = []
            case "lcg": expected = V2Fixtures.lcg(int("length"), seed: int("seed"))
            case "lcg_repeat": expected = Array([[UInt8]](repeating: V2Fixtures.lcg(int("length"), seed: int("seed")),
                                                         count: int("times")).joined())
            case "text": expected = Array(text.prefix(int("length")))
            case "repeat": expected = V2Fixtures.repeated(e["text"] as! String, int("length"))
            case "far_match":
                let h = V2Fixtures.lcg(32768, seed: int("seed"))
                expected = h + h.prefix(258)
            default: return XCTFail("unknown vector kind in \(name)")
            }
            XCTAssertEqual(expected.count, rawLength, name)
            XCTAssertEqual(CRC32.checksum(expected), crc, "\(name): generator matches the Python reference")
            let out = try Inflate.decompress([UInt8](V2Fixtures.data("inflate/\(name).deflate")), expectedSize: rawLength)
            XCTAssertEqual(out, expected, name)
        }
        // the far match really reaches back 32,768 bytes
        let far = try Inflate.decompress([UInt8](V2Fixtures.data("inflate/match258_dist32768.deflate")), expectedSize: 33026)
        XCTAssertEqual(Array(far[32768...]), Array(far[0..<258]))
    }

    func testCRC32() {
        XCTAssertEqual(CRC32.checksum([UInt8]("123456789".utf8)), 0xCBF4_3926)       // CRC-32/ISO-HDLC check value
        XCTAssertEqual(CRC32.checksum([]), 0)
        XCTAssertEqual(CRC32.checksum([UInt8]("KlimaBilanz".utf8)), CRC32.checksum([UInt8]("KlimaBilanz".utf8)))
    }

    func testInflateRejectsMalformedStreams() throws {
        func fails(_ bytes: [UInt8], size: Int, _ expected: InflateError, line: UInt = #line) {
            XCTAssertThrowsError(try Inflate.decompress(bytes, expectedSize: size), line: line) {
                XCTAssertEqual($0 as? InflateError, expected, line: line)
            }
        }
        fails([], size: 0, .truncated)
        fails([0x07], size: 1, .invalidBlockType)                                  // final, block type 3
        fails([0x01, 0x05, 0x00, 0x00, 0x00], size: 5, .invalidStoredLength)      // stored, NLEN ≠ ~LEN
        fails([0x01, 0x05, 0x00, 0xFA, 0xFF, 0x61, 0x62], size: 5, .truncated)    // stored, 2 of 5 bytes
        let dynamic = [UInt8](V2Fixtures.data("inflate/dynamic.deflate"))
        let n = 24_000
        fails(dynamic, size: n - 1, .sizeMismatch)
        fails(dynamic, size: n + 1, .sizeMismatch)
        XCTAssertThrowsError(try Inflate.decompress(Array(dynamic.prefix(dynamic.count / 2)), expectedSize: n))

        var w = TestBitWriter()                     // fixed block: length 3 at distance 1 with nothing written yet
        w.bits(1, 1); w.bits(1, 2); w.huff(0b0000001, 7); w.huff(0, 5); w.huff(0, 7)
        fails(w.bytes, size: 3, .invalidDistance)
        w = TestBitWriter()                         // dynamic block whose code-length code is over-subscribed
        w.bits(1, 1); w.bits(2, 2); w.bits(0, 5); w.bits(0, 5); w.bits(15, 4)
        for _ in 0..<19 { w.bits(1, 3) }
        fails(w.bytes, size: 1, .invalidCodeLengths)
        w = TestBitWriter()                         // literal/length symbol 286 does not exist
        w.bits(1, 1); w.bits(1, 2); w.huff(0b11000110, 8)
        fails(w.bytes, size: 1, .invalidSymbol)
        XCTAssertThrowsError(try Inflate.decompress([0x03, 0x00], expectedSize: -1))
        XCTAssertEqual(try Inflate.decompress([0x03, 0x00], expectedSize: 0), [])
    }

    /// AT-C1: 300 seeded corruptions of a real deflated section (+ random garbage) → an error or a CRC mismatch,
    /// never a trap; every corruption that still inflates to the right size is caught by the CRC.
    func testInflateFuzzNeverTrapsAndCRCCatchesCorruption() throws {
        let c = try KBPLContainer(data: V2Fixtures.data("places.bin"))
        let strs = try XCTUnwrap(c.entry("STRS"))
        XCTAssertEqual(strs.codec, 1)
        let file = [UInt8](V2Fixtures.data("places.bin"))
        let base = Array(file[strs.offset..<(strs.offset + strs.storedLength)])
        let original = try Inflate.decompress(base, expectedSize: strs.rawLength)
        XCTAssertEqual(CRC32.checksum(original), strs.crc32)
        var rng = SeededRNG(seed: 0x4B42_504C)
        var thrown = 0, caughtByCRC = 0, identical = 0
        for i in 0..<300 {
            var m = base
            if i % 3 == 0 {
                m = Array(m.prefix(Int.random(in: 0..<m.count, using: &rng)))
            } else {
                for _ in 0..<Int.random(in: 1...8, using: &rng) {
                    m[Int.random(in: 0..<m.count, using: &rng)] ^= UInt8.random(in: 1...255, using: &rng)
                }
            }
            do {
                let out = try Inflate.decompress(m, expectedSize: strs.rawLength)
                if out == original { identical += 1 } else {
                    XCTAssertNotEqual(CRC32.checksum(out), strs.crc32, "mutation \(i) must fail the CRC")
                    caughtByCRC += 1
                }
            } catch {
                XCTAssertTrue(error is InflateError)
                thrown += 1
            }
        }
        XCTAssertEqual(thrown + caughtByCRC + identical, 300)
        XCTAssertGreaterThan(thrown, 200)
        print("[format] inflate fuzz: \(thrown) threw, \(caughtByCRC) caught by CRC, \(identical) unchanged")
        for _ in 0..<300 {                                       // garbage of every length
            let junk = (0..<Int.random(in: 0..<600, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            _ = try? Inflate.decompress(junk, expectedSize: Int.random(in: 0..<4096, using: &rng))
        }
    }

    // MARK: container

    func testContainerDirectoryMatchesTheGenerator() throws {
        for file in ["places.bin", "stops_osm.bin", "localities.bin"] {
            let c = try KBPLContainer(data: V2Fixtures.data(file))
            XCTAssertEqual(c.version, 2, file)
            let expected = V2Fixtures.sections(file)
            XCTAssertEqual(Set(c.entries.map(\.fourcc)), Set(expected.keys), file)
            for e in c.entries {
                let x = try XCTUnwrap(expected[e.fourcc])
                XCTAssertEqual(Int(e.codec), x.codec, "\(file) \(e.fourcc)")
                XCTAssertEqual(e.rawLength, x.raw, "\(file) \(e.fourcc)")
                XCTAssertEqual(e.crc32, x.crc, "\(file) \(e.fourcc)")
                XCTAssertEqual(try c.decode(e).count, e.rawLength, "\(file) \(e.fourcc) decodes with its CRC")
            }
        }
        let places = try KBPLContainer(data: V2Fixtures.data("places.bin"))
        XCTAssertEqual(places.entries.map(\.fourcc),
                       ["RECS", "STRS", "GEMS", "EXTR", "LCAT", "LNAM", "LSTP", "RPRD", "GTAG", "TAGS", "META", "BASE"])
        XCTAssertEqual(places.nRecords, V2Fixtures.counts["stops"])
        XCTAssertEqual(places.nStopRecords, V2Fixtures.counts["stops"])
        XCTAssertEqual(places.entry("RPRD")?.codec, 0, "stored sections exist next to deflated ones")
        XCTAssertNil(try places.section("ELEV"), "unknown or absent sections are nil, not an error")
        let loc = try KBPLContainer(data: V2Fixtures.data("localities.bin"))
        XCTAssertEqual(loc.nStopRecords, 0)
        XCTAssertEqual(loc.nRecords, V2Fixtures.counts["localities"])
    }

    /// AT-C2: the v1 fixture copy of today's format and its v2 rewrap decode to the same records.
    func testV1AndV2DecodeTheSameRecords() throws {
        let v1 = try PlaceDataset(places: V2Fixtures.data("v1/places.bin"), localities: V2Fixtures.data("v1/localities.bin"))
        let v2 = try PlaceDataset(places: V2Fixtures.data("places.bin"), localities: V2Fixtures.data("localities.bin"))
        XCTAssertEqual(v1.stopCount, V2Fixtures.counts["stops"])
        XCTAssertEqual(v1.localityCount, V2Fixtures.counts["localities"])
        XCTAssertEqual(v1.dataInfo.formatVersion, 1)
        XCTAssertEqual(v2.dataInfo.formatVersion, 2)
        XCTAssertNil(v1.officialLayer)
        XCTAssertNotNil(v2.officialLayer)
        XCTAssertEqual(signature(v1.stops, lines: false), signature(v2.stops, lines: false))
        XCTAssertEqual(signature(v1.localities, lines: false), signature(v2.localities, lines: false))
        XCTAssertTrue(v1.stops.contains { $0.legacyLines != nil }, "v1 keeps its lines string (EXTR tag 5)")
        XCTAssertTrue(v2.stops.allSatisfy { $0.legacyLines == nil }, "v2 drops tag 5 (lines come from LSTP)")
        let warth = try XCTUnwrap(v2.stops.first { $0.id == "at:48:344" })
        XCTAssertEqual(warth.name, "Warth (Vorarlberg) Dorfplatz")
        XCTAssertEqual(warth.state, "V")
        XCTAssertEqual(warth.municipality, "Warth")
        XCTAssertEqual(v1.stops.first { $0.id == "at:48:344" }?.legacyLines, "110,852")
        let ort = try XCTUnwrap(v2.localities.first { $0.id == "osm:n73089810" })
        XCTAssertEqual(ort.mainStopID, "at:48:344")
        XCTAssertEqual(v2.stops.map(\.id), V2Fixtures.manifest["stops"] as? [String], "stop record index = RECS order")
        // mixed versions: every file is read on its own
        let mixed1 = try PlaceDataset(places: V2Fixtures.data("places.bin"), localities: V2Fixtures.data("v1/localities.bin"))
        let mixed2 = try PlaceDataset(places: V2Fixtures.data("v1/places.bin"), localities: V2Fixtures.data("localities.bin"))
        XCTAssertEqual(signature(mixed1.localities, lines: false), signature(v2.localities, lines: false))
        XCTAssertEqual(signature(mixed2.localities, lines: false), signature(v2.localities, lines: false))
    }

    /// AT-C2 at full scale: today's shipped places.bin rewrapped as a stored (codec 0) v2 container decodes to exactly
    /// the same 39k records, CRC checked.
    func testShippedDataRewrappedAsV2() throws {
        let v1Data = try Data(contentsOf: PlaceFixtures.placesURL)
        let c = try KBPLContainer(data: v1Data)
        guard c.version == 1 else { throw XCTSkip("shipped places.bin is already v2") }
        let bytes = [UInt8](v1Data)
        let sections = c.entries.map { ($0.fourcc, Array(bytes[$0.offset..<($0.offset + $0.storedLength)])) }
        let v2Data = KBPLTestWriter.write(sections: sections, nRecords: c.nRecords, nGemeinden: c.nGemeinden,
                                          nStopRecords: c.nStopRecords)
        let a = try PlaceDataset(places: v1Data, localities: nil)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let b = try PlaceDataset(places: v2Data, localities: nil)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        print(String(format: "[format] shipped places.bin as stored v2: %.0f ms (%d records)", ms, b.stopCount))
        XCTAssertEqual(b.dataInfo.formatVersion, 2)
        XCTAssertEqual(signature(a.stops, lines: true), signature(b.stops, lines: true))
        // one flipped byte anywhere in a section is caught
        var bad = [UInt8](v2Data)
        bad[64 + 28 * 1000 + 3] ^= 0x10
        XCTAssertThrowsError(try PlaceDataset(places: Data(bad), localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .corrupt(section: "RECS"))
        }
    }

    func testVersionsAndCorruptFiles() throws {
        var d = V2Fixtures.data("places.bin")
        d[4] = 3
        XCTAssertThrowsError(try PlaceDataset(places: d, localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .unsupportedVersion(3))
        }
        d[4] = 0
        XCTAssertThrowsError(try PlaceDataset(places: d, localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .unsupportedVersion(0))
        }
        XCTAssertThrowsError(try PlaceDataset(places: V2Fixtures.data("corrupt/places_bad_crc.bin"), localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .corrupt(section: "STRS"))
        }
        XCTAssertThrowsError(try PlaceDataset(places: V2Fixtures.data("corrupt/places_bad_deflate.bin"), localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .corrupt(section: "RECS"))
        }
        XCTAssertThrowsError(try PlaceDataset(places: V2Fixtures.data("places.bin").prefix(2000), localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .truncated, "the directory sits at the end")
        }
        // a localities.bin problem is an error too (only the OSM layer is optional)
        XCTAssertThrowsError(try PlaceDataset(places: V2Fixtures.data("places.bin"),
                                              localities: V2Fixtures.data("corrupt/places_bad_crc.bin")))
        // a directory claiming an absurd decoded size is rejected before allocating
        var huge = [UInt8](V2Fixtures.data("places.bin"))
        let dirOff = Int(huge[52]) | Int(huge[53]) << 8 | Int(huge[54]) << 16 | Int(huge[55]) << 24
        huge[dirOff + 12 + 3] = 0x7F                                    // RECS rawLength ≈ 2 GB
        XCTAssertThrowsError(try PlaceDataset(places: Data(huge), localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .corrupt(section: "RECS"))
        }
        // a missing mandatory section
        var noGems = [UInt8](V2Fixtures.data("places.bin"))
        noGems[dirOff + 28 * 2] = UInt8(ascii: "X")                     // "GEMS" → "XEMS"
        XCTAssertThrowsError(try PlaceDataset(places: Data(noGems), localities: nil)) {
            XCTAssertEqual($0 as? ReadError, .corrupt(section: "GEMS"))
        }
    }

    /// Random corruption of a whole v2 file (header, directory, sections, padding): an error or the original records,
    /// never a trap and never silently different data.
    func testCorruptV2FileNeverTrapsOrDecodesWrongData() throws {
        let good = [UInt8](V2Fixtures.data("places.bin"))
        let original = try PlaceDataset(places: Data(good), localities: nil)
        let reference = signature(original.stops, lines: false)
        var rng = SeededRNG(seed: 2026_10_09)
        var failed = 0, unchanged = 0
        for i in 0..<400 {
            var d = good
            if i % 4 == 0 {
                d = Array(d.prefix(Int.random(in: 0..<d.count, using: &rng)))
            } else {
                for _ in 0..<Int.random(in: 1...4, using: &rng) {
                    d[Int.random(in: 0..<d.count, using: &rng)] ^= UInt8.random(in: 1...255, using: &rng)
                }
            }
            do {
                let ds = try PlaceDataset(places: Data(d), localities: nil)
                XCTAssertEqual(signature(ds.stops, lines: false), reference, "mutation \(i) decoded different records")
                unchanged += 1
            } catch {
                XCTAssertNotNil(error as? ReadError, "\(error)")
                failed += 1
            }
        }
        XCTAssertGreaterThan(failed, 250)
        print("[format] file fuzz: \(failed) rejected, \(unchanged) harmless (padding/reserved/hint bytes)")
    }

    // MARK: OSM layer (M1, AT-C3 format part)

    func testOSMLayerLoadsOnlyWithMatchingBase() throws {
        let places = V2Fixtures.data("places.bin"), loc = V2Fixtures.data("localities.bin")
        let full = try PlaceDataset(places: places, localities: loc, osm: V2Fixtures.data("stops_osm.bin"))
        XCTAssertTrue(full.dataInfo.hasOSMLayer)
        XCTAssertNil(full.osmLayerIssue)
        XCTAssertNil(full.dataInfo.osmLayerNote)
        let osm = try XCTUnwrap(full.osmLayer)
        XCTAssertEqual(Set(osm.sections.keys), ["STRS", "LCAT", "LNAM", "LPAT", "LSTP", "TAGS", "META", "BASE"])
        XCTAssertEqual(osm.nStopRecords, full.stopCount)
        let official = try XCTUnwrap(full.officialLayer)
        XCTAssertEqual(Set(official.sections.keys),
                       ["STRS", "LCAT", "LNAM", "LSTP", "RPRD", "GTAG", "TAGS", "META", "BASE"])
        XCTAssertEqual(official.section("BASE"), osm.section("BASE"))
        XCTAssertEqual(official.section("BASE")?.count, 32)
        let rawLCAT = V2Fixtures.sections("places.bin")["LCAT"]!.raw / 24 + V2Fixtures.sections("stops_osm.bin")["LCAT"]!.raw / 24
        XCTAssertEqual(full.dataInfo.lineCount, rawLCAT)
        XCTAssertGreaterThan(full.dataInfo.stopsWithLines, full.stopCount / 2)
        XCTAssertLessThanOrEqual(full.dataInfo.stopsWithLines, full.stopCount)
        let officialOnly = try PlaceDataset(places: places, localities: loc)
        XCTAssertLessThanOrEqual(officialOnly.dataInfo.stopsWithLines, full.dataInfo.stopsWithLines)
        XCTAssertEqual(officialOnly.dataInfo.lineCount, V2Fixtures.sections("places.bin")["LCAT"]!.raw / 24)
        XCTAssertNil(officialOnly.osmLayerIssue, "no OSM file given: nothing to report")

        func issue(_ osm: Data, places p: Data = places) throws -> PlaceDataset.OSMLayerIssue? {
            let ds = try PlaceDataset(places: p, localities: loc, osm: osm)
            XCTAssertFalse(ds.dataInfo.hasOSMLayer)
            XCTAssertNil(ds.osmLayer)
            XCTAssertEqual(ds.stopCount, V2Fixtures.counts["stops"], "the official layer still loads")
            return ds.osmLayerIssue
        }
        XCTAssertEqual(try issue(V2Fixtures.data("stops_osm_other_base.bin")), .baseMismatch)
        var badCRC = [UInt8](V2Fixtures.data("stops_osm.bin"))
        let c = try KBPLContainer(data: Data(badCRC))
        let dirOff = Int(badCRC[52]) | Int(badCRC[53]) << 8 | Int(badCRC[54]) << 16 | Int(badCRC[55]) << 24
        let lcatIndex = try XCTUnwrap(c.entries.firstIndex { $0.fourcc == "LCAT" })
        badCRC[dirOff + 28 * lcatIndex + 20] ^= 0xFF
        XCTAssertEqual(try issue(Data(badCRC)), .corrupt(section: "LCAT"))
        XCTAssertEqual(try issue(Data("not a place file".utf8)), .unreadable)
        XCTAssertEqual(try issue(V2Fixtures.data("v1/places.bin")), .unsupportedVersion(1))
        var v9 = V2Fixtures.data("stops_osm.bin")
        v9[4] = 9
        XCTAssertEqual(try issue(v9), .unsupportedVersion(9))
        XCTAssertEqual(try issue(V2Fixtures.data("stops_osm.bin"), places: V2Fixtures.data("v1/places.bin")), .noBase,
                       "a v1 places.bin has no BASE to match")
        let foreign = try PlaceDataset(places: places, localities: loc, osm: V2Fixtures.data("stops_osm_other_base.bin"))
        XCTAssertEqual(foreign.dataInfo.osmLayerNote, "stops_osm.bin: baseMismatch")

        let missing = try PlaceDataset(placesURL: V2Fixtures.url("places.bin"), localitiesURL: V2Fixtures.url("localities.bin"),
                                       osmURL: V2Fixtures.url("does_not_exist.bin"))
        XCTAssertEqual(missing.osmLayerIssue, .missing)
        XCTAssertFalse(missing.dataInfo.hasOSMLayer)
    }

    func testIndexAndLoaderOnV2Files() async throws {
        let index = try PlaceIndex(placesURL: V2Fixtures.url("places.bin"), localitiesURL: V2Fixtures.url("localities.bin"),
                                   osmURL: V2Fixtures.url("stops_osm.bin"))
        XCTAssertTrue(index.dataInfo.hasOSMLayer)
        XCTAssertEqual(index.dataInfo.formatVersion, 2)
        XCTAssertEqual(index.place(id: "at:48:344")?.name, "Warth (Vorarlberg) Dorfplatz")
        XCTAssertEqual(index.search("Warth Dorfplatz", context: .tripLog, limit: 3).first?.id, "at:48:344")
        XCTAssertEqual(index.search("warth", context: .planner, limit: 8).first { $0.kind == .town && $0.state == "V" }?.mainStopID,
                       "at:48:344")

        let loader = PlaceIndexLoader(placesURL: V2Fixtures.url("places.bin"), localitiesURL: V2Fixtures.url("localities.bin"),
                                      osmURL: V2Fixtures.url("stops_osm_other_base.bin"))
        let loaded = try await loader.load()
        XCTAssertFalse(loaded.dataInfo.hasOSMLayer, "foreign OSM layer: official layer only")
        XCTAssertEqual(loaded.dataInfo.osmLayerNote, "stops_osm.bin: baseMismatch")
        XCTAssertNotNil(loaded.place(id: "at:47:1222"))

        let broken = PlaceIndexLoader(placesURL: V2Fixtures.url("corrupt/places_bad_crc.bin"), localitiesURL: nil)
        do {
            _ = try await broken.load()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ReadError, .corrupt(section: "STRS"))
        }
        guard case .failed = broken.state else { return XCTFail("not failed") }
        XCTAssertNil(PlaceIndexLoader(placesURL: nil, localitiesURL: nil).osmURL)

        let shipped = PlaceFixtures.index.dataInfo         // loaded with stops_osm.bin, like the app
        XCTAssertEqual(shipped.hasOSMLayer, shipped.formatVersion == 2)
        XCTAssertGreaterThanOrEqual(shipped.formatVersion, 1)
        if shipped.formatVersion == 1 { XCTAssertGreaterThan(shipped.stopsWithLines, 30_000) }
    }

    // MARK: helpers

    private func signature(_ recs: [PlaceRecord], lines: Bool) -> [String] {
        recs.map { r in
            var f: [String] = [r.id, r.name, r.aliases.joined(separator: "|"), String(r.lat), String(r.lon)]
            f += [r.kind.rawValue, String(r.products), r.state, r.municipality, String(r.weight), String(r.flags)]
            f.append(r.localityClass ?? "")
            f.append(r.eva.map { String($0) } ?? "")
            f.append(r.hafasExtId.map { String($0) } ?? "")
            f.append(r.uic.map { String($0) } ?? "")
            f.append(r.legacyIDs.joined(separator: "|"))
            f.append(r.mainStopID ?? "")
            f.append(lines ? (r.legacyLines ?? "") : "")
            return f.joined(separator: "\u{1F}")
        }
    }
}

/// Decode budget (ENRICH_SPEC §1.3 / §1.9: inflate + CRC of all three files ≈ 43 ms release). Debug builds only
/// guard against pathological slowdowns; the release numbers are printed for the log.
final class PlaceFormatPerformanceTests: XCTestCase {
    func testInflateThroughput() throws {
        let v = V2Fixtures.json("inflate/vectors.json")["vectors"] as! [[String: Any]]
        var inputs: [([UInt8], Int)] = []
        for vec in v where ["dynamic", "repetitive_1mib", "stored", "huffman_only"].contains(vec["name"] as! String) {
            inputs.append(([UInt8](V2Fixtures.data("inflate/\(vec["name"] as! String).deflate")),
                           (vec["rawLength"] as! NSNumber).intValue))
        }
        let total = inputs.reduce(0) { $0 + $1.1 }
        var best = Double.infinity
        for _ in 0..<5 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            for (data, n) in inputs { _ = try Inflate.decompress(data, expectedSize: n) }
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        let mbps = Double(total) / 1e6 / (best / 1e3)
        print(String(format: "[format] inflate %.2f MB in %.1f ms (%.0f MB/s)", Double(total) / 1e6, best, mbps))
        #if DEBUG
        XCTAssertLessThan(best, 20_000, "debug build: pathological slowdown")
        #else
        XCTAssertGreaterThan(mbps, 40, "release inflate must reach ≥ 40 MB/s (spec: 3.5 MB in ≈ 43 ms)")
        #endif
    }

    /// The shipped files (v1 today, v2 after the data build) decode within the budget.
    func testShippedFilesDecodeBudget() throws {
        let osm = PlaceFixtures.resources.appendingPathComponent("stops_osm.bin")
        var best = Double.infinity
        var info: PlaceDataInfo?
        for _ in 0..<3 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let ds = try PlaceDataset(placesURL: PlaceFixtures.placesURL, localitiesURL: PlaceFixtures.localitiesURL,
                                      osmURL: FileManager.default.fileExists(atPath: osm.path) ? osm : nil)
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            info = ds.dataInfo
        }
        print(String(format: "[format] shipped files (v%d, OSM layer %@) decode: %.0f ms", info?.formatVersion ?? 0,
                     info?.hasOSMLayer == true ? "yes" : "no", best))
        #if DEBUG
        XCTAssertLessThan(best, 30_000, "debug build: pathological slowdown")
        #else
        XCTAssertLessThan(best, 400, "decode + inflate + CRC of the shipped files (today 0.24 s + 43 ms inflate)")
        #endif
    }
}

extension PlaceFormatPerformanceTests {
    /// Full-size v2 files from a data build (`KB_PLACES_V2_DIR=<dir with places.bin, stops_osm.bin, localities.bin>`),
    /// e.g. the prototype output or a WP-D1 build before it is copied to App/Resources. Skipped without the variable.
    func testFullSizeV2FilesFromEnvironment() throws {
        guard let dir = ProcessInfo.processInfo.environment["KB_PLACES_V2_DIR"], !dir.isEmpty else {
            throw XCTSkip("set KB_PLACES_V2_DIR to check full-size v2 files")
        }
        let base = URL(fileURLWithPath: dir)
        var best = Double.infinity
        var ds: PlaceDataset?
        for _ in 0..<3 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            ds = try PlaceDataset(placesURL: base.appendingPathComponent("places.bin"),
                                  localitiesURL: base.appendingPathComponent("localities.bin"),
                                  osmURL: base.appendingPathComponent("stops_osm.bin"))
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        let d = try XCTUnwrap(ds)
        print(String(format: "[format] full v2 (%d stops, %d localities, %d lines, %d stops with lines, OSM %@): %.0f ms",
                     d.stopCount, d.localityCount, d.dataInfo.lineCount, d.dataInfo.stopsWithLines,
                     d.dataInfo.hasOSMLayer ? "yes" : "no", best))
        XCTAssertEqual(d.dataInfo.formatVersion, 2)
        XCTAssertTrue(d.dataInfo.hasOSMLayer, d.dataInfo.osmLayerNote ?? "")
        XCTAssertGreaterThan(d.stopCount, 39_000)
        XCTAssertGreaterThan(d.localityCount, 20_000)
        XCTAssertNotNil(d.stops.first { $0.id == "at:48:344" })
        let v1 = try PlaceDataset(placesURL: PlaceFixtures.placesURL, localitiesURL: PlaceFixtures.localitiesURL)
        if v1.dataInfo.formatVersion == 1, v1.stopCount == d.stopCount {
            XCTAssertEqual(v1.stops.map(\.id), d.stops.map(\.id), "same stops in the same order as the v1 files")
        }
    }
}

/// LSB-first bit writer for hand-made DEFLATE streams (RFC 1951 §3.1.1: Huffman codes MSB first).
struct TestBitWriter {
    private var full: [UInt8] = []
    private var acc: UInt8 = 0
    private var n = 0

    /// Written bytes, the last one zero-padded.
    var bytes: [UInt8] { n > 0 ? full + [acc] : full }

    mutating func bits(_ v: Int, _ k: Int) {
        for i in 0..<k {
            if (v >> i) & 1 == 1 { acc |= 1 << UInt8(n) }
            n += 1
            if n == 8 {
                full.append(acc)
                acc = 0
                n = 0
            }
        }
    }

    mutating func huff(_ code: Int, _ k: Int) {
        var rev = 0
        for i in 0..<k where (code >> i) & 1 == 1 { rev |= 1 << (k - 1 - i) }
        bits(rev, k)
    }
}

/// Minimal KBPL v2 writer (codec 0) for tests.
enum KBPLTestWriter {
    static func write(sections: [(String, [UInt8])], nRecords: Int, nGemeinden: Int, nStopRecords: Int) -> Data {
        func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        func le16(_ v: Int) -> [UInt8] { (0..<2).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        var body: [UInt8] = []
        var dir: [UInt8] = []
        var off = 64
        for (tag, raw) in sections {
            while off % 4 != 0 { body.append(0); off += 1 }
            dir += Array(tag.utf8) + le32(off) + le32(raw.count) + le32(raw.count) + [0, 0] + le16(0)
                + le32(Int(CRC32.checksum(raw))) + le32(0)
            body += raw
            off += raw.count
        }
        while off % 4 != 0 { body.append(0); off += 1 }
        var header = Array("KBPL".utf8) + le16(2) + le16(0) + le32(nRecords) + le32(nGemeinden)
        header += [UInt8](repeating: 0, count: 32) + le32(nStopRecords) + le32(off) + le32(sections.count) + le32(0)
        return Data(header + body + dir)
    }
}
