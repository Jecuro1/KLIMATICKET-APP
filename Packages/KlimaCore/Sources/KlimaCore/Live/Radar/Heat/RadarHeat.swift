import Foundation

// Verspätungs-Heatmap, the aggregation (docs/RADAR_HEATMAP.md). Pure and deterministic: vehicles in, numbers out. No clock of its
// own (`now` comes in where a delay is read), no network, no UI. The same input in any order gives the same cells, the same
// ranking and the same ids.
//
// The honesty rules this file enforces:
// - The delay of a train is the realtime delay ÖBB reports for the next stop it has not reached (`RadarDelay.currentDelay`).
// - A train without realtime data is counted, but never as punctual: it is not in the percentage and not in any median.
// - A cell with fewer than `minimumSample` trains that carry a delay stays neutral: no median, no colour.
// - The punctuality percentage is over the trains with realtime data only; a cancelled train counts as one of them, as not punctual.

/// What a train's delay says. The limits are the ones of the radar's marker tint (`RadarDelay.lateThresholdSeconds`).
public enum HeatBucket: String, Sendable, Hashable, CaseIterable {
    /// Less than 5 minutes late (early trains included).
    case onTime
    /// 5 to 15 minutes late (15:00 itself is still in here).
    case delayed
    /// More than 15 minutes late.
    case severe
    case cancelled
    /// The train carries no realtime delay: nothing is known, so it is never counted as punctual.
    case noRealtime
}

/// One train as the heat map sees it: where it is and what its delay is.
public struct HeatSample: Sendable, Hashable, Identifiable {
    public var tripID: String
    public var coordinate: GeoPoint
    /// "RJX 66"; "Zug" when the line is unknown.
    public var lineTitle: String
    public var direction: String?
    /// The stop the train is heading for; names a hot cell.
    public var nextStopName: String?
    /// Realtime delay in seconds at the next stop; nil without realtime data and for a cancelled train.
    public var delaySeconds: Int?
    public var isCancelled: Bool

    public var id: String { tripID }
    public var bucket: HeatBucket { RadarHeat.bucket(delaySeconds: delaySeconds, isCancelled: isCancelled) }

    public init(tripID: String, coordinate: GeoPoint, lineTitle: String = "Zug", direction: String? = nil, nextStopName: String? = nil,
                delaySeconds: Int? = nil, isCancelled: Bool = false) {
        self.tripID = tripID
        self.coordinate = coordinate
        self.lineTitle = lineTitle
        self.direction = direction
        self.nextStopName = nextStopName
        self.delaySeconds = isCancelled ? nil : delaySeconds
        self.isCancelled = isCancelled
    }

    /// From a radar vehicle at the position the map shows it (`RadarEstimate.shown`), with the delay it carries at `now`.
    public init(vehicle: RadarVehicle, coordinate: GeoPoint, now: Date) {
        self.init(tripID: vehicle.tripID, coordinate: coordinate,
                  lineTitle: vehicle.line.map { LinePresentation.title($0) } ?? "Zug", direction: vehicle.direction,
                  nextStopName: RadarRun.nextStop(of: vehicle, now: now)?.location.name,
                  delaySeconds: RadarDelay.currentDelay(of: vehicle, now: now), isCancelled: vehicle.isCancelled)
    }
}

/// The trains of one grid cell and what they say together.
public struct HeatCell: Sendable, Hashable, Identifiable {
    public var id: HeatCellID
    public var center: GeoPoint
    /// Every train in the cell (with or without realtime data, cancelled or not), sorted by trip id.
    public var tripIDs: [String]
    /// Trains that carry a delay (realtime data, not cancelled): the base of the median.
    public var sampleCount: Int
    public var cancelledCount: Int
    public var noRealtimeCount: Int
    /// Trains 5 minutes or more late.
    public var lateCount: Int
    /// Median delay of the sample trains in seconds. **nil when the cell has fewer than `RadarHeat.minimumSample` of them:** such
    /// a cell is neutral and is never coloured.
    public var medianDelaySeconds: Double?
    /// Sum of the delays of the sample trains in minutes (early trains count 0). What the hot spots are ranked by.
    public var delaySumMinutes: Double
    /// The next stop most of the trains are heading for (ties: the name that sorts first): a hint where the cell is.
    public var placeName: String?

