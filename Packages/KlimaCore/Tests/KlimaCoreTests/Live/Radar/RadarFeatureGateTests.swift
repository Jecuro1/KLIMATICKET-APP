import XCTest
@testable import KlimaCore

/// The radar's live loop, the Pünktlichkeit layer, the Zeitreise and the Cockpit-Ansicht together (docs/OEBB_LIVE.md §R11.3). The radar view
/// asks `RadarFeatureGate` which loop runs and how a Zeitreise ends; these tests switch between the features the way a person can (the layer
/// bar is hidden while the Zeitreise's card is open, nothing of the radar is reachable under the cockpit, the access and the app's state change
/// at any time) and check that the state stays consistent after every step, in every order.
final class RadarFeatureGateTests: XCTestCase {
    // MARK: A person on the radar

    /// What a person (or the phone) can do on the radar. Each step only where the screen offers it.
    private enum Step: CaseIterable {
        case toggleTrains, togglePunctuality, toggleOtherMode
        case openTime, closeTime, scrubAway, backToNow
        case openCockpit, closeCockpit
        case background, foreground
        case goOffline, goOnline, closeAccess, openAccess
    }

    /// The step on `gate` as the radar view does it, then what the view's hooks do when the picture changed (`RadarTimeHooks`). Nil when the
    /// screen does not offer the step in this state.
    private func apply(_ step: Step, to gate: RadarFeatureGate) -> RadarFeatureGate? {
        var next = gate
        // The layer bar waits while the Zeitreise's card is open; under the cockpit nothing of the radar can be touched.
        let barShown = !gate.timeOpen && !gate.cockpitOpen
        switch step {
        case .toggleTrains:
            guard barShown else { return nil }
            next.layers.toggle(.trains)
        case .togglePunctuality:
            guard barShown else { return nil }
            next.layers.toggle(.punctuality)
        case .toggleOtherMode:   // the mode chips at the top (Bus, Bim, ...): a bus on, or off again
            guard !gate.cockpitOpen else { return nil }
            next.railOnly.toggle()
        case .openTime:   // the clock chip is shown only while the Zeitreise is offered
            guard gate.timeAvailable, !gate.timeOpen, !gate.cockpitOpen else { return nil }
            next.timeOpen = true
        case .closeTime:
            guard gate.timeOpen, !gate.cockpitOpen else { return nil }
            next.timeOpen = false
        case .scrubAway:
            guard gate.timeAvailable, gate.timeOpen, !gate.cockpitOpen else { return nil }
            next.timeAway = true
        case .backToNow:   // "Zurück zu Jetzt" on the card or the chip
            guard gate.timeAway, !gate.cockpitOpen else { return nil }
            next.timeAway = false
        case .openCockpit:   // the trip sheet of a train on the map ("Cockpit"), live or from a Zeitreise
            guard gate.trainsOn, gate.sceneActive, !gate.cockpitOpen else { return nil }
            next.cockpitOpen = true
        case .closeCockpit:
            guard gate.cockpitOpen else { return nil }
            next.cockpitOpen = false
        case .background:
            guard gate.sceneActive else { return nil }
            next.sceneActive = false
        case .foreground:
            guard !gate.sceneActive else { return nil }
            next.sceneActive = true
        case .goOffline:
            guard gate.access == .open else { return nil }
            next.access = .offline
        case .goOnline:
            guard gate.access == .offline else { return nil }
            next.access = .open
        case .closeAccess:   // the kill switch, or live data switched off: at any time
            guard gate.access != .closed else { return nil }
            next.access = .closed
        case .openAccess:
            guard gate.access == .closed else { return nil }
            next.access = .open
        }
        // The intermediate frame, before the hooks have run, must be consistent as well: it is drawn.
        assertNoTwoSenders(next, "before the hooks, \(step)")
        if RadarFeatureGate.timeEnding(from: gate, to: next) != nil {
            next.timeOpen = false   // `reset` and `suspend` both end the Zeitreise
            next.timeAway = false
        }
        return next
    }

