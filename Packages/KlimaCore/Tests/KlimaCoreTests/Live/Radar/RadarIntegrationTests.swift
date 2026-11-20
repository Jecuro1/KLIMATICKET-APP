import XCTest
@testable import KlimaCore

/// MARK: integrate-radar3 – the radar as one product (docs/OEBB_LIVE.md §R11.3): the city requests (Bus, Bim, U-Bahn, docs/RADAR_MODES.md §3) in every
/// state of `RadarFeatureGate`, next to the stop page's board (docs/RADAR_MINE.md §4) and „Spuren“ (docs/RADAR_TRAILS.md), and the words the
/// Funktionen-Zentrale and the Spuren setting use for the radar as it is now.
final class RadarIntegrationTests: XCTestCase {
    /// Every combination of the gate's inputs (also some a person cannot reach: the rules must hold there too).
    private func everyGate() -> [RadarFeatureGate] {
        let layerSets: [Set<MapLayer>] = [[], [.trains], [.punctuality], [.trains, .punctuality], [.stations, .trains]]
        var gates: [RadarFeatureGate] = []
        for layers in layerSets {
            for access in [RadarFeatureGate.Access.open, .offline, .closed] {
                for railOnly in [true, false] {
                    for scene in [true, false] {
                        for cockpit in [true, false] {
                            for timeOpen in [true, false] {
                                for timeAway in [true, false] {
                                    gates.append(RadarFeatureGate(layers: MapLayerSelection(layers: layers), access: access, railOnly: railOnly,
                                                                  sceneActive: scene, cockpitOpen: cockpit, timeOpen: timeOpen, timeAway: timeAway))
                                }
                            }
                        }
                    }
                }
            }
        }
        return gates
    }

    /// The city requests ask exactly as the app wires them: inside the live loop (`RadarView` `.task(id: gate.liveLoopRuns)` runs
    /// `RadarModel.run`, the only caller of `RadarScheduler.next`), with their markers drawn (`RadarModel.setMarkersOn(gate.trainsOn)`), a city mode
    /// on (`RadarModel.applyCityViewport`: `modes.hasCity`, which is what makes `railOnly` false) and the map close enough
    /// (`RadarLanePlan.cityInZoom`).
    private func cityAsks(_ gate: RadarFeatureGate, cityModeOn: Bool, span: Double) -> Bool {
        gate.liveLoopRuns && gate.trainsOn && cityModeOn && RadarLanePlan.cityInZoom(latitudeSpan: span)
    }

    func testTheCityRequestsAskOnlyInsideTheLiveLoopWithTheTrainLayerOn() {
        var asked = 0
        let gates = everyGate()
        XCTAssertEqual(gates.count, 480)   // docs/OEBB_LIVE.md §R11.3 names this number
        for gate in gates {
            let cityModeOn = !gate.railOnly
            for span in [0.05, RadarLanePlan.citySpanLimit, 0.61, 4.0] {
                let asks = cityAsks(gate, cityModeOn: cityModeOn, span: span)
                let label = "\(gate) span \(span)"
                guard asks else { continue }
                asked += 1
                XCTAssertEqual(gate.access, .open, "no consent, switch off, kill switch or offline: \(label)")
                XCTAssertTrue(gate.sceneActive, "never in the background: \(label)")
                XCTAssertFalse(gate.cockpitOpen, "the Cockpit asks for its one train instead: \(label)")
                XCTAssertFalse(gate.timeAway, "the Zeitreise away from now pauses the live loop: \(label)")
                XCTAssertTrue(gate.layers.isOn(.trains), "the Pünktlichkeit alone never needs buses: \(label)")
                XCTAssertLessThanOrEqual(span, RadarLanePlan.citySpanLimit, label)
                // A city mode and a Zeitreise exclude each other: its snapshots are of trains.
                XCTAssertFalse(gate.timeAvailable, "a Zeitreise next to Bus, Bim or U-Bahn: \(label)")
                XCTAssertFalse(gate.timeLoopRuns, label)
                // The board of „Wo bleibt mein Bus?“ rides the same loop: one asking part, one budget.
                if gate.stopPanelAsks(isOpen: true, lowPower: false) { XCTAssertTrue(gate.liveLoopRuns, label) }
                // Spuren are drawn wherever the city markers are (the setting on), and never ask anything themselves.
                XCTAssertTrue(RadarTrailPolicy.isDrawn(trainsOn: gate.trainsOn, timeAway: gate.timeAway, mode: .mine), label)
            }
            // Only the Pünktlichkeit on: the loop runs for Austria's trains, the city requests rest.
            if gate.layers.isOn(.punctuality) && !gate.layers.isOn(.trains) {
                XCTAssertFalse(cityAsks(gate, cityModeOn: true, span: 0.1), "\(gate)")
            }
        }
        XCTAssertGreaterThan(asked, 0)
    }

    func testTheFunctionsHubDescribesTheRadarAsItIsNow() {
        let radar = FeatureID.radar.descriptor
        // Not only trains, not „Echtzeit“: the positions are calculated by the Auskunft from timetable and realtime, never GPS.
        for word in ["Bus", "Bim", "U-Bahn", "berechnet"] { XCTAssertTrue(radar.line.contains(word), "\(word) missing in „\(radar.line)“") }
        XCTAssertFalse(radar.line.contains("Echtzeit"), radar.line)
        let timetable = radar.dataFlows.filter { $0.recipient == .oebbTimetable }
        XCTAssertEqual(timetable.count, 1)
        guard let flow = timetable.first else { return XCTFail("the radar names no ÖBB data flow") }
        // Every part of the radar that sends something: the map (live and Zeitreise), the trip sheet, the Cockpit and the stop's board.
        for words in ["Kartenausschnitt", "Zeitreise", "die Fahrt, die du antippst", "Cockpit", "„Wo bleibt mein Bus?“ die Haltestelle"] {
            XCTAssertTrue(flow.sends.contains(words), "\(words) missing in what the radar sends")
        }
        XCTAssertTrue(flow.when.contains("24 Anfragen pro Minute"))
        XCTAssertTrue(flow.when.contains("einmal pro Minute"))
        // What stays on the iPhone: Spuren in memory, Meine Fahrzeuge outside the backup.
        let local = radar.dataFlows.filter { $0.recipient == .device }.map(\.sends)
        XCTAssertTrue(local.contains { $0.hasPrefix("Spuren:") && $0.contains("Arbeitsspeicher") })
        XCTAssertTrue(local.contains { $0.hasPrefix("Meine Fahrzeuge:") })
    }

    func testSpurenSayWhatMeineCovers() {
        // „Ausgewählte und meine“ draws the selected, the followed and the remembered lines' vehicles (`RadarTrailPolicy.trips`); the footer says so.
        XCTAssertTrue(RadarTrailText.footer.hasPrefix(RadarTrailText.mineMeaning))
        XCTAssertTrue(RadarTrailText.mineMeaning.contains("verfolgst"))
        XCTAssertTrue(RadarTrailText.mineMeaning.contains("gemerkten Linien"))
        let choice = RadarTrailPolicy.trips(mode: .mine, selected: nil, followed: "f", remembered: ["r"], singles: ["x", "f", "r"], span: 0.1)
        XCTAssertEqual(choice.tripIDs, ["f", "r"])
    }
}