    public var trainCount: Int { tripIDs.count }
    public var isNeutral: Bool { medianDelaySeconds == nil }

    /// The bucket of the median; nil for a neutral cell.
    public var bucket: HeatBucket? {
        guard let median = medianDelaySeconds else { return nil }
        return RadarHeat.bucket(medianSeconds: median)
    }
}

/// The national numbers (Austria and its border region, whatever the radar has loaded).
public struct HeatSummary: Sendable, Hashable {
    public var total = 0
    public var onTime = 0
    public var delayed = 0
    public var severe = 0
    public var cancelled = 0
    public var noRealtime = 0
    /// Mean delay of the trains 5 minutes or more late, in seconds; nil when there are none.
    public var averageLateSeconds: Double?

    public init() {}

    /// Trains with realtime data: on time, late, very late and cancelled. The base of every percentage.
    public var withRealtime: Int { onTime + delayed + severe + cancelled }
    /// Trains 5 minutes or more late.
    public var late: Int { delayed + severe }

    /// Share of punctual trains among those with realtime data; nil when none has any.
    public var punctualShare: Double? {
        withRealtime > 0 ? Double(onTime) / Double(withRealtime) : nil
    }

    /// The share as a whole percent for display. Never 100 while a train is late and never 0 while one is punctual: rounding
    /// must not say more than the numbers do.
    public var punctualPercent: Int? {
        guard let share = punctualShare else { return nil }
        var percent = Int((share * 100).rounded())
        if onTime < withRealtime { percent = min(percent, 99) }
        if onTime > 0 { percent = max(percent, 1) }
        return percent
    }

    /// The parts of the stacked bar, in order: punctual, 5 to 15 minutes, more than 15, cancelled. Each is a share of the trains
    /// with realtime data; empty when there are none.
    public var segments: [HeatSegment] {
        guard withRealtime > 0 else { return [] }
        return [HeatSegment(bucket: .onTime, count: onTime, base: withRealtime), HeatSegment(bucket: .delayed, count: delayed, base: withRealtime),
                HeatSegment(bucket: .severe, count: severe, base: withRealtime), HeatSegment(bucket: .cancelled, count: cancelled, base: withRealtime)]
    }
}

/// One part of the stacked bar.
public struct HeatSegment: Sendable, Hashable, Identifiable {
    public var bucket: HeatBucket
    public var count: Int
    /// Share of the trains with realtime data, 0 to 1.
    public var share: Double

    public var id: HeatBucket { bucket }

    init(bucket: HeatBucket, count: Int, base: Int) {
        self.bucket = bucket
        self.count = count
        self.share = base > 0 ? Double(count) / Double(base) : 0
    }
}

/// A place where trains are late right now: one cell, ranked by the sum of its delay minutes.
public struct HeatHotspot: Sendable, Hashable, Identifiable {
    public var rank: Int
    public var cellID: HeatCellID
    public var center: GeoPoint
    public var placeName: String?
    public var sampleCount: Int
    public var lateCount: Int
    public var medianDelaySeconds: Double
    public var delaySumMinutes: Double

    public var id: HeatCellID { cellID }
}

/// Everything the heat layer and its panel show, from one set of trains.
public struct HeatSnapshot: Sendable, Equatable {
    public var cells: [HeatCell]
    public var summary: HeatSummary
    /// The trains with the largest delay, at most 5, only those 5 minutes or more late.
    public var topDelays: [HeatSample]
    /// At most 3 places, ranked, at least one cell apart.
    public var hotspots: [HeatHotspot]
    private var samples: [String: HeatSample]

    public static let empty = HeatSnapshot(cells: [], summary: HeatSummary(), topDelays: [], hotspots: [], samples: [:])

    init(cells: [HeatCell], summary: HeatSummary, topDelays: [HeatSample], hotspots: [HeatHotspot], samples: [String: HeatSample]) {
        self.cells = cells
        self.summary = summary
        self.topDelays = topDelays
        self.hotspots = hotspots
        self.samples = samples
    }