    /// The parts that ask the ÖBB right now: the live loop, the Zeitreise (only while away from now) and the cockpit.
    private func senders(_ gate: RadarFeatureGate) -> Int {
        [gate.liveLoopRuns, gate.timeLoopRuns && gate.timeAway, gate.cockpitOpen].filter { $0 }.count
    }

    private func assertNoTwoSenders(_ gate: RadarFeatureGate, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(senders(gate), 1, "two parts send at once (\(context)): \(gate)", file: file, line: line)
    }

    /// What must hold whenever the hooks have run.
    private func assertConsistent(_ gate: RadarFeatureGate, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        assertNoTwoSenders(gate, context, file: file, line: line)
        let timeActive = gate.timeOpen || gate.timeAway
        // The Zeitreise pauses the live loop.
        if gate.timeAway { XCTAssertFalse(gate.liveLoopRuns, "the live loop runs during a Zeitreise (\(context))", file: file, line: line) }
        // A Zeitreise exists only where it is offered: never next to the Pünktlichkeit layer, another mode or without live data.
        if timeActive {
            XCTAssertTrue(gate.timeAvailable, "a Zeitreise outlived what offers it (\(context)): \(gate)", file: file, line: line)
            XCTAssertFalse(gate.heatOn, "the Pünktlichkeit layer next to a Zeitreise (\(context))", file: file, line: line)
        }
        // The cockpit asks for its one train instead of the radar.
        if gate.cockpitOpen {
            XCTAssertFalse(gate.liveLoopRuns, "the live loop runs under the cockpit (\(context))", file: file, line: line)
            XCTAssertFalse(gate.timeLoopRuns, "the Zeitreise runs under the cockpit (\(context))", file: file, line: line)
        }
        // On screen without a cockpit, the live loop runs exactly when a layer needs it and the picture is now: the Pünktlichkeit layer is
        // never left without the loop that loads all of Austria for it, and no loop runs for nothing.
        if gate.sceneActive && !gate.cockpitOpen {
            XCTAssertEqual(gate.liveLoopRuns, gate.loadsRadar && !gate.timeAway, "live loop (\(context)): \(gate)", file: file, line: line)
            if gate.heatOn { XCTAssertTrue(gate.liveLoopRuns, "the Pünktlichkeit layer has no loop (\(context))", file: file, line: line) }
            XCTAssertEqual(gate.timeLoopRuns, timeActive, "Zeitreise loop (\(context)): \(gate)", file: file, line: line)
        }
        // In the background nothing runs.
        if !gate.sceneActive {
            XCTAssertFalse(gate.liveLoopRuns, "live loop in the background (\(context))", file: file, line: line)
            XCTAssertFalse(gate.timeLoopRuns, "Zeitreise loop in the background (\(context))", file: file, line: line)
        }
    }

    private func key(_ gate: RadarFeatureGate) -> String {
        "\(gate.layers.storageValue)|\(gate.access)|\(gate.railOnly)|\(gate.sceneActive)|\(gate.cockpitOpen)|\(gate.timeOpen)|\(gate.timeAway)"
    }

    // MARK: Every order

    func testEveryOrderOfSwitchingBetweenTheFeaturesLeavesAConsistentState() {
        // Every state a person can reach from a fresh radar, and every step from each of them: that is every order of switching.
        let start = RadarFeatureGate()
        assertConsistent(start, "start")
        var seen: Set<String> = [key(start)]
        var queue = [start]
        var transitions = 0
        while let gate = queue.popLast() {
            for step in Step.allCases {
                guard let next = apply(step, to: gate) else { continue }
                transitions += 1
                assertConsistent(next, "\(key(gate)) + \(step)")
                // From anywhere, closing the cockpit, coming back to the app and "Zurück zu Jetzt" give the live radar back.
                var back = next
                for step in [Step.closeCockpit, .foreground, .backToNow] {
                    if let moved = apply(step, to: back) { back = moved }
                }
                assertConsistent(back, "\(key(next)) and back")
                XCTAssertEqual(back.liveLoopRuns, back.loadsRadar, "the live radar does not come back after \(key(next))")
                if seen.insert(key(next)).inserted { queue.append(next) }
            }
        }
        // The walk reached every state a person can reach (the stations stay on, they change nothing here): 48 of the live radar (two layers ×
        // access × modes × scene), 24 under the cockpit (it opens only from a train on the map, and its cover keeps the layers and modes as
        // they were), and 12 with a Zeitreise (open at now, open away, folded away; in the background or not; under the cockpit or not).
        XCTAssertEqual(seen.count, 48 + 24 + 12)
        XCTAssertGreaterThan(transitions, 400)
    }

