import Foundation

// Verspätungs-Heatmap, the trend of this session (docs/RADAR_HEATMAP.md §6). The national punctuality at the moments this radar
// session has had an answer, for the sparkline in the panel. In memory only: it lives as long as the radar screen, is never written
// to disk and starts empty every time. Pure: every call gets its time.

public struct HeatHistory: Sendable, Equatable {
    public struct Point: Sendable, Hashable {
        public var at: Date
        /// Share of punctual trains among those with realtime data, 0 to 1.
        public var share: Double
        /// Trains with realtime data behind the share.
        public var base: Int
    }

    /// One point at most this often (the radar answers every 20 s; a point per answer would only be noise).
    public static let minimumGap: TimeInterval = 30
    /// The newest points kept: 120 × 30 s = one hour.
    public static let capacity = 120
    /// A trend needs a line, and a line needs a stretch of time: three points over at least a minute.
    public static let minimumSpan: TimeInterval = 60
    /// Fewer trains with realtime data than this say too little to put in a trend line.
    public static let minimumBase = 20

    public private(set) var points: [Point] = []

    public init() {}

    /// Notes the summary of one moment. Ignored without realtime data, with too few trains behind it, closer than `minimumGap` to the
    /// last point, and when `now` lies before the last point (the clock went back: the old points would no longer be in order).
    public mutating func record(_ summary: HeatSummary, at now: Date) {
        guard let share = summary.punctualShare, summary.withRealtime >= Self.minimumBase else { return }
        if let last = points.last {
            guard now.timeIntervalSince(last.at) >= Self.minimumGap else { return }
        }
        points.append(Point(at: now, share: share, base: summary.withRealtime))
        if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
    }

    public mutating func reset() { points = [] }

    /// Whole percent like `HeatSummary.punctualPercent`: never 100 while some train is late, never 0 while some is punctual.
    static func percent(_ share: Double) -> Int {
        var percent = Int((share * 100).rounded())
        if share < 1 { percent = min(percent, 99) }
        if share > 0 { percent = max(percent, 1) }
        return percent
    }

    /// True when the line is worth drawing.
    public var hasTrend: Bool {
        guard points.count >= 3, let first = points.first, let last = points.last else { return false }
        return last.at.timeIntervalSince(first.at) >= Self.minimumSpan
    }

    /// How long the session has been recording, in seconds (0 with fewer than two points).
    public var span: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.at.timeIntervalSince(first.at)
    }

    /// "Seit 6 Min: 85 % → 87 %". Nil without a trend.
    public var caption: String? {
        guard hasTrend, let first = points.first, let last = points.last else { return nil }
        let minutes = max(1, Int((span / 60).rounded()))
        let a = Self.percent(first.share), b = Self.percent(last.share)
        return a == b ? "Seit \(minutes) Min unverändert bei \(b) %" : "Seit \(minutes) Min: \(a) % → \(b) %"
    }
}
