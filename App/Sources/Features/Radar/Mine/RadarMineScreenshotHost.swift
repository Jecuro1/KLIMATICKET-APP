import SwiftUI
import KlimaCore

// MARK: radar2-radarmine – CI screenshot scenes of „Meine Fahrzeuge“ (docs/RADAR_MINE.md §10): radarmodes' synthetic city fleets with the demo-only fast
// budget, the invented stop and place of `RadarMineDemo`, no network, no permission prompt (the location is never asked in a screenshot launch). The
// scene is set before the radar is built, so its model starts with the scene's lines, page and stop.

/// Whether the entry points (the chip „Meine“, „Linie merken“) are shown. Screenshot launches always; everyone else once the screens behind them were
/// looked at in the CI screenshots (docs/RADAR_MINE.md §11).
enum RadarMineEntry {
    static var isShown: Bool { LaunchMode.isSandboxed || isReleased }
    static let isReleased = false
}

struct RadarMineScreenshotHost: View {
    static let screens = Set(RadarMineScene.allCases.map(\.rawValue))

    let screen: String

    init(screen: String) {
        self.screen = screen
        RadarMineDemo.scene = RadarMineScene(rawValue: screen)
    }

    private var scene: RadarMineScene { RadarMineScene(rawValue: screen) ?? .lines }

    var body: some View {
        switch scene {
        case .tripSheet:
            RadarMineTripSheetShot()
        case .ax5, .linesAX5:
            RadarView(preset: .modesCity).dynamicTypeSize(.accessibility5)
        default:
            RadarView(preset: .modesCity)
        }
    }
}

/// The trip sheet of a Bus 13A of the city demo, its line remembered.
private struct RadarMineTripSheetShot: View {
    @State private var parts = Radar2Parts()
    private let vehicle: RadarVehicle

    init() {
        let now = Date()
        let fleet = RadarCityDemoFleet.vehicles(now: now)
        vehicle = fleet.first { $0.line?.lineNumber == "13A" && !$0.isCancelled } ?? fleet[0]
        // Its own synthetic stops in the sheet's cache before it asks (the demo timetable answers every trip with one sample train run).
        RadarRouteCache.shared.store(TripDetails(tripID: vehicle.tripID, line: vehicle.line, direction: vehicle.direction, stopovers: vehicle.stopovers),
                                     now: now)
    }

    var body: some View {
        RadarTripSheet(vehicle: vehicle, radar2: parts)
    }
}
