import SwiftUI
import KlimaCore

// MARK: exitalarm – demo scenes and CI screenshot hosts for the Aussteige-Wecker (docs/EXIT_ALARM.md §5). The states are made by the
// real planner from a scripted run (the demo RJX 66 of DemoScotty), so the numbers on screen are the planner's, not painted on.
// No network, no permission prompt, no system alarm and no location: the hosts draw views, the service runs on fakes.

enum ExitAlarmDemo {
    /// The demo run: Wien Hbf → … → Linz Hbf → … → Innsbruck Hbf.
    static var run: DemoScotty.Run { DemoScotty.runs[0] }
    static let linzIndex = 3
    static let speed = 38.0

    static func stopovers(now: Date) -> [Stopover] { DemoScotty.stopovers(run, now: now) }

    static func target(now: Date) -> LiveFollowTarget {
        let stops = stopovers(now: now)
        return LiveFollowTarget(tripID: run.tripID, lineName: "RJX 66", boardingStop: stops[0].location,
                                alightStop: stops[stops.count - 1].location,
                                plannedDeparture: stops[0].departure?.planned, plannedArrival: stops[stops.count - 1].arrival?.planned)
    }

    static func input(now: Date) -> ExitAlarmSheetInput {
        let stops = stopovers(now: now)
        return ExitAlarmSheetInput(target: target(now: now), stopovers: stops, preselectedStopID: stops[linzIndex].location.lid, now: now)
    }

    static func spec(now: Date, lead: ExitAlarmLead = .fiveMinutes) -> ExitAlarmSpec {
        let stops = stopovers(now: now)
        let legs = ExitAlarmStops.legIndices(target: target(now: now), stopovers: stops)
        let options = ExitAlarmStops.options(stopovers: stops, boardingIndex: legs.boarding, endIndex: legs.end, transferAtEnd: false, now: now)
        let option = options.first { $0.lid == stops[linzIndex].location.lid } ?? options[0]
        return ExitAlarmStops.spec(target: target(now: now), stopovers: stops, boardingIndex: legs.boarding, option: option,
                                   lead: lead, soundKey: "standard", now: now)
    }

    enum Scene { case armed, approaching, fired, passed }

    /// The state of a scene at `now`, built by the planner.
    static func state(_ scene: Scene, now: Date) -> ExitAlarmState {
        let spec = spec(now: now)
        let path = GeoPath(spec.path)
        switch scene {
        case .armed:
            let arrival = stopovers(now: now)[linzIndex].arrival?.effective ?? now.addingTimeInterval(31 * 60)
            var state = ExitAlarmPlanner.arm(spec, arrival: arrival, delaySeconds: 300, now: now).state
            // The train is between St. Pölten and Amstetten, 38 m/s.
            let position = path.point(at: path.length * 0.42) ?? spec.path[0]
            for step in 0..<2 {
                ExitAlarmPlanner.apply(.fix(LocationFix(time: now.addingTimeInterval(Double(step) * 5 - 8), coordinate: position, speed: speed,
                                                         horizontalAccuracy: 25)), to: &state, now: now.addingTimeInterval(Double(step) * 5 - 6))
            }
            ExitAlarmPlanner.apply(.tick, to: &state, now: now)
            return state
        case .approaching, .fired:
            let arrival = now.addingTimeInterval(7 * 60)
            var state = ExitAlarmPlanner.arm(spec, arrival: arrival, delaySeconds: 360, now: now).state
            let position = path.point(at: path.length - speed * 7 * 60) ?? spec.path[0]
            for step in 0..<2 {
                ExitAlarmPlanner.apply(.fix(LocationFix(time: now.addingTimeInterval(Double(step) * 5 - 8), coordinate: position, speed: speed,
                                                         horizontalAccuracy: 25)), to: &state, now: now.addingTimeInterval(Double(step) * 5 - 6))
            }
            ExitAlarmPlanner.apply(.tick, to: &state, now: now)
            if scene == .fired { ExitAlarmPlanner.apply(.regionEntered, to: &state, now: now) }
            return state
        case .passed:
            var state = ExitAlarmPlanner.arm(spec, arrival: now.addingTimeInterval(-200), departure: now.addingTimeInterval(-100),
                                             delaySeconds: 360, now: now.addingTimeInterval(-400)).state
            ExitAlarmPlanner.apply(.tick, to: &state, now: now)
            return state
        }
    }

    /// The Live Activity as the Lock Screen draws it while the alarm is armed.
    static func activityState(_ state: ExitAlarmState, now: Date) -> FollowLiveState {
        let info = ExitAlarmBookHolder.info(state, now: now)
        return FollowLiveState(stage: .riding, nextStopName: "Amstetten", nextStopTime: now.addingTimeInterval(5 * 60), delayMinutes: 5,
                               platform: "4", progress: 0.42, updatedAt: now, exitAlarm: info)
    }
}

/// Builds the Live Activity info of one state the way the book does.
private enum ExitAlarmBookHolder {
    static func info(_ state: ExitAlarmState, now: Date) -> FollowExitAlarmInfo? {
        var book = ExitAlarmBook()
        _ = book.arm(state.spec, arrival: state.timetableArrival, departure: state.timetableDeparture, delaySeconds: state.delaySeconds,
                     now: now.addingTimeInterval(-10))
        return book.activityInfo(now: now)
    }
}

struct ExitAlarmScreenshotHost: View {
    static let screens: Set<String> = ["exitAlarmSheet", "exitAlarmLocation", "exitAlarmArmed", "exitAlarmApproaching",
                                       "exitAlarmFired", "exitAlarmPassed", "exitAlarmSettings"]

    let screen: String
    private let now = Date()

    var body: some View {
        switch screen {
        case "exitAlarmSheet":
            ExitAlarmSheet(input: ExitAlarmDemo.input(now: now))
        case "exitAlarmLocation":
            NavigationStack { ExitAlarmLocationExplainer(onContinue: {}, onSkip: {}) }
        case "exitAlarmArmed":
            ExitAlarmCardScene(state: ExitAlarmDemo.state(.armed, now: now), now: now)
        case "exitAlarmApproaching":
            ExitAlarmCardScene(state: ExitAlarmDemo.state(.approaching, now: now), now: now)
        case "exitAlarmFired":
            ExitAlarmFiredView(state: ExitAlarmDemo.state(.fired, now: now), now: now)
        case "exitAlarmPassed":
            ExitAlarmFiredView(state: ExitAlarmDemo.state(.passed, now: now), now: now)
        default:
            NavigationStack {
                List { SetExitAlarmSection() }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                    .navigationTitle("Aussteige-Wecker")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// The card where it lives (the follow detail), with the Live Activity below it.
private struct ExitAlarmCardScene: View {
    let state: ExitAlarmState
    let now: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ExitAlarmCard(state: state, now: now, kind: .alarmKit, locationAuthorization: .always, showsActions: true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("LIVE-AKTIVITÄT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                        FollowLockScreenView(attributes: FollowDemo.attributes, state: ExitAlarmDemo.activityState(state, now: now))
                            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile))
                    }
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("RJX 66")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
