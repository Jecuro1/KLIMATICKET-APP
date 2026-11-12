import Foundation

/// "So weit wie von Bregenz nach Wien": a well-known Austrian distance to put the kilometres of the year in perspective.
///
/// The distance of a pair is never typed in: it is the great-circle distance (haversine, `GeoPoint.distanceKm`) between
/// the coordinates of the two bundled stations, so it is always consistent with the station list. A pair whose station
/// is missing (a station list that changed) is skipped.
public struct ReferenceComparison: Hashable, Sendable {
    public var fromLabel: String
    public var toLabel: String
    /// Great-circle km between the two stations.
    public var referenceKm: Double
    /// `km / referenceKm`: 9,0 = nine times from `fromLabel` to `toLabel`; below 1 = part of it.
    public var factor: Double

    public init(fromLabel: String, toLabel: String, referenceKm: Double, factor: Double) {
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.referenceKm = referenceKm
        self.factor = factor
    }
}

public enum ReferenceDistances {
    public struct Pair: Hashable, Sendable {
        public var fromID: String
        public var toID: String
        public var fromLabel: String
        public var toLabel: String

        public init(fromID: String, toID: String, fromLabel: String, toLabel: String) {
            self.fromID = fromID
            self.toID = toID
            self.fromLabel = fromLabel
            self.toLabel = toLabel
        }
    }

    // Station ids of the bundled stations.json (App/Resources); the KlimaCore tests resolve every one of them.
    private static let wien = "at:49:1349"          // Wien Hauptbahnhof
    private static let graz = "at:46:3040"          // Graz Hbf
    private static let linz = "at:44:41164"         // Linz Hbf
    private static let salzburg = "at:45:50002"     // Salzburg Hbf
    private static let villach = "at:42:3654"       // Villach Hbf
    private static let innsbruck = "at:47:1187"     // Innsbruck Hbf
    private static let bregenz = "at:48:452"        // Bregenz

    /// The pairs, short to long. Their distances come from the coordinates (`distanceKm`), never from this list.
    public static let pairs: [Pair] = [
        Pair(fromID: wien, toID: graz, fromLabel: "Wien", toLabel: "Graz"),
        Pair(fromID: wien, toID: linz, fromLabel: "Wien", toLabel: "Linz"),
        Pair(fromID: wien, toID: salzburg, fromLabel: "Wien", toLabel: "Salzburg"),
        Pair(fromID: wien, toID: villach, fromLabel: "Wien", toLabel: "Villach"),
        Pair(fromID: wien, toID: innsbruck, fromLabel: "Wien", toLabel: "Innsbruck"),
        Pair(fromID: bregenz, toID: wien, fromLabel: "Bregenz", toLabel: "Wien"),
    ]

    /// Great-circle distance of a pair in km; nil when one of its stations is unknown.
    public static func distanceKm(_ pair: Pair, stations: (String) -> Station?) -> Double? {
        guard let from = stations(pair.fromID), let to = stations(pair.toID) else { return nil }
        let km = from.location.distanceKm(to: to.location)
        return km.isFinite && km > 0 ? km : nil
    }

    /// The reference that fits `km` best: the longest pair that is not longer than `km` ("mehr als einmal"), and for a
    /// distance shorter than every pair the shortest one ("ein Drittel von Wien nach Graz"). nil for no distance or when
    /// no pair can be resolved.
    public static func compare(km: Double, stations: (String) -> Station?) -> ReferenceComparison? {
        guard km.isFinite, km > 0 else { return nil }
        let resolved = pairs.compactMap { pair -> (pair: Pair, km: Double)? in
            distanceKm(pair, stations: stations).map { (pair, $0) }
        }
        .sorted { $0.km < $1.km }
        guard let pick = resolved.last(where: { $0.km <= km }) ?? resolved.first else { return nil }
        return ReferenceComparison(fromLabel: pick.pair.fromLabel, toLabel: pick.pair.toLabel, referenceKm: pick.km,
                                   factor: km / pick.km)
    }
}
