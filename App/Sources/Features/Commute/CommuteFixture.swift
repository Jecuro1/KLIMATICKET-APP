import Foundation
import KlimaCore

// MARK: commute – the CI scenes of the Pendel-Modus (`-KBScreenshot <screen> -KBDemo YES`): the demo commuter St. Anton am Arlberg ↔
// Innsbruck Hbf (DemoData's „Arbeit“ route), a pinned clock and synthetic connections. Nothing here touches the network; the
// rows go through the same KlimaCore code (`CommuteStatus`, `CommuteAdvisor`) as live answers.

/// One scene: the clock, the settings, the live availability and the answers of the „search“.
struct CommuteDemoScene {
    var now: Date
    var settings: CommuteSettings
    /// Pretends live data is unavailable (no consent …); nil = available.
    var liveUnavailable: LiveDataService.Unavailable?
    /// The detector's guess for the invitation scene.
    var guess: CommuteGuess?
    var outbound: [Journey]
    var inbound: [Journey]

    func page(direction: CommuteDirection) -> JourneyPage {
        JourneyPage(journeys: direction == .outbound ? outbound : inbound, realtimeUpdatedAt: now)
    }
}

enum CommuteFixture {
    static let origin = CommuteEndpoint(stationID: "at:47:1222", name: "St. Anton am Arlberg")
    static let destination = CommuteEndpoint(stationID: "at:47:1187", name: "Innsbruck Hauptbahnhof")

    /// One train of the scene: departure clock time, line, delay, platforms, cancelled, ride minutes.
    struct Train {
        var hour: Int
        var minute: Int
        var category: String
        var number: String
        var direction: String
        var delay: Int? = 0
        var platform = "2"
        var changedTo: String? = nil
        var cancelled = false
        var minutes = 69
    }

    static func scene(_ screen: String, today: Date = Date()) -> CommuteDemoScene {
        let cal = Calendar.vienna
        func at(_ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        var settings = CommuteSettings()
        settings.isEnabled = screen != "commuteSetup"
        // The settings scene shows its choice ticked among the suggestions; the card scenes come from the demo's „Arbeit“ route.
        settings.source = screen == "commuteSettings" ? .suggestion : .savedRoute
        settings.origin = origin
        settings.destination = destination
        // Mo–Fr plus today, so a scene taken on a weekend still shows the morning.
        var days = CommutePlan.workdays
        if let weekday = RouteWeekday(calendarWeekday: cal.component(.weekday, from: today)) { days.insert(weekday) }
        settings.plan = CommutePlan(weekdays: days, outboundMinute: 7 * 60 + 20, returnMinute: 17 * 60 + 12)
        settings.logsRoundTrip = true

        let morningRows: [Train]
        switch screen {
        case "commuteDelayed", "commuteAX5":
            morningRows = [Train(hour: 7, minute: 20, category: "RJX", number: "160", direction: "Wien Hbf", delay: 12),
                           Train(hour: 7, minute: 27, category: "RJ", number: "362", direction: "Wien Hbf", delay: 0, platform: "3", minutes: 64),
                           Train(hour: 7, minute: 42, category: "REX", number: "5110", direction: "Innsbruck Hbf", delay: 2, platform: "1", minutes: 86),
                           Train(hour: 8, minute: 20, category: "RJX", number: "162", direction: "Wien Hbf")]
        case "commuteCancelled":
            morningRows = [Train(hour: 7, minute: 20, category: "RJX", number: "160", direction: "Wien Hbf", delay: nil, cancelled: true),
                           Train(hour: 7, minute: 42, category: "REX", number: "5110", direction: "Innsbruck Hbf", delay: 0, platform: "3", minutes: 86),
                           Train(hour: 8, minute: 20, category: "RJX", number: "162", direction: "Wien Hbf", delay: 1)]
        default:
            morningRows = [Train(hour: 7, minute: 20, category: "RJX", number: "160", direction: "Wien Hbf", delay: 0),
                           Train(hour: 7, minute: 42, category: "REX", number: "5110", direction: "Innsbruck Hbf", delay: 4, platform: "1", minutes: 86),
                           Train(hour: 8, minute: 20, category: "RJX", number: "162", direction: "Wien Hbf", delay: 0, changedTo: "3"),
                           Train(hour: 8, minute: 42, category: "REX", number: "5112", direction: "Innsbruck Hbf", platform: "1", minutes: 86)]
        }
        let eveningRows = [Train(hour: 17, minute: 12, category: "RJX", number: "167", direction: "Bregenz", delay: 0, platform: "5"),
                           Train(hour: 17, minute: 40, category: "REX", number: "5131", direction: "Landeck-Zams", delay: 3, platform: "7", minutes: 88),
                           Train(hour: 18, minute: 12, category: "RJX", number: "169", direction: "Zürich HB", platform: "5")]

        let now: Date
        switch screen {
        case "commuteEvening": now = at(15, 10)
        default: now = at(7, 4)
        }
        let guess = CommuteGuess(origin: origin, destination: destination, rides: 34, days: 17, weeks: 7,
                                 weekdays: CommutePlan.workdays, outboundMinute: 7 * 60 + 20, returnMinute: 17 * 60 + 10,
                                 mostlyRoundTrips: false, confidence: .high)
        return CommuteDemoScene(now: now, settings: settings,
                                liveUnavailable: screen == "commuteNoConsent" ? .consentUndecided : nil,
                                guess: screen == "commuteSetup" || screen == "commuteSettings" ? guess : nil,
                                outbound: morningRows.map { journey($0, day: today, outbound: true) },
                                inbound: eveningRows.map { journey($0, day: today, outbound: false) })
    }

    /// A direct ride between the two demo stations (the stop names of the planner's demo places).
    static func journey(_ train: Train, day: Date, outbound: Bool) -> Journey {
        let cal = Calendar.vienna
        let start = cal.date(bySettingHour: train.hour, minute: train.minute, second: 0, of: day) ?? day
        let end = start.addingTimeInterval(Double(train.minutes) * 60)
        let anton = DemoPlaces.named("St.Anton am Arlberg Bahnhof") ?? DemoPlaces.innsbruck
        let ibk = DemoPlaces.innsbruck
        let from = outbound ? anton : ibk, to = outbound ? ibk : anton
        let isRegional = train.category == "REX"
        let line = DemoJourneys.line("\(train.category) \(train.number)", category: train.category, cls: isRegional ? 16 : 1, mode: .train,
                                     number: nil, train: train.number, long: isRegional ? "Regional-Express" : "railjet")
        let departure = DemoJourneys.event(start, delay: train.delay, platform: train.platform, changedTo: train.changedTo,
                                           cancelled: train.cancelled)
        let arrival = DemoJourneys.event(end, delay: train.delay, platform: outbound ? "5" : "2", cancelled: train.cancelled)
        let leg = Leg(id: "commute-\(train.number)", kind: .ride, origin: from, destination: to, departure: departure, arrival: arrival,
                      line: line, direction: train.direction, tripID: "demo|\(train.number)", isCancelled: train.cancelled)
        return Journey(legs: [leg], durationSeconds: train.minutes * 60, changes: 0, refreshToken: "demo-commute-\(train.number)",
                       serviceDays: "täglich")
    }
}
