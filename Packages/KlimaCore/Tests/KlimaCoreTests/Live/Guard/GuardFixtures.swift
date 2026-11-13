import Foundation
@testable import KlimaCore

/// Synthetic connection for the Anschluss-Wächter tests (Vienna wall clock, 2026-10-12): RJX 66 Wien Hbf 13:30 → St. Pölten
/// Hbf 14:28 (platform 4), a 3-minute walk, REX 2 St. Pölten Hbf 14:40 (platform 5) → Wiener Neustadt Hbf 15:50. Invented
/// times on real station names; no recorded trip.
enum GuardFixture {
    static func at(_ hhmm: String, second: Int = 0, day: Int = 12, month: Int = 10) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: parts[0], minute: parts[1], second: second))!
    }

    static let wien = Location(lid: "A=1@L=8100003@", kind: .station, extId: "8100003", name: "Wien Hbf")
    static let stPoelten = Location(lid: "A=1@L=8100008@", kind: .station, extId: "8100008", name: "St.Pölten Hbf")
    static let neustadt = Location(lid: "A=1@L=8100516@", kind: .station, extId: "8100516", name: "Wiener Neustadt Hbf")
    static let linz = Location(lid: "A=1@L=8100013@", kind: .station, extId: "8100013", name: "Linz/Donau Hbf")

    static let rjx = Line(name: "RJX 66", category: "RJX", trainNumber: "66", productClass: 1, mode: .train)
    static let rex = Line(name: "REX 2", category: "REX", lineNumber: "2", productClass: 16, mode: .train)
    static let rex3 = Line(name: "REX 3", category: "REX", lineNumber: "3", productClass: 16, mode: .train)

    static func event(_ planned: Date?, delay: TimeInterval?, platform: String? = nil, realtimePlatform: String? = nil,
                      cancelled: Bool = false) -> StopEvent {
        StopEvent(planned: planned, realtime: delay.flatMap { d in planned.map { $0.addingTimeInterval(d) } },
                  plannedPlatform: platform.map { Platform(text: $0, kind: .track) },
                  realtimePlatform: (realtimePlatform ?? (delay == nil ? nil : platform)).map { Platform(text: $0, kind: .track) },
                  isCancelled: cancelled, prognosis: delay == nil ? nil : .prognosed)
    }

    /// The connection. Delays in seconds (nil: no realtime). `walk` nil: no walk leg at all („Fußweg nicht bekannt“).
    static func journey(arrival: Date = at("14:28"), feederDelay: TimeInterval? = 180,
                        departure: Date = at("14:40"), connectionDelay: TimeInterval? = 60,
                        walk: Int? = 3, reachable: Bool? = true, feederCancelled: Bool = false, arrivalCancelled: Bool = false,
                        connectionCancelled: Bool = false, departureCancelled: Bool = false, realtimePlatform: String? = nil,
                        laterChange: Bool = false, token: String? = "ctx-1") -> Journey {
        var legs: [Leg] = []
        let feederDeparture = arrival.addingTimeInterval(-58 * 60)
        legs.append(Leg(id: "L0", kind: .ride, origin: wien, destination: stPoelten,
                        departure: event(feederDeparture, delay: feederDelay == nil ? nil : 0, platform: "8"),
                        arrival: event(arrival, delay: feederDelay, platform: "4", cancelled: arrivalCancelled),
                        line: rjx, direction: "Innsbruck Hbf", tripID: "trip-feeder", stopovers: [
                            Stopover(location: wien, departure: event(feederDeparture, delay: 0)),
                            Stopover(location: stPoelten, arrival: event(arrival, delay: feederDelay)),
                        ], polyline: [GeoPoint(latitude: 48.18, longitude: 16.37)], isReachable: true, isCancelled: feederCancelled))
        if let walk {
            legs.append(Leg(id: "L1", kind: .walk, origin: stPoelten, destination: stPoelten,
                            departure: StopEvent(planned: arrival), arrival: StopEvent(planned: arrival.addingTimeInterval(Double(walk) * 60)),
                            walkDurationSeconds: walk * 60))
        }
        let connectionArrival = departure.addingTimeInterval(70 * 60)
        legs.append(Leg(id: "L2", kind: .ride, origin: stPoelten, destination: laterChange ? linz : neustadt,
                        departure: event(departure, delay: connectionDelay, platform: "5", realtimePlatform: realtimePlatform,
                                         cancelled: departureCancelled),
                        arrival: event(connectionArrival, delay: connectionDelay, platform: "2"),
                        line: rex, direction: "Wiener Neustadt Hbf", tripID: "trip-connection",
                        remarks: [Remark(kind: .info, text: "Fahrradmitnahme")], isReachable: reachable, isCancelled: connectionCancelled))
        if laterChange {
            let d = connectionArrival.addingTimeInterval(12 * 60)
            legs.append(Leg(id: "L3", kind: .ride, origin: linz, destination: neustadt,
                            departure: event(d, delay: nil, platform: "1"), arrival: event(d.addingTimeInterval(30 * 60), delay: nil),
                            line: rex3, tripID: "trip-third"))
        }
        return Journey(legs: legs, durationSeconds: 7200, changes: laterChange ? 2 : 1, refreshToken: token,
                       remarks: [Remark(kind: .info, text: "x")], shopURL: URL(string: "https://example.invalid/shop"))
    }

    static let record = GuardRecord(followTripID: "trip-feeder", journey: journey(), journeyAt: at("14:00"),
                                    products: .klimaTicket, klimaTicketOnly: true, createdAt: at("13:00"))

    /// The follow of the feeder (target alighting at St. Pölten) with one answer at `now`.
    static func followSnapshot(arrival: Date = at("14:28"), delay: TimeInterval?, now: Date, cancelled: Bool = false) -> LiveFollowSnapshot {
        let depart = arrival.addingTimeInterval(-58 * 60)
        let trip = TripDetails(tripID: "trip-feeder", stopovers: [
            Stopover(location: wien, departure: event(depart, delay: 0), index: 0),
            Stopover(location: stPoelten, arrival: event(arrival, delay: delay, platform: "4"),
                     departure: event(arrival.addingTimeInterval(120), delay: delay), index: 1),
            Stopover(location: linz, arrival: event(arrival.addingTimeInterval(50 * 60), delay: delay), index: 2),
        ], isCancelled: cancelled)
        let target = LiveFollowTarget(tripID: "trip-feeder", lineName: "RJX 66", boardingStop: wien, alightStop: stPoelten,
                                      plannedDeparture: depart, plannedArrival: arrival,
                                      transfer: FollowTransfer(stationName: "St.Pölten Hbf", plannedDeparture: at("14:40"), lineName: "REX 2"))
        return LiveFollow.snapshot(trip, target: target, now: now)
    }

    /// One assessment from scratch.
    static func assess(_ journey: Journey, now: Date, journeyAt: Date? = nil, memory: GuardMemory = GuardMemory(),
                       follow: LiveFollowSnapshot? = nil, followAt: Date? = nil) -> (assessment: GuardAssessment, memory: GuardMemory) {
        ConnectionGuard.assess(journey: journey, followSnapshot: follow, followAt: followAt, journeyAt: journeyAt ?? now,
                               previous: memory, now: now)!
    }

    /// Every journey with at least one change in the recorded planner answers.
    static func plannerJourneysWithChanges() throws -> [(String, Journey)] {
        let scenarios = ["tripsearch_innsbruck_lech_bus", "tripsearch_st_anton_innsbruck", "tripsearch_tyrol_bus_landeck_ischgl",
                         "tripsearch_innsbruck_wien_hbf", "tripsearch_graz_klagenfurt_koralm", "tripsearch_wien_westbf_salzburg",
                         "tripsearch_overnight_dst_change_wien_innsbruck", "tripsearch_via_feldkirch_dwell_ibk_bregenz",
                         "tripsearch_arrive_by_innsbruck_wien", "tripsearch_vienna_urban_address_to_poi",
                         "tripsearch_paging_later_graz_klagenfurt", "reconstruction_innsbruck_lech_outReconL"]
        var out: [(String, Journey)] = []
        for s in scenarios {
            let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/\(s).response"))
            out += page.journeys.filter { $0.rideLegs.count >= 2 }.map { (s, $0) }
        }
        return out
    }
}
