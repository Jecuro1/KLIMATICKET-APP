import Foundation
import KlimaCore
import KlimaCloud

// MARK: timebalance – the app's side of the „Zeitbilanz“ data (docs/TIME_BALANCE.md): entity → KlimaCore input, and the
// JSON backup's optional time keys. `TripRecord` and the sync DTOs stay as they are.

extension TripEntity {
    /// The trip as the time balance reads it.
    var timeInput: TimeTripInput {
        TimeTripInput(id: id, date: date, fromName: fromName, toName: toName, mode: mode, distanceKm: distanceKm,
                      isRoundTrip: isRoundTrip, journeyID: journeyID, legIndex: legIndex, durationMinutes: durationMinutes,
                      arrivalAt: arrivalAt, delayMinutes: delayMinutes, delaySource: TripDelaySource(storedValue: delaySourceRaw))
    }
}

/// A trip row of the JSON backup: the sync row's keys plus `duration_minutes`, `delay_minutes`, `delay_source` and
/// `arrival_at` (KlimaCore `TripTimeBackupRow`, tested there).
typealias BackupTripRow = TripTimeBackupRow<TripDTO>

extension TripTimeBackupRow where Base == TripDTO {
    /// Export: the row with every time field (zeros included, so a restore over a newer local value is exact).
    init(entity e: TripEntity) {
        self.init(TripDTO(e, userID: ""),
                  times: TripTimeBackupFields(durationMinutes: e.durationMinutes, delayMinutes: e.delayMinutes,
                                              delaySource: e.delaySourceRaw, arrivalAt: e.arrivalAt))
    }
}

extension TripTimeBackupFields {
    /// Import: only the keys the file has (an older backup has none – the entity keeps what it has, a new one its defaults).
    func apply(to e: TripEntity) {
        if let durationMinutes { e.durationMinutes = durationMinutes }
        if let delayMinutes { e.delayMinutes = delayMinutes }
        if let delaySource { e.delaySourceRaw = delaySource }
        if let arrivalAt { e.arrivalAt = arrivalAt }
    }
}
