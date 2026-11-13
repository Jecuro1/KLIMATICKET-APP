import XCTest
@testable import KlimaCore

// MARK: radarmodes – the counts line of the status card.
final class RadarModeCountsTests: XCTestCase {
    func testCountsPerModeInChipOrderAddUpToThePill() {
        let classes = Array(repeating: 1, count: 21) + Array(repeating: 32, count: 28) + Array(repeating: 64, count: 180)
            + Array(repeating: 512, count: 92) + Array(repeating: 256, count: 12)
        let counts = RadarModeCounts(productClasses: classes.shuffled(), shownModes: RadarMode.allCases)
        XCTAssertEqual(counts.line, "Zug 21 · S-Bahn 28 · Bus 180 · Bim 92 · U-Bahn 12")
        XCTAssertEqual(counts.spoken, "21 Züge, 28 S-Bahnen, 180 Busse, 92 Bims, 12 U-Bahnen")
        XCTAssertEqual(counts.total, classes.count)
    }

    func testAModeWithNoVehicleShowsZero() {
        let counts = RadarModeCounts(productClasses: [64, 64], shownModes: [.rail, .bus])
        XCTAssertEqual(counts.line, "Zug 0 · Bus 2")
        XCTAssertEqual(counts.spoken, "0 Züge, 2 Busse")
    }

    func testOtherClassesAreAndereSoTheLineAddsUp() {
        // Rail replacement (2) and coaches (1024) are `.bus` for the codec, never a city bus here; class 0 is unknown.
        let classes = [1, 64, 2, 1024, 0]
        let counts = RadarModeCounts(productClasses: classes, shownModes: [.rail, .bus])
        XCTAssertEqual(counts.line, "Zug 1 · Bus 1 · Andere 3")
        XCTAssertEqual(counts.spoken, "1 Zug, 1 Bus, 3 andere Fahrzeuge")
        XCTAssertEqual(counts.total, classes.count)
        XCTAssertEqual(RadarModeCounts(productClasses: [2], shownModes: [.rail]).spoken, "0 Züge, 1 anderes Fahrzeug")
    }

    func testTheLineAlwaysEqualsThePinCount() {
        for seed in 0..<20 {
            var generator = CountsSeededGenerator(seed: UInt64(seed))
            let pool = [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
            let classes = (0..<Int.random(in: 0...300, using: &generator)).map { _ in pool.randomElement(using: &generator)! }
            let shown = RadarMode.allCases.filter { _ in Bool.random(using: &generator) }
            XCTAssertEqual(RadarModeCounts(productClasses: classes, shownModes: shown).total, classes.count)
        }
    }

    func testSingularForms() {
        let counts = RadarModeCounts(productClasses: [1, 32, 64, 512, 256], shownModes: RadarMode.allCases)
        XCTAssertEqual(counts.spoken, "1 Zug, 1 S-Bahn, 1 Bus, 1 Bim, 1 U-Bahn")
    }
}

private struct CountsSeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
