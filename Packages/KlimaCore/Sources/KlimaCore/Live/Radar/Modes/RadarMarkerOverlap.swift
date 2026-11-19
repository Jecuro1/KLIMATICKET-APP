import Foundation

// MARK: radar2-fix-radarmodes – markers that would cover each other across a cell border (docs/RADAR_MODES.md §5). `RadarClustering.group` folds the
// vehicles of one grid cell into one marker, and a cell is about one marker wide, so two markers of one cell never overlap. Two vehicles on either side
// of a border did: each was the only one of its cell, and their plates lay on top of each other (CI screenshot radarTrails: S45 under REX 92 at Wien).
// This pass works on the grid's markers in screen units (one cell = one marker pitch, Mercator like the map):
// - two markers that would overlap become one group (their vehicles, their counts, the mean of their points), until none overlaps;
// - a kept marker (the selected and the followed vehicle, a part's remembered line: `RadarModel`) is never folded; a single marker that would lie under
//   its plate is drawn as a dot (`compact`), so the kept plate stays readable and the other vehicle stays on the map, at its point, tappable.
// Nothing leaves the map and nothing moves: the vehicles and their count are the same before and after.

public enum RadarMarkerOverlap {
    public struct Result: Equatable, Sendable {
        public var clusters: [RadarCluster]
        /// Trip ids of single markers drawn as a dot: they lie under a kept marker's plate.
        public var compact: Set<String>

        public init(clusters: [RadarCluster], compact: Set<String>) {
            self.clusters = clusters
            self.compact = compact
        }
    }

    /// How far two marker points must be apart, in cells, for their markers not to touch: a plate with its arrow is about 0.8 of a pitch wide
    /// (REX 92 is 46 pt at the normal pitch of 56) and half a pitch tall; a group bubble is 34 pt round.
    public static let reachX = 0.8
    public static let reachY = 0.5

    /// The grid's markers with the overlaps resolved. `kept`: trip ids that stay single markers. Unchanged without a valid cell size.
    public static func resolve(_ clusters: [RadarCluster], cellDegrees: Double, kept: Set<String> = []) -> Result {
        guard cellDegrees > 0, cellDegrees.isFinite, clusters.count > 1 else { return Result(clusters: clusters, compact: []) }
        func isKept(_ cluster: RadarCluster) -> Bool { cluster.isSingle && kept.contains(cluster.tripIDs[0]) }
        let fixed = clusters.filter(isKept)
        var free = clusters.filter { !isKept($0) }

        // A new group sits between its members and can reach a third marker: passes until one merges nothing, so no two markers overlap. Each pass
        // that merges has fewer markers, so this ends; one or two passes are usual for the 150 cells the grid allows.
        while true {
            let merged = mergePass(free, cellDegrees: cellDegrees)
            guard merged.count < free.count else { break }
            free = merged
        }

        var compact: Set<String> = []
        if !fixed.isEmpty {
            let anchors = fixed.map { screen($0.center, cellDegrees) }
            for cluster in free where cluster.isSingle {
                let at = screen(cluster.center, cellDegrees)
                if anchors.contains(where: { abs($0.x - at.x) < reachX && abs($0.y - at.y) < reachY }) {
                    compact.insert(cluster.tripIDs[0])
                }
            }
        }
        return Result(clusters: (fixed + free).sorted { $0.id < $1.id }, compact: compact)
    }

    /// A point in cells: x the longitude, y the Mercator height in longitude degrees (as the map draws it), both divided by the cell.
    static func screen(_ point: GeoPoint, _ cellDegrees: Double) -> (x: Double, y: Double) {
        let latitude = min(max(point.latitude, -85), 85) * .pi / 180
        let mercator = log(tan(.pi / 4 + latitude / 2)) * 180 / .pi
        return (point.longitude / cellDegrees, mercator / cellDegrees)
    }

    /// One sweep from west to east: each marker takes the markers east of it that it would touch. Deterministic for any input order.
    private static func mergePass(_ clusters: [RadarCluster], cellDegrees: Double) -> [RadarCluster] {
        let sorted = clusters.map { (cluster: $0, at: screen($0.center, cellDegrees)) }
            .sorted { $0.at.x != $1.at.x ? $0.at.x < $1.at.x : $0.cluster.id < $1.cluster.id }
        var used = [Bool](repeating: false, count: sorted.count)
        var result: [RadarCluster] = []
        for i in sorted.indices where !used[i] {
            used[i] = true
            var members = [sorted[i].cluster]
            var j = i + 1
            while j < sorted.count, sorted[j].at.x - sorted[i].at.x < reachX {
                if !used[j], abs(sorted[j].at.y - sorted[i].at.y) < reachY {
                    used[j] = true
                    members.append(sorted[j].cluster)
                }
                j += 1
            }
            result.append(members.count == 1 ? members[0] : combine(members))
        }
        return result
    }

    /// One group of several markers: every vehicle once, the point weighted by the vehicles, the late and cancelled counts added. Its id is the
    /// grid key of its largest group (ties: the smaller key), or „near|“ and its first trip id when it was only single markers: unique, since every
    /// vehicle is in one marker, and the same for the same markers.
    private static func combine(_ members: [RadarCluster]) -> RadarCluster {
        let count = Double(members.reduce(0) { $0 + $1.count })
        let latitude = members.reduce(0.0) { $0 + $1.center.latitude * Double($1.count) } / count
        let longitude = members.reduce(0.0) { $0 + $1.center.longitude * Double($1.count) } / count
        let trips = members.flatMap(\.tripIDs).sorted()
        let largestGroup = members.filter { !$0.isSingle }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }.first
        return RadarCluster(id: largestGroup?.id ?? "near|\(trips[0])",
                            center: GeoPoint(latitude: latitude, longitude: longitude),
                            tripIDs: trips,
                            lateCount: members.reduce(0) { $0 + $1.lateCount },
                            cancelledCount: members.reduce(0) { $0 + $1.cancelledCount })
    }
}
