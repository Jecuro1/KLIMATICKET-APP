import Foundation

// MARK: radartrail – „Verspätung, seit du zuschaust“ (docs/RADAR_TRAILS.md §5): how the delay of one vehicle moved in the answers this iPhone got
// while the radar was open. Built from the recorder's samples, nothing else; shown only when there is enough of it (no empty promise).

public struct RadarDelaySeries: Sendable, Equatable {
    public struct Point: Sendable, Hashable {
        public var at: Date
        /// Whole minutes late (negative: early), as the radar's markers count them.
        public var minutes: Int

        public init(at: Date, minutes: Int) {
            self.at = at
            self.minutes = minutes
        }
    }

    public enum Trend: String, Sendable {
        case rising, falling, steady
    }

    /// At least this many moments with a delay …
    public static let minimumMoments = 3
    /// … over at least this long.
    public static let minimumSpan: TimeInterval = 120
    /// A change of at least this many minutes is a trend.
    public static let trendMinutes = 2

    /// A run of equal minutes keeps its first and its last moment, so the line stays flat as long as the delay did.
    public private(set) var points: [Point] = []
    /// The moments with a delay behind the points (a stand counts its first and its last answer).
    public private(set) var moments = 0
    /// A later answer called the run cancelled: the series ends there.
    public private(set) var endsCancelled = false

    public init(samples: [RadarTrailSample]) {
        for sample in samples {
            if sample.isCancelled {
                endsCancelled = true
                break
            }
            guard let seconds = sample.delaySeconds else { continue }
            let minutes = seconds / 60
            add(Point(at: sample.from, minutes: minutes))
            if sample.to > sample.from { add(Point(at: sample.to, minutes: minutes)) }
        }
    }

    private mutating func add(_ point: Point) {
        moments += 1
        let n = points.count
        if n >= 2, points[n - 1].minutes == point.minutes, points[n - 2].minutes == point.minutes {
            points[n - 1].at = point.at   // the run grows: its last moment moves
        } else {
            points.append(point)
        }
    }

    public var start: Date? { points.first?.at }
    public var end: Date? { points.last?.at }
    public var first: Int? { points.first?.minutes }
    public var last: Int? { points.last?.minutes }

    public var span: TimeInterval {
        guard let start, let end else { return 0 }
        return end.timeIntervalSince(start)
    }

    /// Enough to be worth a row: three moments over two minutes.
    public var isShowable: Bool { moments >= Self.minimumMoments && span >= Self.minimumSpan }

    /// From the first to the last point: up by two minutes or more, down by two or more, or about the same.
    public var trend: Trend {
        guard let first, let last else { return .steady }
        if last - first >= Self.trendMinutes { return .rising }
        if last - first <= -Self.trendMinutes { return .falling }
        return .steady
    }

    /// The smallest and the largest value (the chart's range).
    public var range: ClosedRange<Int>? {
        guard let low = points.map(\.minutes).min(), let high = points.map(\.minutes).max() else { return nil }
        return low...high
    }
}
