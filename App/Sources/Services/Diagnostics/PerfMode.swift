import Foundation
import SwiftData
import KlimaCore

/// Data for the CI performance tests (`-KBPerf YES`, see `LaunchMode.isPerf` and KlimaBilanzPerfTests):
/// the regular demo year, optionally plus `-KBPerfTrips <n>` synthetic trips (a heavy commuter's history) to see how
/// the screens scale with the amount of data.
@MainActor
enum PerfMode {
    static let defaultsSuite = "perf"

    /// `-KBPerfTrips <n>` (0 when absent).
    static var extraTrips: Int { max(0, UserDefaults.standard.integer(forKey: "KBPerfTrips")) }

    /// Fresh settings for every run: onboarding done, no update checks.
    static func makeSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        defaults.removePersistentDomain(forName: defaultsSuite)
        let settings = AppSettings(defaults: defaults)
        settings.onboardingCompleted = true
        settings.autoUpdateCheck = false
        return settings
    }

    /// Demo year (+ `extraTrips`). Every seeded ticket counts as celebrated: the full-screen "Rentiert!" moment would
    /// cover the screen the tests measure (it showed up with +1 500 trips and hid every scroll view).
    static func seed(into context: ModelContext, settings: AppSettings, now: Date = Date()) {
        defer {
            let tickets = (try? context.fetch(FetchDescriptor<TicketEntity>())) ?? []
            settings.celebratedBreakEvenTicketIDs = tickets.map(\.id.uuidString)
        }
        DemoData.seed(into: context, now: now)
        let extra = extraTrips
        guard extra > 0 else { return }
        let cal = Calendar.vienna
        var generator = SeededGenerator(seed: 4_711)
        let routes = DemoData.routes
        var inserted = 0
        while inserted < extra {
            let route = routes[Int.random(in: 0..<routes.count, using: &generator)]
            let daysBack = Int.random(in: 0..<220, using: &generator)
            let day = cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: now)) ?? now
            let hour = Int.random(in: 6..<22, using: &generator)
            let minute = Int.random(in: 0..<60, using: &generator)
            let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            guard date <= now else { continue }
            context.insert(TripEntity(date: date, fromName: route.from, toName: route.to, fromStationID: route.fromID,
                                      toStationID: route.toID, mode: route.mode, distanceKm: route.km, fareEUR: route.fare,
                                      isRoundTrip: Bool.random(using: &generator), states: route.states))
            inserted += 1
        }
        try? context.save()
        print("Perf data: +\(inserted) synthetic trips")
    }
}
