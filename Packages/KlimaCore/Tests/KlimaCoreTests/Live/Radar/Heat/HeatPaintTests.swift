import XCTest
@testable import KlimaCore

/// What the heat layer draws (docs/RADAR_HEATMAP.md §3): the colour ramp, the strength, the bound on the number of cells and
/// overlays, and the in-between states of the cross-fade.
final class HeatPaintTests: XCTestCase {
    private func sample(_ id: String, at point: GeoPoint, delay: Int?) -> HeatSample {
        HeatSample(tripID: id, coordinate: point, lineTitle: "REX 1", nextStopName: "Halt", delaySeconds: delay)
    }

    private func snapshot(cells: Int, perCell: Int = 4, delay: Int? = 600) -> HeatSnapshot {
        var samples: [HeatSample] = []
        for index in 0..<cells {
            let centre = HeatGrid.center(of: HeatCellID(q: index % 40, r: index / 40))
            for train in 0..<perCell { samples.append(sample("c\(index)-\(train)", at: centre, delay: delay)) }
        }
        return RadarHeat.snapshot(samples)
    }

    // MARK: Ramp

    func testTheRampBlendsAddUpToOneEverywhere() {
        for tenth in -20...400 {
            let blend = HeatRamp.blend(medianSeconds: Double(tenth) * 6)
            XCTAssertEqual(blend.green + blend.orange + blend.red, 1, accuracy: 1e-12, "minutes \(Double(tenth) / 10)")
            XCTAssertGreaterThanOrEqual(min(blend.green, blend.orange, blend.red), 0)
        }
    }

    func testTheRampFollowsTheBucketsWithASoftEdge() {
        // Under 5 minutes green dominates, from 5 to 15 orange, over 15 red; at the limits the two colours are half and half.
        for tenth in 0..<50 {
            let blend = HeatRamp.blend(medianSeconds: Double(tenth) * 6)
            XCTAssertGreaterThanOrEqual(blend.green, blend.orange, "\(Double(tenth) / 10) min")
            XCTAssertEqual(blend.red, 0)
        }
        for tenth in 51..<150 {
            let blend = HeatRamp.blend(medianSeconds: Double(tenth) * 6)
            XCTAssertGreaterThanOrEqual(blend.orange, max(blend.green, blend.red), "\(Double(tenth) / 10) min")
        }
        for tenth in 151...400 {
            let blend = HeatRamp.blend(medianSeconds: Double(tenth) * 6)
            XCTAssertGreaterThanOrEqual(blend.red, blend.orange, "\(Double(tenth) / 10) min")
            XCTAssertEqual(blend.green, 0)
        }
        let five = HeatRamp.blend(medianSeconds: 300)
        XCTAssertEqual(five.green, 0.5, accuracy: 1e-12)
        XCTAssertEqual(five.orange, 0.5, accuracy: 1e-12)
        let fifteen = HeatRamp.blend(medianSeconds: 900)
        XCTAssertEqual(fifteen.orange, 0.5, accuracy: 1e-12)
        XCTAssertEqual(fifteen.red, 0.5, accuracy: 1e-12)
    }

    func testTheRampIsPureInTheMiddleOfEachBucketAndContinuous() {
        XCTAssertEqual(HeatRamp.blend(medianSeconds: 0), HeatBlend(green: 1, orange: 0, red: 0))
        XCTAssertEqual(HeatRamp.blend(medianSeconds: 600), HeatBlend(green: 0, orange: 1, red: 0))
        XCTAssertEqual(HeatRamp.blend(medianSeconds: 1500), HeatBlend(green: 0, orange: 0, red: 1))
        XCTAssertEqual(HeatRamp.blend(medianSeconds: -400), HeatBlend(green: 1, orange: 0, red: 0), "early is green")
        XCTAssertEqual(HeatRamp.blend(medianSeconds: .nan), HeatBlend(green: 1, orange: 0, red: 0), "no NaN reaches the map")
        var previous = HeatRamp.blend(medianSeconds: 0)
        for second in stride(from: 1, through: 1500, by: 1) {
            let blend = HeatRamp.blend(medianSeconds: Double(second))
            XCTAssertLessThan(abs(blend.green - previous.green) + abs(blend.orange - previous.orange) + abs(blend.red - previous.red), 0.02,
                              "no jump at second \(second)")
            previous = blend
        }
    }

    func testStrengthGrowsWithTheNumberOfTrains() {
        XCTAssertEqual(HeatRamp.strength(sampleCount: 3), 0.55, accuracy: 1e-12)
        XCTAssertEqual(HeatRamp.strength(sampleCount: 12), 1, accuracy: 1e-12)
        XCTAssertEqual(HeatRamp.strength(sampleCount: 500), 1, accuracy: 1e-12)
        XCTAssertEqual(HeatRamp.strength(sampleCount: 0), 0.55, accuracy: 1e-12, "never below the faintest")
        var last = 0.0
        for count in 0...20 {
            let value = HeatRamp.strength(sampleCount: count)
            XCTAssertGreaterThanOrEqual(value, last)
            last = value
        }
    }

