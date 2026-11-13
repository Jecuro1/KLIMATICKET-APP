import Foundation
@testable import KlimaCore

/// Fixtures of the „Zeitbilanz“ tests: dates in Vienna, trips with only what a test needs.
enum TimeBalanceFixtures {
    static let calendar = Calendar.vienna

    /// A Vienna wall-clock time.
    static func vienna(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func trip(_ date: Date, mode: TransportMode = .train, km: Double = 50, roundTrip: Bool = false, duration: Int = 0,
                     arrival: Date? = nil, journey: UUID? = nil, leg: Int = 0, delay: Int = 0, delaySource: TripDelaySource? = nil,
                     from: String = "A", to: String = "B") -> TimeTripInput {
        TimeTripInput(date: date, fromName: from, toName: to, mode: mode, distanceKm: km, isRoundTrip: roundTrip, journeyID: journey,
                      legIndex: leg, durationMinutes: duration, arrivalAt: arrival, delayMinutes: delay, delaySource: delaySource)
    }

    /// The same trip as the Auto-Vergleich sees it.
    static func record(_ trip: TimeTripInput) -> TripRecord {
        TripRecord(id: trip.id, date: trip.date, fromName: trip.fromName, toName: trip.toName, mode: trip.mode, distanceKm: trip.distanceKm,
                   fareEUR: 10, isRoundTrip: trip.isRoundTrip, journeyID: trip.journeyID, legIndex: trip.legIndex)
    }

    static func compute(_ trips: [TimeTripInput], from start: Date, to end: Date, now: Date,
                        profile: CarProfile = CarProfile()) -> TimeBalance {
        TimeBalanceCalculator.compute(trips: trips, range: start...end, now: now, carProfile: profile)
    }
}