    public var isEmpty: Bool { summary.total == 0 }

    /// Cells with at least one train, and those among them that have a colour (`RadarHeat.minimumSample` trains with a delay).
    public var populatedCellCount: Int { cells.count }
    public var colouredCellCount: Int { cells.filter { !$0.isNeutral }.count }

    public func sample(_ tripID: String) -> HeatSample? { samples[tripID] }

    public func cell(_ id: HeatCellID) -> HeatCell? {
        // Cells are sorted by id: a binary search, the tap handler asks once per tap.
        var low = 0, high = cells.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if cells[mid].id == id { return cells[mid] }
            if cells[mid].id < id { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }

    /// The trains of a cell, the latest first: largest delay, then cancelled ones, then those without realtime data.
    public func samples(in cell: HeatCell) -> [HeatSample] {
        cell.tripIDs.compactMap { samples[$0] }.sorted { a, b in
            let rankA = Self.order(a), rankB = Self.order(b)
            if rankA != rankB { return rankA > rankB }
            return a.tripID < b.tripID
        }
    }

    private static func order(_ sample: HeatSample) -> Double {
        if let delay = sample.delaySeconds { return 1_000_000 + Double(delay) }
        return sample.isCancelled ? 500_000 : 0
    }
}

public enum RadarHeat {
    /// A cell needs this many trains with a delay before it gets a colour (and a median).
    public static let minimumSample = 3
    /// 5 minutes: the radar's own "verspätet" limit.
    public static let lateThresholdSeconds = RadarDelay.lateThresholdSeconds
    /// 15 minutes: above this a train is "über 15 Min".
    public static let severeThresholdSeconds = 900
    public static let topDelayCount = 5
    public static let hotspotCount = 3
    /// Hot spots are further apart than this many steps of the grid.
    public static let hotspotSeparation = 2

    // MARK: Classes

    public static func bucket(delaySeconds: Int?, isCancelled: Bool) -> HeatBucket {
        if isCancelled { return .cancelled }
        guard let delaySeconds else { return .noRealtime }
        if delaySeconds < lateThresholdSeconds { return .onTime }
        return delaySeconds <= severeThresholdSeconds ? .delayed : .severe
    }

    /// The same classes for a median (a cell): under 5 minutes, up to 15, above.
    public static func bucket(medianSeconds: Double) -> HeatBucket {
        if medianSeconds < Double(lateThresholdSeconds) { return .onTime }
        return medianSeconds <= Double(severeThresholdSeconds) ? .delayed : .severe
    }

    /// The median; the mean of the two middle values for an even count. nil for no values.
    public static func median(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return Double(sorted[middle]) }
        return (Double(sorted[middle - 1]) + Double(sorted[middle])) / 2
    }

    // MARK: Aggregation

    /// Cells, national numbers, top delays and hot spots from the trains of one moment. A train that appears twice (same trip id)
    /// counts once, the first of the two in the input (the radar's store holds each trip once, so this is a safety net); a train with a
    /// position that is not on the globe (non-finite, beyond ±90° / ±180°) is left out.
    public static func snapshot(_ input: [HeatSample]) -> HeatSnapshot {
        var byID: [String: HeatSample] = [:]
        for sample in input where HeatGrid.isValid(sample.coordinate) {
            if byID[sample.tripID] == nil { byID[sample.tripID] = sample }
        }
        guard !byID.isEmpty else { return .empty }

        var summary = HeatSummary()
        var lateSeconds = 0
        var groups: [HeatCellID: [HeatSample]] = [:]
        for sample in byID.values {
            groups[HeatGrid.cell(containing: sample.coordinate), default: []].append(sample)
            summary.total += 1
            switch sample.bucket {
            case .onTime: summary.onTime += 1
            case .delayed: summary.delayed += 1
            case .severe: summary.severe += 1
            case .cancelled: summary.cancelled += 1
            case .noRealtime: summary.noRealtime += 1
            }
            if let delay = sample.delaySeconds, delay >= lateThresholdSeconds { lateSeconds += delay }
        }
        if summary.late > 0 { summary.averageLateSeconds = Double(lateSeconds) / Double(summary.late) }

        let cells = groups.keys.sorted().map { id in makeCell(id, groups[id] ?? []) }
        let top = byID.values
            .filter { ($0.delaySeconds ?? 0) >= lateThresholdSeconds }
            .sorted { a, b in
                let da = a.delaySeconds ?? 0, db = b.delaySeconds ?? 0
                return da != db ? da > db : a.tripID < b.tripID
            }
            .prefix(topDelayCount)
        return HeatSnapshot(cells: cells, summary: summary, topDelays: Array(top), hotspots: hotspots(in: cells), samples: byID)
    }

