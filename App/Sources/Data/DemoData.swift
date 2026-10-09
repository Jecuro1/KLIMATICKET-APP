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
        Route(from: "St. Anton am Arlberg", to: "Innsbruck Hbf", fromID: nil, toID: nil, mode: .train, km: 101, fare: 23.4, states: ["T"]),
        Route(from: "St. Anton am Arlberg", to: "Landeck-Zams", fromID: nil, toID: nil, mode: .train, km: 28, fare: 7.4, states: ["T"]),
        Route(from: "St. Anton am Arlberg", to: "Bludenz", fromID: nil, toID: nil, mode: .train, km: 41, fare: 9.6, states: ["T", "V"]),
        Route(from: "Langen am Arlberg", to: "Bregenz", fromID: nil, toID: nil, mode: .train, km: 88, fare: 17.8, states: ["V"]),
        Route(from: "Innsbruck Hbf", to: "Wien Hauptbahnhof", fromID: nil, toID: nil, mode: .train, km: 476, fare: 79.9, states: ["T", "S", "OÖ", "NÖ", "W"]),
        Route(from: "Innsbruck Hbf", to: "Salzburg Hbf", fromID: nil, toID: nil, mode: .train, km: 189, fare: 41.2, states: ["T", "S"]),
        Route(from: "Wien Hauptbahnhof", to: "Praterstern", fromID: nil, toID: nil, mode: .metro, km: 4.5, fare: 3.2, states: ["W"]),
        Route(from: "Innsbruck Hbf", to: "Hungerburg", fromID: nil, toID: nil, mode: .cableCar, km: 3, fare: 3.0, states: ["T"]),
        Route(from: "Innsbruck Hbf", to: "Innsbruck Marktplatz", fromID: nil, toID: nil, mode: .tram, km: 1.6, fare: 3.0, states: ["T"]),
        Route(from: "St. Anton am Arlberg", to: "Lech", fromID: nil, toID: nil, mode: .bus, km: 19, fare: 5.8, states: ["T", "V"]),
        Route(from: "Graz Hbf", to: "Klagenfurt Hbf", fromID: nil, toID: nil, mode: .train, km: 128, fare: 27.9, states: ["ST", "K"]),
    ]

    /// Fills the context with a ticket started ~222 days ago and ~90 trips.
    static func seed(into context: ModelContext, now: Date = Date()) {
        let cal = Calendar.vienna
        let start = cal.date(byAdding: .day, value: -222, to: cal.startOfDay(for: now)) ?? now
        let ticket = TicketEntity(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", variant: .klassik, family: .oe,
                                  price: 1_300, startDate: start, holderName: "Lena Hofer", ticketNumber: "KT-2026-48 31 07")
        ticket.themeRaw = "aurora"
        context.insert(ticket)

        var generator = SeededGenerator(seed: 42)
        var day = start
        var count = 0
        while day <= now {
            let weekday = cal.component(.weekday, from: day) // 1 = So
            let roll = Double.random(in: 0..<1, using: &generator)
            var plans: [(Route, Int, Bool)] = []
            // Tuned so the demo year sits at roughly 70–80 % amortisation (shows progress + forecast).
            if (2...6).contains(weekday) {
                if roll < 0.045 { plans.append((routes[0], 7, true)) }
                else if roll < 0.115 { plans.append((routes[1], 8, true)) }
                else if roll < 0.165 { plans.append((routes[9], 17, false)) }
            } else {
                if roll < 0.02 { plans.append((routes[4], 9, false)); plans.append((routes[6], 15, false)) }
                else if roll < 0.05 { plans.append((routes[5], 10, true)) }
                else if roll < 0.13 { plans.append((routes[2], 11, true)) }
                else if roll < 0.19 { plans.append((routes[3], 12, false)) }
                else if roll < 0.23 { plans.append((routes[7], 14, true)); plans.append((routes[8], 16, false)) }
                else if roll < 0.25 { plans.append((routes[10], 9, false)) }
            }
            for (route, hour, round) in plans {
                let minute = Int.random(in: 0..<55, using: &generator)
                let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                guard date <= now else { continue }
                context.insert(TripEntity(date: date, fromName: route.from, toName: route.to, fromStationID: route.fromID,
                                          toStationID: route.toID, mode: route.mode, distanceKm: route.km, fareEUR: route.fare,
                                          isRoundTrip: round, states: route.states))
                count += 1
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? now.addingTimeInterval(86_400)
        }

        let favorites = [
            FavoriteRouteEntity(title: "Arbeit", fromName: routes[0].from, toName: routes[0].to, mode: .train, distanceKm: routes[0].km,
                                fareEUR: routes[0].fare, isRoundTrip: true, states: routes[0].states, sortIndex: 0),
            FavoriteRouteEntity(title: "Landeck", fromName: routes[1].from, toName: routes[1].to, mode: .train, distanceKm: routes[1].km,
                                fareEUR: routes[1].fare, isRoundTrip: true, states: routes[1].states, sortIndex: 1),
            FavoriteRouteEntity(title: "Bludenz", fromName: routes[2].from, toName: routes[2].to, mode: .train, distanceKm: routes[2].km,
                                fareEUR: routes[2].fare, isRoundTrip: true, states: routes[2].states, sortIndex: 2),
            FavoriteRouteEntity(title: "Lech", fromName: routes[9].from, toName: routes[9].to, mode: .bus, distanceKm: routes[9].km,
                                fareEUR: routes[9].fare, states: routes[9].states, sortIndex: 3),
        ]
        favorites.forEach { context.insert($0) }
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
