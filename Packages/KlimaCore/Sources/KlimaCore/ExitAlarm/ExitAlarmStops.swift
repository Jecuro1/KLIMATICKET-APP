import Foundation

// Aussteige-Wecker: which stops the alarm can wake you for, and the spec built from a followed run (docs/EXIT_ALARM.md §2).
// Pure: the planner, the Zug-Radar and the connection detail pass the stopovers of the run.

/// One stop the user can pick in the sheet.
public struct ExitAlarmStopOption: Hashable, Sendable, Identifiable {
    public var id: String { lid }
    public var lid: String
    public var name: String
    public var coordinate: GeoPoint?
    public var plannedArrival: Date?
    /// Realtime arrival when the timetable reports one, else the planned one.
    public var effectiveArrival: Date?
    public var delaySeconds: Int?
    public var platform: String?
    /// The last stop the user rides to (the end of the leg).
    public var isEnd: Bool
    /// The user changes trains here.
    public var isTransfer: Bool
}

public enum ExitAlarmStops {
    /// The stops from the one after boarding through the end of the leg. The end of the leg is a transfer when the
    /// connection goes on (`transferAtEnd`). Stops the train passes without stopping are left out.
    public static func options(stopovers: [Stopover], boardingIndex: Int?, endIndex: Int?, transferAtEnd: Bool) -> [ExitAlarmStopOption] {
        guard !stopovers.isEmpty else { return [] }
        let first = min((boardingIndex ?? 0) + 1, stopovers.count - 1)
        let last = min(max(endIndex ?? stopovers.count - 1, first), stopovers.count - 1)
        guard first <= last else { return [] }
        return (first...last).compactMap { index -> ExitAlarmStopOption? in
            let stop = stopovers[index]
            guard !stop.passesWithoutStop || index == last else { return nil }
            let arrival = stop.arrival ?? stop.departure
            let isEnd = index == last
            return ExitAlarmStopOption(lid: stop.location.lid, name: stop.location.name, coordinate: stop.location.coordinate,
                                       plannedArrival: arrival?.planned, effectiveArrival: arrival?.effective,
                                       delaySeconds: arrival?.delaySeconds,
                                       platform: arrival?.platform?.text ?? stop.departure?.platform?.text,
                                       isEnd: isEnd, isTransfer: isEnd && transferAtEnd)
        }
    }

    /// The spec of an alarm for `option` on the followed run. The path runs from the boarding stop to the option.
    public static func spec(target: LiveFollowTarget, stopovers: [Stopover], boardingIndex: Int?, option: ExitAlarmStopOption,
                            lead: ExitAlarmLead, soundKey: String, now: Date) -> ExitAlarmSpec {
        let boarding = boardingIndex ?? 0
        let end = stopovers.firstIndex { $0.location.lid == option.lid } ?? stopovers.count - 1
        let path: [GeoPoint] = stopovers.indices.filter { $0 >= boarding && $0 <= end }.compactMap { stopovers[$0].location.coordinate }
        let boardingStop = stopovers.indices.contains(boarding) ? stopovers[boarding] : nil
        return ExitAlarmSpec(tripID: target.tripID, lineName: target.lineName, stopID: option.lid, stopName: option.name,
                             stopCoordinate: option.coordinate, platform: option.platform, path: path,
                             plannedArrival: option.plannedArrival,
                             boardingDeparture: boardingStop?.departure?.planned ?? target.plannedDeparture,
                             lead: lead, isTransfer: option.isTransfer, createdAt: now, soundKey: soundKey)
    }

    /// The timetable data of the spec's stop in a fresh answer: effective arrival, departure and the delay. Nil when the
    /// stop is not in the run any more.
    public static func timetable(for spec: ExitAlarmSpec, in stopovers: [Stopover]) -> (arrival: Date?, departure: Date?, delaySeconds: Int?)? {
        guard let stop = stopovers.first(where: { $0.location.lid == spec.stopID }) else { return nil }
        let arrival = stop.arrival ?? stop.departure
        return (arrival?.effective, stop.arrival == nil ? nil : stop.departure?.effective, arrival?.delaySeconds)
    }
}
