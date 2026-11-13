import Foundation

// Pendel-Modus (docs/COMMUTE.md §3): which direction applies now and whether the live window is open. All clock maths in
// the calendar's time zone (Vienna for the app) through `Calendar`, never by adding 86 400 s – so midnight and the two
// daylight-saving nights land where a wall clock says.

/// One planned commute departure.
public struct CommuteSlot: Hashable, Sendable {
    public var direction: CommuteDirection
    /// The planned departure (wall-clock time of the plan on that day).
    public var departure: Date

    public init(direction: CommuteDirection, departure: Date) {
        self.direction = direction
        self.departure = departure
    }
}

public enum CommuteWindow {
    /// The live window opens this long before a planned departure …
    public static let leadMinutes = 45
    /// … and stays open this long after it (late trains, a missed one).
    public static let tailMinutes = 30
    /// Before this hour the commute runs outbound, from it on back home (when the plan's times fit around it).
    public static let splitHour = 13

    public enum State: Hashable, Sendable {
        /// Within `leadMinutes` before to `tailMinutes` after a planned departure: show the next connections.
        case live(CommuteSlot)
        /// Outside every window: the next planned departure („Nächste Pendelfahrt heute 17:12“).
        case upcoming(CommuteSlot)
        /// No weekday in the plan.
        case inactive
    }

    /// The direction for „now“: before 13:00 outbound, from 13:00 on the return. A plan whose times do not sit on both sides
    /// of 13:00 (a late shift, a night shift) splits at the departure that is nearer in the day instead.
    public static func direction(at now: Date, plan: CommutePlan, calendar: Calendar) -> CommuteDirection {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let split = splitHour * 60
        if plan.outboundMinute < split && plan.returnMinute >= split {
            return minute < split ? .outbound : .inbound
        }
        func distance(_ a: Int, _ b: Int) -> Int {
            let d = abs(a - b) % (24 * 60)
            return min(d, 24 * 60 - d)
        }
        return distance(minute, plan.outboundMinute) <= distance(minute, plan.returnMinute) ? .outbound : .inbound
    }

    /// Live, upcoming or inactive at `now`. A window that crosses midnight belongs to the weekday of its departure.
    public static func state(at now: Date, plan: CommutePlan, calendar: Calendar) -> State {
        let all = slots(around: now, plan: plan, calendar: calendar)
        guard !all.isEmpty else { return .inactive }
        let lead = TimeInterval(leadMinutes * 60), tail = TimeInterval(tailMinutes * 60)
        // The open window whose departure is closest to now (two windows can overlap for a very short workday).
        let open = all.filter { now >= $0.departure.addingTimeInterval(-lead) && now <= $0.departure.addingTimeInterval(tail) }
        if let live = open.min(by: { abs($0.departure.timeIntervalSince(now)) < abs($1.departure.timeIntervalSince(now)) }) {
            return .live(live)
        }
        if let next = all.first(where: { $0.departure > now }) { return .upcoming(next) }
        return .inactive
    }

    /// The planned departures from yesterday to eight days ahead on the plan's weekdays, oldest first.
    public static func slots(around now: Date, plan: CommutePlan, calendar: Calendar) -> [CommuteSlot] {
        guard !plan.weekdays.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        var out: [CommuteSlot] = []
        for offset in -1...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = RouteWeekday(calendarWeekday: calendar.component(.weekday, from: day)),
                  plan.weekdays.contains(weekday) else { continue }
            for direction in CommuteDirection.allCases {
                if let departure = departure(on: day, minute: plan.minute(for: direction), calendar: calendar) {
                    out.append(CommuteSlot(direction: direction, departure: departure))
                }
            }
        }
        return out.sorted { $0.departure < $1.departure }
    }

    /// The wall-clock minute on `day`. In the spring-forward hour (02:00–03:00 does not exist) the next existing time is used.
    public static func departure(on day: Date, minute: Int, calendar: Calendar) -> Date? {
        let m = CommutePlan.clamp(minute)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day, matchingPolicy: .nextTime,
                             repeatedTimePolicy: .first, direction: .forward)
    }

    /// „heute 17:12“, „morgen 07:20“, „Mo 07:20“ – the day word relative to `now`, then the clock time.
    public static func dayText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let clock = CommutePlan.clockText(minuteOfDay(date, calendar: calendar))
        if calendar.isDate(date, inSameDayAs: now) { return "heute \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "morgen \(clock)" }
        let weekday = RouteWeekday(calendarWeekday: calendar.component(.weekday, from: date))?.shortName ?? ""
        return "\(weekday) \(clock)"
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
