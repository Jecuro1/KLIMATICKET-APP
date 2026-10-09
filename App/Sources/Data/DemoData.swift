import Foundation
import SwiftData
import KlimaCore

/// Realistic sample year for screenshots, previews and the "Demo ansehen" option:
/// an Arlberg commuter (St. Anton ↔ Innsbruck) with weekend trips across Austria.
@MainActor
enum DemoData {
    struct Route {
        let from: String, to: String, fromID: String?, toID: String?, mode: TransportMode, km: Double, fare: Double, states: [String]
    }

    static let routes: [Route] = [
        Route(from: "St. Anton am Arlberg", to: "Innsbruck Hauptbahnhof", fromID: "at:47:1222", toID: "at:47:1187", mode: .train, km: 101, fare: 23.5, states: ["T"]),
        Route(from: "St. Anton am Arlberg", to: "Landeck-Zams", fromID: "at:47:1222", toID: "at:47:1212", mode: .train, km: 28, fare: 6.7, states: ["T"]),
        Route(from: "St. Anton am Arlberg", to: "Bludenz", fromID: "at:47:1222", toID: "at:48:130", mode: .train, km: 41, fare: 8.6, states: ["T", "V"]),
        Route(from: "Langen am Arlberg", to: "Bregenz", fromID: "at:48:1226", toID: "at:48:452", mode: .train, km: 88, fare: 18.8, states: ["V"]),
        Route(from: "Innsbruck Hauptbahnhof", to: "Wien Hauptbahnhof", fromID: "at:47:1187", toID: "at:49:1349", mode: .train, km: 476, fare: 92.8, states: ["NÖ", "OÖ", "S", "T", "W"]),
        Route(from: "Innsbruck Hauptbahnhof", to: "Salzburg Hauptbahnhof", fromID: "at:47:1187", toID: "at:45:50002", mode: .train, km: 189, fare: 55.2, states: ["S", "T"]),
        Route(from: "Wien Hauptbahnhof", to: "Wien Praterstern", fromID: "wl:60201349", toID: "wl:60201040", mode: .metro, km: 4.5, fare: 3.2, states: ["W"]),
        Route(from: "Innsbruck Congress", to: "Hungerburg", fromID: nil, toID: nil, mode: .cableCar, km: 1.8, fare: 6.5, states: ["T"]),
        Route(from: "Innsbruck Hauptbahnhof", to: "Innsbruck Marktplatz", fromID: "at:47:1187", toID: nil, mode: .tram, km: 1.6, fare: 3.3, states: ["T"]),
        Route(from: "St. Anton am Arlberg", to: "Lech", fromID: "at:47:1222", toID: nil, mode: .bus, km: 19, fare: 5.8, states: ["T", "V"]),
        Route(from: "Graz Hauptbahnhof", to: "Klagenfurt Hauptbahnhof", fromID: "at:46:3040", toID: "at:42:3642", mode: .train, km: 128, fare: 32.0, states: ["K", "ST"]),
    ]

    /// Fills the context with a ticket started ~222 days ago and ~90 trips.
    static func seed(into context: ModelContext, now: Date = Date()) {
        let cal = Calendar.vienna
        let start = cal.date(byAdding: .day, value: -222, to: cal.startOfDay(for: now)) ?? now
        let ticket = TicketEntity(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", variant: .klassik, family: .oe,
                                  price: 1_400, startDate: start, holderName: "Lena Hofer", ticketNumber: "KT-2026-48 31 07")
        ticket.themeRaw = "twilight"
        context.insert(ticket)

        var generator = SeededGenerator(seed: 42)
        var day = start
        var count = 0
        var seeded: [TripEntity] = [] // MARK: tripmeta
        while day <= now {
            let weekday = cal.component(.weekday, from: day) // 1 = So
            let roll = Double.random(in: 0..<1, using: &generator)
            var plans: [(Route, Int, Bool)] = []
            // Tuned (simulated exactly with this RNG) to 79 trips · € 1.050 · 75 % of € 1.400 – shows progress + forecast.
            if (2...6).contains(weekday) {
                if roll < 0.02 { plans.append((routes[0], 7, true)) }
                else if roll < 0.10 { plans.append((routes[1], 8, true)) }
                else if roll < 0.30 { plans.append((routes[9], 17, false)) }
            } else {
                if roll < 0.01 { plans.append((routes[4], 9, false)); plans.append((routes[6], 15, false)) }
                else if roll < 0.03 { plans.append((routes[5], 10, true)) }
                else if roll < 0.18 { plans.append((routes[2], 11, true)) }
                else if roll < 0.24 { plans.append((routes[3], 12, false)) }
                else if roll < 0.28 { plans.append((routes[7], 14, true)); plans.append((routes[8], 16, false)) }
                else if roll < 0.30 { plans.append((routes[10], 9, false)) }
            }
            for (route, hour, round) in plans {
                let minute = Int.random(in: 0..<55, using: &generator)
                let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                guard date <= now else { continue }
                let trip = TripEntity(date: date, fromName: route.from, toName: route.to, fromStationID: route.fromID,
                                      toStationID: route.toID, mode: route.mode, distanceKm: route.km, fareEUR: route.fare,
                                      isRoundTrip: round, states: route.states)
                context.insert(trip)
                seeded.append(trip)
                count += 1
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? now.addingTimeInterval(86_400)
        }

        let favorites = [
            FavoriteRouteEntity(title: "Arbeit", fromName: routes[0].from, toName: routes[0].to, fromStationID: routes[0].fromID, toStationID: routes[0].toID, mode: .train, distanceKm: routes[0].km,
                                fareEUR: routes[0].fare, isRoundTrip: true, states: routes[0].states, sortIndex: 0),
            FavoriteRouteEntity(title: "Landeck", fromName: routes[1].from, toName: routes[1].to, fromStationID: routes[1].fromID, toStationID: routes[1].toID, mode: .train, distanceKm: routes[1].km,
                                fareEUR: routes[1].fare, isRoundTrip: true, states: routes[1].states, sortIndex: 1),
            FavoriteRouteEntity(title: "Bludenz", fromName: routes[2].from, toName: routes[2].to, fromStationID: routes[2].fromID, toStationID: routes[2].toID, mode: .train, distanceKm: routes[2].km,
                                fareEUR: routes[2].fare, isRoundTrip: true, states: routes[2].states, sortIndex: 2),
            FavoriteRouteEntity(title: "Lech", fromName: routes[9].from, toName: routes[9].to, fromStationID: routes[9].fromID, toStationID: routes[9].toID, mode: .bus, distanceKm: routes[9].km,
                                fareEUR: routes[9].fare, states: routes[9].states, sortIndex: 3),
        ]
        favorites.forEach { context.insert($0) }
        // MARK: tripmeta – purposes + "Ohne KlimaTicket nicht gefahren" (values unchanged, so the totals stay the same).
        MetaDemoCategories.assign(trips: seeded, favorites: favorites)
        try? context.save()
        print("Demo data: \(count) trips")
    }
}

/// Deterministic RNG so screenshots are stable between builds.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
