import Foundation
import ActivityKit

// "Aufzeichnung läuft" Live Activity (docs/TRIP_DETECTION.md §2): while "Fahrt aufzeichnen" runs, the Lock Screen and the Dynamic
// Island show the elapsed time, the distance and the station you are at. Started and updated by the app only while a recording
// runs, `pushType: nil` (no remote pushes, no APNs). Shared source file: compiled into the app and the widget extension.

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var distanceKm: Double
        var speedKmh: Double
        /// The station the phone is at right now, else the last one it passed.
        var stationName: String?
        var isAtStation: Bool
        /// Stopped: the activity shows "Gestoppt" until it is dismissed.
        var isStopped: Bool
        /// When it was stopped: the timer stands still at that moment instead of counting on until the activity goes away.
        var stoppedAt: Date?

        init(distanceKm: Double = 0, speedKmh: Double = 0, stationName: String? = nil, isAtStation: Bool = false, isStopped: Bool = false,
             stoppedAt: Date? = nil) {
            self.distanceKm = distanceKm
            self.speedKmh = speedKmh
            self.stationName = stationName
            self.isAtStation = isAtStation
            self.isStopped = isStopped
            self.stoppedAt = stoppedAt
        }
    }

    var startedAt: Date

    /// Elapsed-time range for `Text(timerInterval:)` (counts up from the start, stops after 12 hours).
    var timerRange: ClosedRange<Date> { startedAt...startedAt.addingTimeInterval(12 * 3600) }
}
