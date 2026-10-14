import Foundation

/// Text and calendar export of a connection (docs/PLANNER.md §Teilen, §Kalender). Pure: the app writes the files and
/// opens the share sheet. The German date text is built here, so it does not depend on the device locale.
public enum PlannerExport {
    /// „Innsbruck Hbf → Landeck-Zams · Do, 15. Okt., 08:12–09:30 · 1 Umstieg · RJX 19910 · Bus 760“
    public static func shareText(_ journey: Journey) -> String {
        let from = journey.origin.map { DisplayNames.name($0.name) } ?? ""
        let to = journey.destination.map { DisplayNames.name($0.name) } ?? ""
        var parts = ["\(from) → \(to)"]
        if let start = journey.departure?.effective {
            var when = "\(dayText(start)), \(timeText(start))"
            if let end = journey.arrival?.effective { when += "–\(timeText(end))" }
            parts.append(when)
        }
        parts.append(changesText(journey.changes))
        let lines = LinePresentation.lineSummary(journey.rideLegs.compactMap(\.line))
        if !lines.isEmpty { parts.append(lines) }
        let walk = PlannerResults.walkMeters(journey)
        if walk > 0 { parts.append("Fußweg \(walk) m") }
        return parts.joined(separator: " · ")
    }

    /// One-event iCalendar (RFC 5545) of the connection with a display alarm `alarmMinutes` before the departure.
    /// nil without planned departure and arrival. Lines are CRLF, long lines are folded at 75 octets.
    public static func ics(_ journey: Journey, uid: String, stamp: Date, alarmMinutes: Int? = 10) -> String? {
        guard let start = journey.departure?.effective, let end = journey.arrival?.effective else { return nil }
        let from = journey.origin.map { DisplayNames.name($0.name) } ?? ""
        let to = journey.destination.map { DisplayNames.name($0.name) } ?? ""
        var description: [String] = []
        for leg in journey.legs {
            switch leg.kind {
            case .ride:
                let name = leg.line.map(LinePresentation.title) ?? "Fahrt"
                let dep = leg.departure.effective.map(timeText) ?? "", arr = leg.arrival.effective.map(timeText) ?? ""
                description.append("\(dep) \(DisplayNames.name(leg.origin.name)) → \(arr) \(DisplayNames.name(leg.destination.name)) (\(name))")
            case .walk, .transfer:
                let meters = leg.walkDistanceMeters.map { " (\($0) m)" } ?? ""
                description.append("Fußweg\(meters) in \(DisplayNames.name(leg.origin.name))")
            }
        }
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//KlimaBilanz//Fahrplan//DE", "CALSCALE:GREGORIAN", "BEGIN:VEVENT",
            "UID:\(uid)", "DTSTAMP:\(utcStamp(stamp))", "DTSTART:\(utcStamp(start))", "DTEND:\(utcStamp(end))",
            "SUMMARY:\(escape("\(from) → \(to)"))", "LOCATION:\(escape(from))",
            "DESCRIPTION:\(escape(description.joined(separator: "\n")))",
        ]
        if let alarmMinutes, alarmMinutes > 0 {
            lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape("Abfahrt in \(alarmMinutes) Min"))",
                      "TRIGGER:-PT\(alarmMinutes)M", "END:VALARM"]
        }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// File name of the .ics file, without characters a file system dislikes.
    public static func icsFileName(_ journey: Journey) -> String {
        let from = journey.origin.map { DisplayNames.name($0.name) } ?? "Fahrt"
        let to = journey.destination.map { DisplayNames.name($0.name) } ?? ""
        let raw = "Fahrt \(from) nach \(to).ics"
        return String(raw.map { "/:\\?*\"<>|".contains($0) ? "-" : $0 })
    }

    // MARK: - Text pieces

    static func changesText(_ changes: Int) -> String {
        switch changes {
        case ...0: "direkt"
        case 1: "1 Umstieg"
        default: "\(changes) Umstiege"
        }
    }

    /// „Do, 15. Okt.“ in Vienna time.
    static func dayText(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.weekday, .day, .month], from: date)
        let weekday = weekdays[max(0, min(6, (c.weekday ?? 1) - 1))]
        let month = months[max(0, min(11, (c.month ?? 1) - 1))]
        return "\(weekday), \(c.day ?? 0). \(month)"
    }

    /// „08:12“ in Vienna time.
    static func timeText(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.hour, .minute], from: date)
        return "\(pad(c.hour ?? 0, 2)):\(pad(c.minute ?? 0, 2))"
    }

    static let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let months = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// `20261015T061200Z`.
    static func utcStamp(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return "\(pad(c.year ?? 0, 4))\(pad(c.month ?? 0, 2))\(pad(c.day ?? 0, 2))T\(pad(c.hour ?? 0, 2))\(pad(c.minute ?? 0, 2))\(pad(c.second ?? 0, 2))Z"
    }

    /// RFC 5545 text escaping: backslash, comma, semicolon and newline.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Folds a content line at 75 octets; continuation lines start with a space and never split a character.
    static func fold(_ line: String) -> String {
        var out = ""
        var octets = 0
        for character in line {
            let size = String(character).utf8.count
            if octets + size > 75 {
                out += "\r\n "
                octets = 1
            }
            out.append(character)
            octets += size
        }
        return out
    }
}