    // MARK: The single rules, one by one

    func testAZeitreiseAwayFromNowPausesTheLiveLoopAndBackToNowResumesIt() throws {
        var gate = RadarFeatureGate()
        XCTAssertTrue(gate.liveLoopRuns)
        XCTAssertFalse(gate.timeLoopRuns)
        gate = try XCTUnwrap(apply(.openTime, to: gate))
        XCTAssertTrue(gate.liveLoopRuns, "the open card at Jetzt: the live radar is the picture")
        XCTAssertTrue(gate.timeLoopRuns, "and the Zeitreise's loop waits for the scrubber (it sends nothing at now)")
        gate = try XCTUnwrap(apply(.scrubAway, to: gate))
        XCTAssertFalse(gate.liveLoopRuns)
        XCTAssertTrue(gate.timeLoopRuns)
        gate = try XCTUnwrap(apply(.closeTime, to: gate))
        XCTAssertFalse(gate.liveLoopRuns, "folded to its chip the Zeitreise is still away from now")
        XCTAssertTrue(gate.timeLoopRuns)
        gate = try XCTUnwrap(apply(.backToNow, to: gate))
        XCTAssertTrue(gate.liveLoopRuns)
        XCTAssertFalse(gate.timeLoopRuns)
    }

    func testThePunctualityLayerEndsAZeitreiseAndThenLoadsAustria() throws {
        var gate = RadarFeatureGate()
        gate = try XCTUnwrap(apply(.openTime, to: gate))
        gate = try XCTUnwrap(apply(.scrubAway, to: gate))
        XCTAssertNil(apply(.togglePunctuality, to: gate), "the layer bar waits while the card is open")
        gate = try XCTUnwrap(apply(.closeTime, to: gate))
        // The chip says where the Zeitreise is; the layer bar is back. Switching the layer on ends the Zeitreise (it does not wait behind it).
        var on = gate
        on.layers.toggle(.punctuality)
        XCTAssertEqual(RadarFeatureGate.timeEnding(from: gate, to: on), .reset)
        XCTAssertFalse(on.heatOn, "for the frame before the Zeitreise has ended, the layer stays off: its numbers are about now")
        gate = try XCTUnwrap(apply(.togglePunctuality, to: gate))
        XCTAssertFalse(gate.timeAway)
        XCTAssertTrue(gate.heatOn)
        XCTAssertTrue(gate.liveLoopRuns, "the live loop loads all of Austria for the layer")
        XCTAssertFalse(gate.timeAvailable, "and the clock chip is gone while the layer is on")
        XCTAssertNil(apply(.openTime, to: gate))
    }

    func testThePunctualityLayerAloneKeepsTheLoopRunning() throws {
        var gate = RadarFeatureGate()
        gate = try XCTUnwrap(apply(.togglePunctuality, to: gate))
        gate = try XCTUnwrap(apply(.toggleTrains, to: gate))
        XCTAssertFalse(gate.trainsOn)
        XCTAssertTrue(gate.heatOn)
        XCTAssertTrue(gate.liveLoopRuns, "without the train layer the layer still needs the trains of Austria")
        gate = try XCTUnwrap(apply(.togglePunctuality, to: gate))
        XCTAssertFalse(gate.liveLoopRuns, "no layer that needs the radar: nothing is asked")
    }

