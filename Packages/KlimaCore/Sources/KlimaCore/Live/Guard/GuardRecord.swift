import Foundation

// Anschluss-Wächter, what survives a relaunch (docs/CONNECTION_GUARD.md §7): one record, version 1, with a slim copy of the
// watched journey (legs without stopovers, polylines and remarks; the Reconstruction handle). The app keeps it as
// `Guard/record.json` in Application Support, excluded from backup – it is your itinerary to the final destination – and
// drops it when the follow stops or is replaced, when the guard ends, or after 12 hours. Buffer samples and states stay in
// memory only.

public struct GuardRecord: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public var version: Int
    /// The follow this guard belongs to (the feeder's trip id).
    public var followTripID: String
    /// The watched connection, slim (`GuardRecord.slim`).
    public var journey: Journey
    /// When `journey` was asked for.
    public var journeyAt: Date
    /// Ride index of the feeder (0: the followed first ride); the watched change is the one after it.
    public var feederRide: Int
    /// The planner's products at registration (alternatives are searched with them).
    public var products: ProductMask
    /// „Nur mit KlimaTicket gültig“ was on at registration (said in the alternatives' footer).
    public var klimaTicketOnly: Bool
    public var createdAt: Date
    /// „Wächter aus“ for this follow.
    public var switchedOff: Bool

    public init(followTripID: String, journey: Journey, journeyAt: Date, feederRide: Int = 0, products: ProductMask,
                klimaTicketOnly: Bool, createdAt: Date, switchedOff: Bool = false) {
        self.version = Self.currentVersion
        self.followTripID = followTripID
        self.journey = Self.slim(journey)
        self.journeyAt = journeyAt
        self.feederRide = feederRide
        self.products = products
        self.klimaTicketOnly = klimaTicketOnly
        self.createdAt = createdAt
        self.switchedOff = switchedOff
    }

    /// The journey without what the guard never reads: stopovers, polylines, remarks, positions and the shop link.
    public static func slim(_ journey: Journey) -> Journey {
        var copy = journey
        copy.remarks = []
        copy.shopURL = nil
        copy.legs = journey.legs.map { leg in
            var l = leg
            l.stopovers = []
            l.polyline = nil
            l.remarks = []
            l.currentPosition = nil
            return l
        }
        return copy
    }

    /// The record with a newer answer of the connection.
    public func updated(journey: Journey, at: Date) -> GuardRecord {
        var copy = self
        copy.journey = Self.slim(journey)
        copy.journeyAt = at
        return copy
    }

    /// Older than 12 hours.
    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(createdAt) > GuardPlan.recordLifetime
    }

    /// The feeder's arrival station (lid, then extId, then name) is the follow target's change station.
    func isTransferStation(_ target: LiveFollowTarget) -> Bool {
        guard let (a, _) = ConnectionGuard.legIndices(journey, feederRide: feederRide) else { return false }
        let station = journey.legs[a].destination
        if station.lid == target.alightStop.lid { return true }
        if let ext = station.extId, ext == target.alightStop.extId { return true }
        return DisplayNames.name(station.name) == DisplayNames.name(target.transfer?.stationName ?? target.alightStop.name)
    }

    /// The record still belongs to a follow that (re)starts with `target`: same trip, with a change at the same station.
    /// A radar or train-search follow of the same trip has no change and ends the guard.
    public func belongs(to target: LiveFollowTarget) -> Bool {
        target.tripID == followTripID && target.transfer != nil && isTransferStation(target)
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// nil for garbage, a missing field or another version.
    public static func decode(_ data: Data) -> GuardRecord? {
        struct Probe: Decodable { var version: Int }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data), probe.version == currentVersion else { return nil }
        return try? JSONDecoder().decode(GuardRecord.self, from: data)
    }
}
