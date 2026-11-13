import Foundation
import KlimaCore

// MARK: commute – „Nächste Abfahrten“ in the stop detail (docs/COMMUTE.md §12): one departure board (HAFAS StationBoard) for the
// stop's station. `StopBoardDepartures.load` refuses before any I/O when `LiveDataService.timetable` is nil (no consent, Fahrplan
// switched off, kill switch, offline); the linker – and with it the live client stack – is only touched after that gate. The
// request shares the app-wide `RequestThrottle` (40 requests per minute, 0,3 s apart). Demo runs use the demo timetable.

@MainActor
struct LiveStopDepartureProvider {
    let live: LiveDataService

    func departures(for station: Station, at date: Date = Date()) async throws -> StopBoardSnapshot {
        let timetable = live.timetable
        guard timetable != nil else { throw CommuteLiveError.consentRequired }
        if live.isDemo {
            let location = PlannerModel.demoLocation(station)
            return try await StopBoardDepartures.load(timetable: timetable, at: date) { location }
        }
        let linker = live.linker
        do {
            return try await StopBoardDepartures.load(timetable: timetable, at: date) { try await linker.hafasLocation(for: station) }
        } catch LiveError.hafas(code: "LOCATION", _) {
            await linker.invalidate(stationID: station.id)
            throw LiveError.noConnection
        }
    }
}