    func testTheCockpitStopsBothLoopsAndClosingItResumesWhatRanBefore() throws {
        // From the live radar.
        var gate = RadarFeatureGate()
        gate = try XCTUnwrap(apply(.openCockpit, to: gate))
        XCTAssertFalse(gate.liveLoopRuns)
        XCTAssertEqual(senders(gate), 1, "only the cockpit asks")
        gate = try XCTUnwrap(apply(.closeCockpit, to: gate))
        XCTAssertTrue(gate.liveLoopRuns)

        // From a Zeitreise: under the cockpit neither loop runs, afterwards the Zeitreise goes on where it was.
        gate = try XCTUnwrap(apply(.openTime, to: gate))
        gate = try XCTUnwrap(apply(.scrubAway, to: gate))
        gate = try XCTUnwrap(apply(.openCockpit, to: gate))
        XCTAssertFalse(gate.liveLoopRuns)
        XCTAssertFalse(gate.timeLoopRuns)
        XCTAssertTrue(gate.timeAway, "the cockpit does not end the Zeitreise")
        gate = try XCTUnwrap(apply(.closeCockpit, to: gate))
        XCTAssertTrue(gate.timeLoopRuns)
        XCTAssertFalse(gate.liveLoopRuns)

        // From the Pünktlichkeit layer (a train dot's trip sheet): the layer's loop stops and comes back.
        gate = try XCTUnwrap(apply(.backToNow, to: gate))
        gate = try XCTUnwrap(apply(.closeTime, to: gate))
        gate = try XCTUnwrap(apply(.togglePunctuality, to: gate))
        gate = try XCTUnwrap(apply(.openCockpit, to: gate))
        XCTAssertTrue(gate.heatOn, "the layer stays on under the cockpit")
        XCTAssertFalse(gate.liveLoopRuns, "but its loop waits: the cockpit asks for its one train instead")
        gate = try XCTUnwrap(apply(.closeCockpit, to: gate))
        XCTAssertTrue(gate.liveLoopRuns)
    }

    func testOfflineSuspendsAZeitreiseAndAClosedAccessResetsIt() {
        var away = RadarFeatureGate(timeOpen: true, timeAway: true)
        var offline = away
        offline.access = .offline
        XCTAssertEqual(RadarFeatureGate.timeEnding(from: away, to: offline), .suspend, "offline keeps what was loaded")
        var closed = away
        closed.access = .closed
        XCTAssertEqual(RadarFeatureGate.timeEnding(from: away, to: closed), .reset, "the kill switch or live data off ends everything")
        XCTAssertEqual(RadarFeatureGate.timeEnding(from: offline, to: closed), .reset, "offline first, then switched off: everything ends")
        var bus = away
        bus.railOnly = false
        XCTAssertEqual(RadarFeatureGate.timeEnding(from: away, to: bus), .reset, "another mode: the snapshots are of trains")
        var noTrains = away
        noTrains.layers.toggle(.trains)
        XCTAssertEqual(RadarFeatureGate.timeEnding(from: away, to: noTrains), .reset)
        // Nothing that leaves the Zeitreise offered ends it: the background, the cockpit, the card folding.
        away.sceneActive = false
        XCTAssertNil(RadarFeatureGate.timeEnding(from: RadarFeatureGate(timeOpen: true, timeAway: true), to: away))
        away.cockpitOpen = true
        away.timeOpen = false
        XCTAssertNil(RadarFeatureGate.timeEnding(from: RadarFeatureGate(timeOpen: true, timeAway: true), to: away))
    }

    func testOfflineTheRadarAsksNothingAndOnlineAgainItResumes() throws {
        var gate = RadarFeatureGate(layers: MapLayerSelection(layers: [.stations, .trains, .punctuality]))
        XCTAssertTrue(gate.liveLoopRuns)
        gate = try XCTUnwrap(apply(.goOffline, to: gate))
        XCTAssertFalse(gate.trainsOn)
        XCTAssertFalse(gate.heatOn)
        XCTAssertFalse(gate.liveLoopRuns)
        gate = try XCTUnwrap(apply(.goOnline, to: gate))
        XCTAssertTrue(gate.liveLoopRuns)
        XCTAssertTrue(gate.heatOn)
    }
}
