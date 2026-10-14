import Foundation
@testable import KlimaCore

/// Shared fixtures for the Live verfolgen tests: the RJX 66 run Salzburg Hbf → Linz Hbf → Wien Hbf on 2026-10-12 (Vienna
/// wall clock). Salzburg 09:30 (platform 5), Linz 10:45/10:47 (planned platform 3, realtime 4), Wien 12:01 (platform 11).
enum FollowFixture {
    static func at(_ hhmm: String, second: Int = 0) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: parts[0], minute: parts[1], second: second))!
    }

    static let salzburg = Location(lid: "A=1@L=8100108@", kind: .station, extId: "8100108", name: "Salzburg Hbf")
    static let linz = Location(lid: "A=1@L=8100173@", kind: .station, extId: "8100173", name: "Linz Hbf")
    static let wien = Location(lid: "A=1@L=8100003@", kind: .station, extId: "8100003", name: "Wien Hbf")
    static let innsbruck = Location(lid: "A=1@L=8100002@", kind: .station, extId: "8100002", name: "Innsbruck Hbf")

    static func target(transfer: FollowTransfer? = nil) -> LiveFollowTarget {
        LiveFollowTarget(tripID: "T1", lineName: "RJX 66", boardingStop: salzburg, alightStop: wien,
                         plannedDeparture: at("09:30"), plannedArrival: at("12:01"), transfer: transfer)
    }

    static func trip(delayLinz: Int = 300, delayWien: Int = 360, platformAtBoarding: String = "5",
                     cancelled: Bool = false, updatedAt: Date? = nil) -> TripDetails {
        func ev(_ planned: String, _ delay: Int, platform: String? = nil, plannedPlatform: String? = nil) -> StopEvent {
            let p = at(planned)
            return StopEvent(planned: p, realtime: p.addingTimeInterval(TimeInterval(delay)),
                             plannedPlatform: plannedPlatform.map { Platform(text: $0) } ?? platform.map { Platform(text: $0) },
                             realtimePlatform: platform.map { Platform(text: $0) }, isCancelled: false, prognosis: .prognosed,
                             platformChangeFlag: false)
        }
        let stops = [
            Stopover(location: salzburg, departure: ev("09:30", 0, platform: platformAtBoarding), index: 0),
            Stopover(location: linz, arrival: ev("10:45", delayLinz - 300), departure: ev("10:47", delayLinz, platform: "4", plannedPlatform: "3"), index: 1),
            Stopover(location: wien, arrival: ev("12:01", delayWien, platform: "11"), index: 2),
        ]
        return TripDetails(tripID: "T1", stopovers: stops, isCancelled: cancelled, realtimeUpdatedAt: updatedAt)
    }
}
