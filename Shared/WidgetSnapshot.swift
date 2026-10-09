import Foundation

/// Compact, Codable summary the app writes for the widgets (App Group UserDefaults).
/// Shared source file: compiled into both the app and the widget extension.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    struct RecentTrip: Codable, Hashable, Sendable {
        var fromName: String
        var toName: String
        var modeSymbol: String
        var value: Double
        var date: Date
    }

    struct Favorite: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var modeSymbol: String
        var value: Double
        var distanceKm: Double = 0
        var fromName: String = ""
        var toName: String = ""
    }

    var generatedAt: Date
    var ticketName: String
    var ticketPrice: Double
    var totalValue: Double
    var amortizedFraction: Double
    var tripCount: Int
    var distanceKm: Double
    var co2SavedKg: Double
    var daysRemaining: Int
    var validUntil: Date
    var isPaidOff: Bool
    var forecastBreakEvenDate: Date?
    var lastTrip: RecentTrip?
    var favorites: [Favorite]
    /// Daily cumulative value points (max ~60) for a sparkline.
    var sparkline: [Double]

    var net: Double { totalValue - ticketPrice }
    var remaining: Double { max(0, ticketPrice - totalValue) }

    static let defaultsKey = "widgetSnapshot.v1"

    static var store: UserDefaults { AppGroup.defaults }

    static func load() -> WidgetSnapshot? {
        guard let data = store.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        WidgetSnapshot.store.set(data, forKey: WidgetSnapshot.defaultsKey)
    }

    /// Optimistically applies a quick-logged favourite (widget / Siri) or a saved ride (Live Activity, `date` = its
    /// start, which can lie before the snapshot) until the app recomputes precisely.
    mutating func apply(favorite: Favorite, date: Date) {
        // The widgets count the remaining days from `generatedAt` (WidInsight.daysRemaining): bring the stored value
        // up to `date` before moving `generatedAt`, or the days left would jump up by the snapshot's age. Only ever
        // forwards – moving it back (a ride that started yesterday) would cost the widget a day.
        if date > generatedAt {
            daysRemaining = max(0, daysRemaining - max(0, WidInsight.dayCount(from: generatedAt, to: date)))
            generatedAt = date
        }
        // The app counts only trips inside the ticket's validity – a trip after its end adds nothing here either.
        if date <= validUntil {
            totalValue += favorite.value
            tripCount += 1
            distanceKm += favorite.distanceKm
            co2SavedKg += max(0, (166 - 8) * favorite.distanceKm / 1000)
            amortizedFraction = ticketPrice > 0 ? totalValue / ticketPrice : 0
            isPaidOff = isPaidOff || totalValue >= ticketPrice
            sparkline.append(totalValue)
        }
        if lastTrip.map({ $0.date <= date }) ?? true {
            lastTrip = RecentTrip(fromName: favorite.fromName.isEmpty ? favorite.title : favorite.fromName,
                                  toName: favorite.toName, modeSymbol: favorite.modeSymbol, value: favorite.value, date: date)
        }
    }

    /// Realistic sample used for widget previews/placeholders and screenshots.
    static let sample = WidgetSnapshot(
        generatedAt: Date(),
        ticketName: "KlimaTicket Ö Klassik",
        ticketPrice: 1_300,
        totalValue: 946.4,
        amortizedFraction: 0.728,
        tripCount: 87,
        distanceKm: 4_812,
        co2SavedKg: 612,
        daysRemaining: 143,
        validUntil: Calendar.current.date(byAdding: .day, value: 143, to: Date()) ?? Date(),
        isPaidOff: false,
        forecastBreakEvenDate: Calendar.current.date(byAdding: .day, value: 66, to: Date()),
        lastTrip: RecentTrip(fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf", modeSymbol: "train.side.front.car", value: 22.8, date: Date()),
        favorites: [
            Favorite(id: UUID(), title: "Arbeit", modeSymbol: "train.side.front.car", value: 22.8),
            Favorite(id: UUID(), title: "Bludenz", modeSymbol: "train.side.front.car", value: 9.6),
        ],
        sparkline: [0, 40, 88, 130, 190, 240, 300, 355, 420, 480, 540, 610, 660, 720, 790, 850, 905, 946]
    )
}
