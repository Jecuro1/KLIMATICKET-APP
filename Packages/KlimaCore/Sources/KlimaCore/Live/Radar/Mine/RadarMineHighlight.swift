import Foundation

// MARK: radar2-radarmine – „Nur meine Linien hervorheben“ (docs/RADAR_MINE.md §2): the vehicles of your lines get a star and stay single markers, the
// others step back. Twenty remembered bus lines in Wien can be several hundred vehicles; as single markers they would cover the map and cost MapKit
// what the radar's 250-marker rule forbids. So at most 60 stay single, nearest the map's centre first; the rest group as usual.

public enum RadarMineHighlight {
    public static let singleCap = 60

    public struct Candidate: Sendable, Hashable {
        public var tripID: String
        public var coordinate: GeoPoint

        public init(tripID: String, coordinate: GeoPoint) {
            self.tripID = tripID
            self.coordinate = coordinate
        }
    }

    /// The highlighted vehicles that stay single: all of them up to the cap, else the `cap` nearest `centre` (ties by trip id).
    public static func singles(_ candidates: [Candidate], centre: GeoPoint, cap: Int = singleCap) -> Set<String> {
        guard candidates.count > cap else { return Set(candidates.map(\.tripID)) }
        // Plain degrees with the longitude shrunk to Austria's latitude: an order, not a distance.
        func distance(_ c: Candidate) -> Double {
            let dLat = c.coordinate.latitude - centre.latitude
            let dLon = (c.coordinate.longitude - centre.longitude) * 0.67
            let d = dLat * dLat + dLon * dLon
            return d.isFinite ? d : .infinity
        }
        let ranked = candidates.map { ($0.tripID, distance($0)) }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        return Set(ranked.prefix(max(cap, 0)).map(\.0))
    }
}
