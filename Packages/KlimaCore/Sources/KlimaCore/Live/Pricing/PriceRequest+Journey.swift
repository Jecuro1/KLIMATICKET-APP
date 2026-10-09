import Foundation

extension PriceEndpoint {
    /// From a planner location: app station id via `StationLinker.appStation(for:in:)` (nil when none within 300 m with
    /// a compatible name), HAFAS extId, coordinate and name.
    public init(location: Location, stations: StationIndex?) {
        self.init(stationID: stations.flatMap { StationLinker.appStation(for: location, in: $0)?.id }, name: location.name,
                  coordinate: location.coordinate, hafasExtId: location.extId?.nilIfEmpty)
    }
}

extension PriceRequest {
    /// From/to = first/last ride leg origin/destination (stationID via StationLinker.appStation(for:in:), hafasExtId, coordinate);
    /// departure = planned departure of the first ride leg; mode = mode of the longest ride leg; journey = journey.
    public init(journey: Journey, travelClass: TravelClass, discount: FareDiscount, stations: StationIndex) {
        self.init(journey: journey, travelClass: travelClass, discount: discount, stations: stations, via: [])
    }

    /// Same, with the planner's via stops (`JourneyQuery.via`, owner request 2026-10-09) so the price follows the via
    /// route (see `LivePriceService`).
    public init(journey: Journey, travelClass: TravelClass, discount: FareDiscount, stations: StationIndex, via: [ViaStop]) {
        let rides = journey.rideLegs
        let first = rides.first ?? journey.legs.first
        let last = rides.last ?? journey.legs.last
        let origin = first?.origin ?? Location(lid: "", name: "Start")
        let destination = last?.destination ?? Location(lid: "", name: "Ziel")
        let departure = first?.departure.planned ?? first?.departure.effective ?? journey.departure?.planned
            ?? Date(timeIntervalSince1970: 0)
        let longest = rides.max { a, b in Self.seconds(a) < Self.seconds(b) }
        self.init(from: PriceEndpoint(location: origin, stations: stations),
                  to: PriceEndpoint(location: destination, stations: stations),
                  departure: departure, mode: longest?.line?.mode ?? .train, travelClass: travelClass, discount: discount,
                  journey: journey, via: via.prefix(JourneyQuery.maxViaStops).map { PriceEndpoint(location: $0.location, stations: stations) })
    }

    /// Planned ride time of a leg in seconds (0 when unknown).
    private static func seconds(_ leg: Leg) -> TimeInterval {
        guard let a = leg.departure.planned ?? leg.departure.effective, let b = leg.arrival.planned ?? leg.arrival.effective else { return 0 }
        return b.timeIntervalSince(a)
    }
}
