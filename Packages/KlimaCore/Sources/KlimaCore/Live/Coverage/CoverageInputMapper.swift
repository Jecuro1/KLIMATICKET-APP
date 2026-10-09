import Foundation

/// `Leg` / `Journey` → `CoverageLegInput` (SPEC §C2.2). Federal states come from the nearest `StationIndex` station
/// within 2 km (with an attached place index every Austrian stop counts), countries from HAFAS `countryCodeL`.
public enum CoverageInputMapper {
    /// One input per `journey.legs` element (walks and transfers included; the engine marks them `notApplicable`).
    public static func inputs(for journey: Journey, stations: StationIndex) -> [CoverageLegInput] {
        journey.legs.map { CoverageLegInput(leg: $0, stations: stations) }
    }

    /// `country = countryCode?.uppercased()`; `state` = nearest station within 2 km; a missing country is derived from
    /// the state ("AT" for an Austrian state, "XX" for a foreign station, state "X").
    public static func stop(_ location: Location, stations: StationIndex) -> CoverageLegInput.Stop {
        let lat = location.coordinate?.latitude, lon = location.coordinate?.longitude
        var state: String?
        if let p = location.coordinate, let hit = stations.nearest(to: p, limit: 1, maxKm: 2).first, hit.distanceKm < 2 {
            state = hit.station.state
        }
        var country = location.countryCode?.uppercased().nilIfEmpty
        if country == nil, let state {
            if CoverageEvaluator.austrianStates.contains(state) { country = "AT" } else if state == "X" { country = "XX" }
        }
        return CoverageLegInput.Stop(name: location.name, lat: lat, lon: lon, country: country, state: state)
    }

    static func legType(_ kind: Leg.Kind) -> String {
        switch kind {
        case .ride: return "JNY"
        case .walk: return "WALK"
        case .transfer: return "TRSF"
        }
    }
}

extension CoverageLegInput {
    /// Maps a live leg (SPEC §C2.2): line facts from `Leg.line`, remark texts of every kind, from/to/pass list stops.
    public init(leg: Leg, stations: StationIndex) {
        let line = leg.line
        self.init(legType: CoverageInputMapper.legType(leg.kind),
                  operator: line?.operatorName,
                  productName: line?.fullName ?? line?.name,
                  category: line?.category,
                  categoryLong: line?.categoryLong,
                  cls: line?.productClass,
                  clsScheme: "oebb-mgate",
                  admin: line?.admin,
                  lineId: line?.lineId,
                  line: line?.lineNumber,
                  remarks: leg.remarks.map(\.text),
                  from: CoverageInputMapper.stop(leg.origin, stations: stations),
                  to: CoverageInputMapper.stop(leg.destination, stations: stations),
                  passList: leg.intermediateStops.map { CoverageInputMapper.stop($0.location, stations: stations) })
    }
}