    // MARK: What is drawn

    func testCellsAreDrawnColouredOrNeutral() {
        let snapshot = RadarHeat.snapshot(
            (0..<4).map { sample("a\($0)", at: HeatGrid.center(of: HeatCellID(q: 0, r: 0)), delay: 1200) }
            + (0..<2).map { sample("b\($0)", at: HeatGrid.center(of: HeatCellID(q: 3, r: 0)), delay: 1200) })
        let drawn = HeatLayer.drawCells(from: snapshot)
        XCTAssertEqual(drawn.count, 2)
        let coloured = drawn.first { $0.id == HeatCellID(q: 0, r: 0) }
        let neutral = drawn.first { $0.id == HeatCellID(q: 3, r: 0) }
        XCTAssertEqual(coloured?.isNeutral, false)
        XCTAssertEqual(coloured?.blend, HeatBlend(green: 0, orange: 0, red: 1))
        XCTAssertEqual(neutral?.isNeutral, true)
        XCTAssertEqual(neutral?.blend, HeatBlend.none, "a cell with two trains is never coloured, however late they are")
        XCTAssertEqual(coloured?.trainCount, 4)
    }

    func testTheNumberOfDrawnCellsIsBounded() {
        // 700 cells, each with four late trains: far more than the layer may draw.
        let big = snapshot(cells: 700)
        XCTAssertEqual(big.cells.count, 700)
        let drawn = HeatLayer.drawCells(from: big)
        XCTAssertEqual(drawn.count, HeatLayer.maxDrawnCells)
        XCTAssertEqual(drawn.reduce(0) { $0 + $1.overlayCount }, HeatLayer.maxOverlays, "three map overlays a cell, not one view per train")
        XCTAssertLessThanOrEqual(drawn.reduce(0) { $0 + $1.overlayCount }, 900)
        XCTAssertEqual(HeatLayer.drawCells(from: big, cap: 10).count, 10)
        XCTAssertTrue(HeatLayer.drawCells(from: big, cap: 0).isEmpty)
        XCTAssertTrue(HeatLayer.drawCells(from: big, cap: -5).isEmpty)
        XCTAssertTrue(HeatLayer.drawCells(from: .empty).isEmpty)
    }

    func testColouredCellsComeBeforeNeutralOnesWhenTheCapCuts() {
        // 30 coloured cells (4 trains each) and 400 neutral ones (1 train each): a cap of 100 keeps every coloured cell.
        var samples: [HeatSample] = []
        for index in 0..<30 {
            for train in 0..<4 { samples.append(sample("c\(index)-\(train)", at: HeatGrid.center(of: HeatCellID(q: index, r: 0)), delay: 600)) }
        }
        for index in 0..<400 {
            samples.append(sample("n\(index)", at: HeatGrid.center(of: HeatCellID(q: index % 40, r: 2 + index / 40)), delay: 120))
        }
        let drawn = HeatLayer.drawCells(from: RadarHeat.snapshot(samples), cap: 100)
        XCTAssertEqual(drawn.count, 100)
        XCTAssertEqual(drawn.filter { !$0.isNeutral }.count, 30)
        XCTAssertEqual(drawn.filter(\.isNeutral).count, 70)
    }

    func testTheDrawingOrderAndTheChoiceAreStable() {
        let input = snapshot(cells: 500)
        let first = HeatLayer.drawCells(from: input)
        XCTAssertEqual(first, HeatLayer.drawCells(from: input))
        XCTAssertEqual(first.map(\.id), first.map(\.id).sorted(), "sorted by id: the z-order never changes between two answers")
    }

    func testMoreTrainsMeanAMoreSolidCell() {
        let few = HeatLayer.drawCells(from: RadarHeat.snapshot((0..<3).map { sample("a\($0)", at: HeatGrid.center(of: HeatCellID(q: 0, r: 0)), delay: 600) }))
        let many = HeatLayer.drawCells(from: RadarHeat.snapshot((0..<14).map { sample("a\($0)", at: HeatGrid.center(of: HeatCellID(q: 0, r: 0)), delay: 600) }))
        XCTAssertLessThan(few[0].strength, many[0].strength)
        XCTAssertEqual(many[0].strength, 1, accuracy: 1e-12)
    }

    // MARK: Cross-fade

