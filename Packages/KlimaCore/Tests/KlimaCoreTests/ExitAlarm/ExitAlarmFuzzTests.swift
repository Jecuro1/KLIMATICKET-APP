import XCTest
@testable import KlimaCore

/// Random event sequences against the planner: whatever the order of fixes, ticks, timetable changes, circle entries and user
/// actions, the invariants hold: one ring per firing, nothing after the end, no NaN or infinite number on the card.
final class ExitAlarmFuzzTests: XCTestCase {
    typealias F = ExitAlarmFixtures

    /// A small deterministic generator (SplitMix64), so a failure reproduces.
    private struct Rng: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    func testInvariantsHoldForRandomSequences() {
        for seed in 1...200 {
            var rng = Rng(state: UInt64(seed))
            let lead = ExitAlarmLead.allCases.randomElement(using: &rng)!
            var state = ExitAlarmPlanner.arm(F.spec(stop: 2, lead: lead), arrival: F.arrival(at: 2), departure: Bool.random(using: &rng) ? F.arrival(at: 2).addingTimeInterval(120) : nil,
                                             now: F.t0.addingTimeInterval(-300)).state
            var now = F.t0.addingTimeInterval(-300)
            var arrivalRings = 0
            let path = GeoPath(F.path(to: 4))

            for _ in 0..<120 {
                now = now.addingTimeInterval(Double.random(in: 1...90, using: &rng))
                let event: ExitAlarmEvent
                switch Int.random(in: 0..<14, using: &rng) {
                case 0, 1, 2, 3, 4:
                    let along = Double.random(in: 0...(path.length * 1.05), using: &rng)
                    let speed: Double? = Bool.random(using: &rng) ? Double.random(in: 0...60, using: &rng) : nil
                    event = .fix(LocationFix(time: now.addingTimeInterval(-Double.random(in: 0...80, using: &rng)),
                                             coordinate: path.point(at: along) ?? F.salzburg, speed: speed,
                                             horizontalAccuracy: Double.random(in: -5...400, using: &rng)))
                case 5, 6: event = .tick
                case 7:
                    let shift = Double.random(in: -900...1800, using: &rng)
                    event = .timetable(arrival: Bool.random(using: &rng) ? F.arrival(at: 2).addingTimeInterval(shift) : nil,
                                       departure: nil, delaySeconds: Int(shift))
                case 8: event = .regionEntered
                case 9: event = .timeAlarmRang
                case 10: event = .timeAlarmUnavailable
                case 11: event = .acknowledge
                case 12: event = .snooze(minutes: Int.random(in: 0...30, using: &rng))
                default: event = Int.random(in: 0..<6, using: &rng) == 0 ? .end(.followEnded) : .tick
                }
                let wasEnded = state.phase == .ended
                let effects = ExitAlarmPlanner.apply(event, to: &state, now: now)
                if wasEnded { XCTAssertTrue(effects.isEmpty, "seed \(seed): effects after the end") }
                for effect in effects {
                    if case .ring = effect { arrivalRings += 1 }
                    if case .scheduleTimeAlarm(let date) = effect { XCTAssertGreaterThan(date, now, "seed \(seed): an alarm in the past") }
                }

                let estimate = ExitAlarmPresentation.estimate(state, now: now)
                XCTAssertTrue((0...1).contains(estimate.progress), "seed \(seed): progress \(estimate.progress)")
                for value in [estimate.remainingSeconds, estimate.remainingMeters, estimate.secondsUntilAlarm].compactMap({ $0 }) {
                    XCTAssertTrue(value.isFinite && value >= 0, "seed \(seed): number \(value)")
                }
                // A scheduled time alarm only exists while the alarm still waits.
                if state.scheduledTimeAlarm != nil {
                    XCTAssertTrue([.armed, .approaching, .snoozed].contains(state.phase), "seed \(seed): scheduled alarm in \(state.phase)")
                }
                // The geofence only exists while the alarm still waits.
                if state.geofenceRadius != nil {
                    XCTAssertTrue([.armed, .approaching, .snoozed].contains(state.phase), "seed \(seed): circle in \(state.phase)")
                }
            }
            // One ring for the arrival and one for each snooze that ended, at most ("vorbeigefahren" is its own effect).
            XCTAssertLessThanOrEqual(arrivalRings, 1 + state.snoozeCount, "seed \(seed): \(arrivalRings) rings, \(state.snoozeCount) snoozes")
        }
    }
}
