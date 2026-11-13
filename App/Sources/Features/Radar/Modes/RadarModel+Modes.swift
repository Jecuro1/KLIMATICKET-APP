import SwiftUI
import KlimaCore

// MARK: radarmodes – the radar model's two request lanes (docs/RADAR_MODES.md §3): which products a tile asks for, when a lane starts over, the
// city lane's view and refresh, and which vehicles the map shows. The wide lane (Züge, S-Bahn, the Pünktlichkeit's Austria) is the radar as it
// always was; the city lane (Bus, Bim, U-Bahn) asks only while the map is zoomed in and the train layer is on.

extension RadarModel {
    /// The products a tile of this lane asks for: the chosen modes of its lane, and while the Pünktlichkeit layer is on every train and S-Bahn.
    func products(for tile: RadarTileKey) -> ProductMask {
        laneMasks[tile.lane] ?? RadarLanePlan.products(for: tile.lane, selection: modes, heatOn: heat.isEnabled)
    }

    /// A lane whose request mask changed (chips, the Pünktlichkeit layer) starts over: its tiles are forgotten and an answer still on its way for
    /// it is dropped; the other lane keeps everything. Vehicles that no lane asks for any more leave the store at once.
    func syncLanes() {
        var changed = false
        for lane in RadarLane.allCases {
            let mask = RadarLanePlan.products(for: lane, selection: modes, heatOn: heat.isEnabled)
            guard laneMasks[lane] != mask else { continue }
            laneMasks[lane] = mask
            laneGenerations[lane, default: 0] += 1
            scheduler.reset(lane: lane)
            changed = true
        }
        guard changed else { return }
        let asked = RadarLanePlan.requestMask(selection: modes, heatOn: heat.isEnabled)
        store.removeAll { vehicle in
            guard let line = vehicle.line, line.productClass != 0 else { return false }
            return line.productClass & asked.rawValue == 0
        }
    }

    /// The city lane's view: the map's rectangle while a city mode is on and the markers are drawn, else none. The scheduler asks only while
    /// the span is at most `RadarLanePlan.citySpanLimit`.
    func applyCityViewport(now: Date = Date()) {
        let wanted = markersOn && modes.hasCity
        scheduler.setCityViewport(wanted ? box : nil, latitudeSpan: spanDegrees, now: now)
    }

    /// The train layer went on or off: the city lane runs only while its markers are drawn (the Pünktlichkeit never needs buses).
    func setMarkersOn(_ on: Bool) {
        guard on != markersOn else { return }
        markersOn = on
        applyCityViewport()
        rebuildPinsNow()
    }

    /// „Automatisch“: every 20 s, every 60 s on a metered or constrained path, decided once when the loop starts (the Zeitreise's check).
    /// Screenshot and perf launches take Wi-Fi.
    func resolveCityInterval() async {
        let metered = LaunchMode.isSandboxed ? false : await RadarMeteredPath.isMetered()
        cityMetered = metered
        scheduler.setCityInterval(RadarLanePlan.automaticCityInterval(metered: metered))
    }

    /// The products the map draws: the chips' modes, without Bus, Bim and U-Bahn while the city lane is out of zoom or off (their vehicles
    /// leave the map at once; what the store holds stays until its retention ends).
    var shownProducts: ProductMask {
        scheduler.cityIsInZoom ? products : products.subtracting(RadarLanePlan.products(for: .city, selection: modes, heatOn: false))
    }

    /// The city modes are on, but the map is too far out for them.
    var cityOutOfZoom: Bool { status.city.outOfZoom }
}
