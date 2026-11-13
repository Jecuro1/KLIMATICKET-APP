import Foundation
import KlimaCore

// MARK: radarmodes – the synthetic city fleets (KlimaCore `RadarCityDemoFleet`, docs/RADAR_MODES.md §10) as a radar service: no network, no real
// vehicle. The city CI scenes use it with the demo-only fast budget; -KBDemo gets the same fleets through `DemoRadarService`.

/// The radar service of the city CI scenes: the synthetic city fleets and the corridor trains of the demo, answered like the real service.
struct RadarCityDemoService: RadarService {
    var crowded = false

    func radar(_ query: RadarQuery) async throws -> RadarSnapshot {
        RadarCityDemoFleet.answer(query, crowded: crowded, extra: DemoScotty.vehicles(now: query.when))
    }
}
