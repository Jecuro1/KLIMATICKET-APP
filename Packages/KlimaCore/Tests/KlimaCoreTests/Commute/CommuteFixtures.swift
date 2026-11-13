import Foundation
@testable import KlimaCore

/// Builders for the Pendel-Modus tests: Vienna dates, trips and journeys.
enum CommuteFixtures {
    static let vienna: Calendar = .vienna

    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        vienna.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static let linz = CommuteEndpoint(stationID: "at:44:1", name: "Linz Hbf")
    static let wien = CommuteEndpoint(stationID: "at:49:1", name: "Wien Hbf")
    static let stPoelten = CommuteEndpoint(stationID: "at:43:1", name: "St. Pölten Hbf")
    static let salzburg = CommuteEndpoint(stationID: "at:50:1", name: "Salzburg Hbf")

    static func trip(_ from: CommuteEndpoint, _ to: CommuteEndpoint, _ date: Date, roundTrip: Bool = false,
                     journey: UUID? = nil, leg: Int = 0) -> TripRecord {
        TripRecord(date: date, fromName: from.name, toName: to.name, fromStationID: from.stationID, toStationID: to.stationID,
                   mode: .train, distanceKm: 180, fareEUR: 40, isRoundTrip: roundTrip, journeyID: journey, legIndex: leg)
    }

    /// Weekday commuting Linz ↔ Wien: out at `outHour`:`outMinute`, back at `backHour`:10, on Mon/Tue/Thu of `weeks` weeks
    /// counted back from Monday 2 Nov 2026.
    static func commuteWeeks(_ weeks: Int, outHour: Int = 7, outMinute: Int = 20, backHour: Int = 17,
                             from: CommuteEndpoint = linz, to: CommuteEndpoint = wien) -> [TripRecord] {
        var out: [TripRecord] = []
        for week in 0..<weeks {
            for weekdayOffset in [0, 1, 3] {   // Mon, Tue, Thu
                let day = 2 - week * 7 + weekdayOffset
                guard let base = vienna.date(byAdding: .day, value: day - 2, to: at(2026, 11, 2)) else { continue }
                let comps = vienna.dateComponents([.year, .month, .day], from: base)
                out.append(trip(from, to, at(comps.year!, comps.month!, comps.day!, outHour, outMinute)))
                out.append(trip(to, from, at(comps.year!, comps.month!, comps.day!, backHour, 10)))
            }
        }
        return out
    }

    // MARK: Journeys

    static func location(_ name: String, extId: String) -> Location { Location.station(extId: extId, name: name) }

    static let origin = location("Linz Hbf", extId: "8100013")
    static let destination = location("Wien Hbf", extId: "1290401")

    static func line(_ name: String, category: String = "RJX", number: String, mode: TransportMode = .train) -> Line {
        Line(name: name, fullName: name, category: category, categoryShort: category, lineNumber: nil, trainNumber: number,
             lineId: "test:\(name)", productClass: mode == .bus ? 64 : 1, mode: mode)
    }

    /// A direct connection: departure `planned`, `minutes` long, `delay` minutes late (nil = no realtime).
    static func journey(_ planned: Date, delay: Int? = 0, minutes: Int = 75, number: String = "162", platform: String? = "4",
                        changedTo: String? = nil, cancelled: Bool = false, arrivalDelay: Int? = nil, mode: TransportMode = .train) -> Journey {
        let arrive = planned.addingTimeInterval(Double(minutes) * 60)
        let depEvent = StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval(Double($0) * 60) },
                                 plannedPlatform: platform.map { Platform(text: $0, kind: .track) },
                                 realtimePlatform: (changedTo ?? platform).map { Platform(text: $0, kind: .track) },
                                 isCancelled: cancelled, platformChangeFlag: changedTo != nil)
        let arrDelay = arrivalDelay ?? delay
        let arrEvent = StopEvent(planned: arrive, realtime: arrDelay.map { arrive.addingTimeInterval(Double($0) * 60) }, isCancelled: cancelled)
        let leg = Leg(id: "leg-\(number)", kind: .ride, origin: origin, destination: destination, departure: depEvent, arrival: arrEvent,
                      line: line("RJX \(number)", number: number, mode: mode), direction: "Wien Hbf", tripID: "trip|\(number)",
                      isCancelled: cancelled)
        return Journey(legs: [leg], durationSeconds: minutes * 60, changes: 0)
    }
}
