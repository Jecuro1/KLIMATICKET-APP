import Foundation

public struct Achievement: Hashable, Sendable, Identifiable {
    public enum Tier: String, Sendable { case bronze, silver, gold, platinum }

    public var id: String
    public var title: String
    public var detail: String
    public var symbolName: String
    public var tier: Tier
    /// 0…1
    public var progress: Double
    public var isUnlocked: Bool { progress >= 1 }
    /// Human-readable progress, e.g. "640 / 1.000 km".
    public var progressLabel: String
}

/// Derives achievements purely from trips + summary – no persistence needed.
public enum AchievementEngine {
    public static func evaluate(summary: SavingsSummary, trips: [TripRecord], records: TravelRecords) -> [Achievement] {
        func make(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ tier: Achievement.Tier,
                  current raw: Double, target: Double, unit: String) -> Achievement {
            let current = raw.isFinite ? max(0, raw) : 0   // a broken figure must not trap in Int(_:) below
            return Achievement(id: id, title: title, detail: detail, symbolName: symbol, tier: tier,
                        progress: target > 0 ? min(1, current / target) : 0,
                        progressLabel: "\(group(Int(min(current, target).rounded()))) / \(group(Int(target))) \(unit)".trimmingCharacters(in: .whitespaces))
        }
        let km = summary.distanceKm
        let tripCount = JourneySummary.tripCount(trips)   // a journey is one "Fahrt" (docs/JOURNEYS.md)
        let modes = Set(trips.map(\.mode))
        let calendar = Calendar.vienna
        var nightOwl = false, earlyBird = false
        for trip in trips where !(nightOwl && earlyBird) {
            let hour = calendar.component(.hour, from: trip.date)
            if hour >= 22 || hour < 5 { nightOwl = true }
            if (5..<7).contains(hour) { earlyBird = true }
        }

        return [
            make("first-trip", "Eingestiegen", "Deine erste Fahrt erfasst", "figure.walk.departure", .bronze,
                 current: Double(tripCount), target: 1, unit: "Fahrt"),
            make("quarter", "Ein Viertel geschafft", "25 % des Ticketpreises herausgefahren", "chart.pie", .bronze,
                 current: summary.amortizedFraction * 100, target: 25, unit: "%"),
            make("half", "Halbzeit", "50 % des Ticketpreises herausgefahren", "circle.lefthalf.filled", .silver,
                 current: summary.amortizedFraction * 100, target: 50, unit: "%"),
            make("break-even", "Rentiert!", "Das Ticket hat sich bezahlt gemacht", "checkmark.seal.fill", .gold,
                 current: summary.amortizedFraction * 100, target: 100, unit: "%"),
            make("double", "Doppelt gut", "Doppelter Ticketwert erreicht", "sparkles", .platinum,
                 current: summary.amortizedFraction * 100, target: 200, unit: "%"),
            make("km-1000", "Tausender", "1.000 km mit Öffis unterwegs", "point.topleft.down.to.point.bottomright.curvepath", .bronze,
                 current: km, target: 1_000, unit: "km"),
            make("km-5000", "Streckenkenner:in", "5.000 km unterwegs", "map", .silver,
                 current: km, target: 5_000, unit: "km"),
            make("km-10000", "Österreich-Umrunder:in", "10.000 km unterwegs", "globe.europe.africa.fill", .gold,
                 current: km, target: 10_000, unit: "km"),
            make("co2-500", "Klimaschützer:in", "500 kg CO₂ eingespart", "leaf.fill", .silver,
                 current: summary.co2SavedKg, target: 500, unit: "kg"),
            make("co2-1000", "Eine Tonne", "1 Tonne CO₂ eingespart", "tree.fill", .gold,
                 current: summary.co2SavedKg, target: 1_000, unit: "kg"),
            make("trips-100", "Stammgast", "100 Fahrten erfasst", "100.circle", .silver,
                 current: Double(tripCount), target: 100, unit: "Fahrten"),
            make("states-5", "Bundesländer-Sammler:in", "In 5 Bundesländern unterwegs", "mappin.and.ellipse", .silver,
                 current: Double(records.statesVisited.count), target: 5, unit: "Länder"),
            make("states-9", "Ganz Österreich", "Alle 9 Bundesländer bereist", "flag.checkered", .platinum,
                 current: Double(records.statesVisited.count), target: 9, unit: "Länder"),
            make("streak-7", "Eine Woche am Stück", "7 Tage in Folge unterwegs", "flame.fill", .bronze,
                 current: Double(records.longestStreakDays), target: 7, unit: "Tage"),
            make("modes-4", "Multimodal", "4 verschiedene Verkehrsmittel genutzt", "square.grid.2x2.fill", .silver,
                 current: Double(modes.count), target: 4, unit: "Arten"),
            make("night-owl", "Nachteule", "Eine Fahrt nach 22 Uhr", "moon.stars.fill", .bronze,
                 current: nightOwl ? 1 : 0, target: 1, unit: ""),
            make("early-bird", "Frühaufsteher:in", "Eine Fahrt vor 7 Uhr", "sunrise.fill", .bronze,
                 current: earlyBird ? 1 : 0, target: 1, unit: ""),
        ]
    }

    static func group(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, c) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(".") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