    private func cell(_ q: Int, _ blend: HeatBlend, strength: Double = 1, neutral: Bool = false) -> HeatDrawCell {
        HeatDrawCell(id: HeatCellID(q: q, r: 0), center: HeatGrid.center(of: HeatCellID(q: q, r: 0)), isNeutral: neutral, blend: blend,
                     strength: strength, trainCount: 4)
    }

    private let green = HeatBlend(green: 1, orange: 0, red: 0)
    private let red = HeatBlend(green: 0, orange: 0, red: 1)

    func testTheEndsOfTheCrossFadeAreTheOldAndTheNewCells() {
        let old = [cell(0, green), cell(1, green)]
        let new = [cell(1, red), cell(2, red)]
        XCTAssertEqual(HeatLayer.interpolate(from: old, to: new, progress: 1), new, "at 1 exactly the new cells")
        XCTAssertEqual(HeatLayer.interpolate(from: old, to: new, progress: 2), new, "clamped")
        let start = HeatLayer.interpolate(from: old, to: new, progress: 0)
        XCTAssertEqual(start.map(\.id.q), [0, 1], "at 0 the old cells; a cell that is only new has no strength yet")
        XCTAssertEqual(start.first { $0.id.q == 1 }?.blend, green)
        XCTAssertEqual(HeatLayer.interpolate(from: old, to: new, progress: .nan), new, "a broken progress shows the new state")
    }

    func testAColourMovesLinearlyAndNewAndGoneCellsFade() {
        let old = [cell(0, green), cell(1, green)]
        let new = [cell(1, red, strength: 0.6), cell(2, red)]
        let half = HeatLayer.interpolate(from: old, to: new, progress: 0.5)
        XCTAssertEqual(half.map(\.id.q), [0, 1, 2])
        let stayed = half.first { $0.id.q == 1 }!
        XCTAssertEqual(stayed.blend.green, 0.5, accuracy: 1e-12)
        XCTAssertEqual(stayed.blend.red, 0.5, accuracy: 1e-12)
        XCTAssertEqual(stayed.strength, 0.8, accuracy: 1e-12)
        XCTAssertEqual(half.first { $0.id.q == 0 }?.strength ?? -1, 0.5, accuracy: 1e-12, "a cell that is gone fades out")
        XCTAssertEqual(half.first { $0.id.q == 2 }?.strength ?? -1, 0.5, accuracy: 1e-12, "a cell that is new fades in")
        for blend in half.map(\.blend) { XCTAssertEqual(blend.green + blend.orange + blend.red, 1, accuracy: 1e-12) }
    }

    func testACellThatTurnsColouredOrNeutralNeverPassesThroughADimColour() {
        let neutral = cell(0, .none, neutral: true)
        let coloured = cell(0, red, strength: 0.7)
        for step in stride(from: 0.0, through: 1.0, by: 0.125) {
            for (from, to) in [(neutral, coloured), (coloured, neutral)] {
                let state = HeatLayer.interpolate(from: [from], to: [to], progress: step)
                XCTAssertEqual(state.count, 1)
                let drawn = state[0]
                if !drawn.isNeutral {
                    XCTAssertEqual(drawn.blend.red, 1, accuracy: 1e-12, "step \(step): a coloured cell is the full colour, never red at a fraction of it")
                }
            }
        }
        XCTAssertTrue(HeatLayer.interpolate(from: [neutral], to: [neutral], progress: 0.5)[0].isNeutral)
        XCTAssertEqual(HeatLayer.interpolate(from: [neutral], to: [neutral], progress: 0.5)[0].blend, HeatBlend.none)
    }

    func testTheFadeFromNothingAndToNothing() {
        let cells = [cell(0, green), cell(1, red)]
        XCTAssertTrue(HeatLayer.interpolate(from: [], to: [], progress: 0.5).isEmpty)
        let appearing = HeatLayer.interpolate(from: [], to: cells, progress: 0.25)
        XCTAssertEqual(appearing.map(\.strength), [0.25, 0.25], "the layer fades in when it is switched on")
        let vanishing = HeatLayer.interpolate(from: cells, to: [], progress: 0.99)
        XCTAssertTrue(vanishing.allSatisfy { $0.strength < 0.02 })
        XCTAssertTrue(HeatLayer.interpolate(from: cells, to: [], progress: 1).isEmpty)
    }

    func testTheCrossFadeNeverDrawsMoreThanBothSetsTogether() {
        let old = HeatLayer.drawCells(from: snapshot(cells: 700, delay: 600))
        let new = HeatLayer.drawCells(from: snapshot(cells: 700, delay: 1500))
        for step in stride(from: 0.0, through: 1.0, by: 0.25) {
            XCTAssertLessThanOrEqual(HeatLayer.interpolate(from: old, to: new, progress: step).count, 2 * HeatLayer.maxDrawnCells)
        }
    }
}