    private static func makeCell(_ id: HeatCellID, _ unsorted: [HeatSample]) -> HeatCell {
        let members = unsorted.sorted { $0.tripID < $1.tripID }
        let delays = members.compactMap(\.delaySeconds)
        let enough = delays.count >= minimumSample
        var names: [String: Int] = [:]
        for name in members.compactMap(\.nextStopName) where !name.isEmpty { names[name, default: 0] += 1 }
        let place = names.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
        return HeatCell(
            id: id, center: HeatGrid.center(of: id), tripIDs: members.map(\.tripID).sorted(),
            sampleCount: delays.count, cancelledCount: members.filter(\.isCancelled).count,
            noRealtimeCount: members.filter { $0.bucket == .noRealtime }.count,
            lateCount: delays.filter { $0 >= lateThresholdSeconds }.count,
            medianDelaySeconds: enough ? median(delays) : nil,
            // Whole seconds first, minutes once: the sum is exact, so ties in the ranking are real ties.
            delaySumMinutes: Double(delays.reduce(0) { $0 + max($1, 0) }) / 60, placeName: place)
    }

    /// The `hotspotCount` cells with the largest sum of delay minutes, among the cells that have a colour and whose median is 5
    /// minutes or more (a place where trains are late, not just a place with many trains). A cell within two steps of a better one
    /// (about 27 km) is skipped: three hot spots are three places, not one corridor counted three times, and on the country view their
    /// numbers on the map do not sit on top of each other.
    static func hotspots(in cells: [HeatCell]) -> [HeatHotspot] {
        let ranked = cells
            .filter { ($0.medianDelaySeconds ?? 0) >= Double(lateThresholdSeconds) }
            .sorted { a, b in
                if a.delaySumMinutes != b.delaySumMinutes { return a.delaySumMinutes > b.delaySumMinutes }
                if a.sampleCount != b.sampleCount { return a.sampleCount > b.sampleCount }
                return a.id < b.id
            }
        var chosen: [HeatCell] = []
        for cell in ranked where chosen.count < hotspotCount {
            if chosen.contains(where: { HeatGrid.distance($0.id, cell.id) <= hotspotSeparation }) { continue }
            chosen.append(cell)
        }
        return chosen.enumerated().map { index, cell in
            HeatHotspot(rank: index + 1, cellID: cell.id, center: cell.center, placeName: cell.placeName, sampleCount: cell.sampleCount,
                        lateCount: cell.lateCount, medianDelaySeconds: cell.medianDelaySeconds ?? 0, delaySumMinutes: cell.delaySumMinutes)
        }
    }

    // MARK: Taps

    /// The cell a tap belongs to: the cell under the point if it has trains, else the nearest cell centre within `toleranceKm`
    /// (cells are only a few points wide on a country view; a finger is not). nil when nothing is near.
    public static func cell(at point: GeoPoint, in snapshot: HeatSnapshot, toleranceKm: Double) -> HeatCell? {
        if let hit = snapshot.cell(HeatGrid.cell(containing: point)) { return hit }
        guard toleranceKm > 0, toleranceKm.isFinite else { return nil }
        var best: (cell: HeatCell, distance: Double)?
        for cell in snapshot.cells {
            let distance = HeatGrid.distanceKm(point, cell.center)
            guard distance <= toleranceKm else { continue }
            if let current = best, current.distance < distance || (current.distance == distance && current.cell.id < cell.id) { continue }
            best = (cell, distance)
        }
        return best?.cell
    }
}
