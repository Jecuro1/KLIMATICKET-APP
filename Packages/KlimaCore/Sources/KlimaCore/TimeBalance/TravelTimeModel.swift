import Foundation

/// Rough ride time of a trip nobody timed: an average speed per mode that grows with the distance (longer trips use
/// faster lines and stop less often), stops included, the way to the stop and waiting excluded. Always an estimate –
/// the app labels every minute from here as „geschätzt“ (docs/TIME_BALANCE.md §3).
///
/// The speed is interpolated linearly between documented anchor points (below the first anchor its speed, beyond the
/// last one its speed). Every segment is checked by `isMonotonic`: the ride time never gets shorter when the distance
/// grows, so one more kilometre never saves time.
public struct TravelTimeModel: Hashable, Sendable {
    /// Average speed (km/h, stops included) of a ride of `km` kilometres.
    public struct Anchor: Hashable, Sendable {
        public var km: Double
        public var kmh: Double

        public init(km: Double, kmh: Double) {
            self.km = km
            self.kmh = kmh
        }
    }

    /// Anchors per mode, ascending in km.
    public var anchors: [TransportMode: [Anchor]]
    /// Shortest ride (minutes): a trip without a distance still took the time to board and ride one stop.
    public var minimumMinutes: Double

    public init(anchors: [TransportMode: [Anchor]], minimumMinutes: Double) {
        self.anchors = anchors
        self.minimumMinutes = minimumMinutes
    }

    /// The model the app uses. Rough Austrian averages, stops included (checked against typical timetables, not exact):
    /// - Zug: 5 km 30 km/h (Regionalzug mit vielen Halten) · 20 km 50 · 60 km 70 · 150 km 95 · ab 300 km 125 (Railjet/Westbahn)
    /// - S-Bahn: 5 km 28 · 15 km 36 · 40 km 48 · ab 80 km 55
    /// - U-Bahn: 2 km 25 · ab 10 km 32
    /// - Bim: 2 km 14 · ab 10 km 17
    /// - Bus (and „Sonstiges“): 3 km 18 (Stadtbus) · 15 km 28 · 40 km 40 · ab 100 km 50 (Regionalbus, Fernbus)
    /// - Schiff 15 · Seilbahn 15 (Gondel und Standseilbahn)
    /// - at least 2 minutes per ride
    public static let standard: TravelTimeModel = {
        let bus = [Anchor(km: 3, kmh: 18), Anchor(km: 15, kmh: 28), Anchor(km: 40, kmh: 40), Anchor(km: 100, kmh: 50)]
        return TravelTimeModel(anchors: [
            .train: [Anchor(km: 5, kmh: 30), Anchor(km: 20, kmh: 50), Anchor(km: 60, kmh: 70), Anchor(km: 150, kmh: 95),
                     Anchor(km: 300, kmh: 125)],
            .sBahn: [Anchor(km: 5, kmh: 28), Anchor(km: 15, kmh: 36), Anchor(km: 40, kmh: 48), Anchor(km: 80, kmh: 55)],
            .metro: [Anchor(km: 2, kmh: 25), Anchor(km: 10, kmh: 32)],
            .tram: [Anchor(km: 2, kmh: 14), Anchor(km: 10, kmh: 17)],
            .bus: bus,
            .ferry: [Anchor(km: 5, kmh: 15)],
            .cableCar: [Anchor(km: 2, kmh: 15)],
            .other: bus,
        ], minimumMinutes: 2)
    }()

    /// Average speed (km/h) of a ride of `km` kilometres with `mode`.
    public func averageSpeedKmh(_ mode: TransportMode, km: Double) -> Double {
        let points = anchors[mode] ?? anchors[.other] ?? []
        guard let first = points.first, let last = points.last else { return 30 }
        guard km > first.km else { return first.kmh }
        guard km < last.km else { return last.kmh }
        for (lower, upper) in zip(points, points.dropFirst()) where km <= upper.km {
            let t = (km - lower.km) / max(upper.km - lower.km, .ulpOfOne)
            return lower.kmh + (upper.kmh - lower.kmh) * t
        }
        return last.kmh
    }

    /// Estimated minutes of ONE ride (one direction, one leg) of `km` kilometres.
    public func minutes(_ mode: TransportMode, km: Double) -> Double {
        let distance = km.isFinite ? max(0, km) : 0
        guard distance > 0 else { return minimumMinutes }
        return max(minimumMinutes, distance / averageSpeedKmh(mode, km: distance) * 60)
    }

    /// Estimated minutes of a trip entry: every ride counts, a round trip twice.
    public func minutes(of trip: TimeTripInput) -> Double {
        minutes(trip.mode, km: trip.distanceKm) * Double(trip.legs)
    }

    /// True when the time km ÷ speed(km) never falls as km grows. Linear speed between two anchors keeps that exactly
    /// when the line through them meets km = 0 at a positive speed (speed − slope × km > 0 at the lower anchor), and the
    /// anchors rise in km.
    public var isMonotonic: Bool {
        anchors.values.allSatisfy { points in
            zip(points, points.dropFirst()).allSatisfy { lower, upper in
                guard upper.km > lower.km, lower.kmh > 0, upper.kmh > 0 else { return false }
                let slope = (upper.kmh - lower.kmh) / (upper.km - lower.km)
                return lower.kmh - slope * lower.km > 0
            }
        }
    }
}
