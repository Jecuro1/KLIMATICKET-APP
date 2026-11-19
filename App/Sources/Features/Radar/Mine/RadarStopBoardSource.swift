import Foundation
import KlimaCore

// MARK: radar2-radarmine – where „Wo bleibt mein Bus?“ gets its departures (docs/RADAR_MINE.md §4). Called only from the radar's side job
// (`RadarMineModel.run`, one slot of the radar's 24 a minute each): the station link (one LocMatch the first time a stop is linked; none for `uic:`
// stations; the linker keeps it on disk for 30 days) and the StationBoard (30 minutes, at most 12 entries, Züge, S-Bahn, Bus, Bim and U-Bahn
// whatever the chips say). Both go through `LiveDataService` – nil without consent, with the Fahrplan off, under the kill switch, offline or in the
// Offline-Modus – and the shared HAFAS client with its `RequestThrottle`. Demo and screenshot launches get a synthetic board (`RadarMineDemo`), no
// network.

@MainActor
struct RadarStopBoardSource {
    enum SourceError: Error { case noLiveData }

    let live: LiveDataService
    /// Demo data or a screenshot launch: the synthetic board, never the network.
    var isDemo: Bool { live.isDemo || LaunchMode.isSandboxed }

    /// The stop needs a station lookup of its own (its own slot): not for `uic:` stations, not in the demo.
    func needsLink(_ station: Station) -> Bool {
        !isDemo && !station.id.hasPrefix("uic:")
    }

    func link(_ station: Station) async throws -> Location {
        if isDemo { return PlannerModel.demoLocation(station) }
        guard live.timetable != nil else { throw SourceError.noLiveData }
        return try await live.linker.hafasLocation(for: station)
    }

    func board(at location: Location, station: Station, now: Date) async throws -> Board {
        if isDemo { return RadarMineDemo.board(for: station, now: now) }
        guard let timetable = live.timetable else { throw SourceError.noLiveData }
        return try await timetable.board(RadarStopArrivals.query(station: location, at: now))
    }

    /// The board refused a stored link: the linker forgets it.
    func forget(_ station: Station) async {
        guard !isDemo else { return }
        await live.linker.invalidate(stationID: station.id)
    }
}
