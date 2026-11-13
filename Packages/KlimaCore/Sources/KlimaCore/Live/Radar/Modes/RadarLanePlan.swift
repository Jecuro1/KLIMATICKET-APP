import Foundation

// MARK: radarmodes – the two request lanes of the radar (docs/RADAR_MODES.md §3): which products each lane asks for, when the city lane runs, how
// fine it starts and splits, how many of its tiles a view may have and how often they are asked. Pure values; the scheduler and the model read them.

public enum RadarLanePlan {
    /// The city lane asks only while the map is at most this tall (degrees of latitude, about 67 km). Above it a country view of buses would
    /// split into hundreds of tiles and minutes per round. The live measurement of 2026-11-13 (docs/RADAR_MODES.md §8) gave no reason to move it.
    public static let citySpanLimit = 0.6
    /// The city lane starts this many levels finer than the wide lane would for the same view (a Wien view of 0.12°: level 5, 9.7 × 9 km).
    public static let cityLevelOffset = 1
    /// At most this many city tiles in one view. A split that would need more leaves its tile as it is („crowded“, said in the status).
    public static let cityMaxTiles = 16
    /// City refresh: every 20 s on Wi-Fi, every 60 s on a metered or constrained path („Automatisch“).
    public static let cityIntervalWiFi: TimeInterval = 20
    public static let cityIntervalMetered: TimeInterval = 60
    /// Kilometres per degree of latitude (the footer of the Verkehrsmittel section says the limit in km).
    public static let kmPerDegreeLatitude = 111.2

    /// The lane that asks for a mode: Züge and S-Bahn the wide lane, Bus, Bim and U-Bahn the city lane.
    public static func lane(of mode: RadarMode) -> RadarLane { mode.isCity ? .city : .wide }

    /// The products a lane asks for. The wide lane: the chosen Züge and S-Bahn, and while the Pünktlichkeit layer is on every train and S-Bahn
    /// (`.rail`, 4157) whatever the chips say (the layer's numbers must not depend on the chips; the pins still follow them). The city lane: the
    /// chosen Bus, Bim and U-Bahn. An empty mask: the lane asks for nothing.
    public static func products(for lane: RadarLane, selection: RadarModeSelection, heatOn: Bool) -> ProductMask {
        let chosen = selection.modes.filter { self.lane(of: $0) == lane }
            .reduce(into: ProductMask(rawValue: 0)) { $0.formUnion($1.products) }
        return lane == .wide && heatOn ? chosen.union(.rail) : chosen
    }

    /// Everything the radar asks for: both lanes. A vehicle whose class is outside it leaves the store at once when the modes change.
    public static func requestMask(selection: RadarModeSelection, heatOn: Bool) -> ProductMask {
        products(for: .wide, selection: selection, heatOn: heatOn).union(products(for: .city, selection: selection, heatOn: heatOn))
    }

    /// The city lane may ask for this view: a city mode is on, its markers are drawn (train layer on) and the map is close enough.
    public static func cityInZoom(latitudeSpan: Double, limit: Double = citySpanLimit) -> Bool {
        latitudeSpan.isFinite && latitudeSpan > 0 && latitudeSpan <= limit
    }

    /// The span limit in whole kilometres (0.6° → 67).
    public static func cityLimitKilometres(_ limit: Double = citySpanLimit) -> Int {
        Int((limit * kmPerDegreeLatitude).rounded())
    }

    /// The city refresh for „Automatisch“: 60 s on a metered path, else 20 s.
    public static func automaticCityInterval(metered: Bool) -> TimeInterval { metered ? cityIntervalMetered : cityIntervalWiFi }
}

public extension RadarSchedulerConfig {
    /// MARK: radarmodes – the CI scenes of the city demo only: a city view of 9 to 30 synthetic tiles is captured 11 s after launch, which the real
    /// budget (4 in 10 s) would show half loaded. Never with a real service: `forRadar` returns it only for the synthetic city demo in a sandboxed
    /// launch.
    static let syntheticCityDemo: RadarSchedulerConfig = {
        var config = RadarSchedulerConfig()
        config.perMinute = 600
        config.burst = 60
        config.minGap = 0
        config.settleDelay = 0
        return config
    }()

    /// The radar's scheduler config: `.standard` unless the synthetic city demo runs in a sandboxed (screenshot, perf) launch.
    static func forRadar(syntheticCityDemo: Bool, sandboxed: Bool) -> RadarSchedulerConfig {
        syntheticCityDemo && sandboxed ? .syntheticCityDemo : .standard
    }
}
