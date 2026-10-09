import Foundation
import XCTest
@testable import KlimaCore
#if canImport(Glibc)
import Glibc
#endif

/// AT-C8 (docs/ENRICH_SPEC.md §1.9, release gate in CI step "Place search performance"): the whole cold build of the
/// app's index – decode + inflate + CRC of places.bin, stops_osm.bin and localities.bin, the enrichment parse and the
/// search index – and the resident memory of the built index. Release only (a debug build takes ~10 s per build).
final class PlaceIndexBudgetTests: XCTestCase {
    /// ENRICH_SPEC §1.9 total budget (Linux, release, one core).
    static let buildBudget = 1.30
    /// The v1 files (places.bin + localities.bin of 7920f46^, no enrichment) indexed and measured the same way: 35.7–36.1 MB
    /// resident (2026-10-09, release, Linux). docs/PLACES.md quotes ~30 MB, measured differently (heap only).
    static let v1ResidentMB = 36.0
    /// §1.9: at most 8 MB more than v1 for every line and tag (v2 today: ~41 MB).
    static let memoryBudgetMB = v1ResidentMB + 8

    func testColdBuildTimeAndResidentMemory() throws {
        #if DEBUG
        throw XCTSkip("release gate (swift test -c release); a debug build is ~10× slower")
        #else
        func build() throws -> PlaceIndex {
            try PlaceIndex(placesURL: PlaceFixtures.placesURL, localitiesURL: PlaceFixtures.localitiesURL,
                           osmURL: PlaceFixtures.osmURL)
        }
        var best = Double.infinity
        for _ in 0..<2 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let index = try build()
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9)
            XCTAssertTrue(index.dataInfo.hasOSMLayer)
        }
        var memoryMB: Double?
        #if os(Linux)
        Self.trimHeap()
        if let before = Self.residentBytes() {
            let index = try build()
            Self.trimHeap()
            if let after = Self.residentBytes() { memoryMB = Double(after - before) / 1_048_576 }
            withExtendedLifetime(index) {}
        }
        #endif
        print(String(format: "[places] cold build (decode + inflate + enrichment + index) %.2f s (budget %.2f s), resident %@",
                     best, Self.buildBudget, memoryMB.map { String(format: "%.1f MB (budget %.0f MB)", $0, Self.memoryBudgetMB) }
                         ?? "not measured"))
        // shared CI runners are slower and noisier than the reference core: 1.5× the spec budget fails the gate
        XCTAssertLessThan(best, Self.buildBudget * 1.5, "AT-C8: decode + inflate + enrichment + index build")
        if let memoryMB { XCTAssertLessThan(memoryMB, Self.memoryBudgetMB, "AT-C8: resident memory of the built index") }
        #endif
    }

    #if os(Linux)
    /// Resident set size (`/proc/self/statm`, pages × page size).
    static func residentBytes() -> Int? {
        guard let s = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else { return nil }
        let parts = s.split(separator: " ")
        guard parts.count > 1, let pages = Int(parts[1]) else { return nil }
        return pages * Int(getpagesize())
    }

    /// `malloc_trim(0)`: hands freed heap back to the system, so the RSS delta is what the index keeps.
    static func trimHeap() {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "malloc_trim") else { return }
        typealias MallocTrim = @convention(c) (Int) -> Int32
        _ = unsafeBitCast(sym, to: MallocTrim.self)(0)
    }
    #endif
}
