import Foundation

// Cockpit-Ansicht, part 7: every German word of the cockpit (docs/RADAR_COCKPIT.md). Pure: numbers in, text out. Du-Form, no technical codes.
// Each line says only what the data says: the speed is "geschätzt", the position is calculated, the age is the age of the last answer.

public enum CockpitText {
    // MARK: Honesty

    /// Under the HUD: where the position comes from.
    public static let positionNote = "Die Position rechnet die Auskunft aus Fahrplan und Echtzeit-Meldungen. Sie ist keine GPS-Ortung."
    /// Under the route when there is no polyline.
    public static let straightLineNote = "Luftlinie zwischen den Halten"
    /// Where the HUD says the speed comes from.
    public static let speedNote = "geschätzt"

    // MARK: Numbers

    /// "12:34" in Vienna.
    public static func clock(_ date: Date) -> String { RealtimePresentation.time(date) }

    /// "in 12 Min", "in 1 Std 05 Min", "gleich". Nothing for a time that is long past.
    public static func countdown(seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > -CockpitSummary.overdueSeconds else { return nil }
        if seconds < 30 { return "gleich" }
        let minutes = max(Int((seconds / 60).rounded()), 1)
        if minutes < 60 { return "in \(minutes) Min" }
        return String(format: "in %d Std %02d Min", minutes / 60, minutes % 60)
    }

    /// The same for VoiceOver: "in 12 Minuten", "in einer Stunde und 5 Minuten".
    public static func spokenCountdown(seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > -CockpitSummary.overdueSeconds else { return nil }
        if seconds < 30 { return "gleich" }
        let minutes = max(Int((seconds / 60).rounded()), 1)
        if minutes < 60 { return minutes == 1 ? "in einer Minute" : "in \(minutes) Minuten" }
        let hours = minutes / 60, rest = minutes % 60
        let hourText = hours == 1 ? "einer Stunde" : "\(hours) Stunden"
        if rest == 0 { return "in \(hourText)" }
        return "in \(hourText) und \(rest == 1 ? "einer Minute" : "\(rest) Minuten")"
    }

    /// The chip next to the arrival: "pünktlich", "+4 min", "−2 min", "Fällt aus", "Keine Echtzeit". The sign is the typographic minus.
    public static func delayChip(seconds: Int?, state: RadarDelayState) -> String {
        if state == .cancelled { return "Fällt aus" }
        guard let seconds else { return "Keine Echtzeit" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes == 0 { return "pünktlich" }
        return minutes > 0 ? "+\(minutes) min" : "\u{2212}\(-minutes) min"
    }

    /// VoiceOver: "pünktlich", "4 Minuten verspätet", "2 Minuten früher", "fällt aus", "ohne Echtzeit-Daten".
    public static func spokenDelay(seconds: Int?, state: RadarDelayState) -> String {
        if state == .cancelled { return "fällt aus" }
        guard let seconds else { return "ohne Echtzeit-Daten" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes == 0 { return "pünktlich" }
        return minutes > 0 ? "\(RealtimePresentation.minutes(minutes)) verspätet" : "\(RealtimePresentation.minutes(-minutes)) früher"
    }

    /// "850 m", "4,3 km", "18 km". Under 50 m: "unter 50 m". The decimal sign is the German comma.
    public static func distance(km: Double) -> String {
        guard km.isFinite else { return "–" }
        let km = max(km, 0)
        if km < 0.05 { return "unter 50 m" }
        if km < 0.95 { return "\(Int((km * 1000 / 50).rounded()) * 50) m" }
        if km < 10 { return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(km.rounded())) km"
    }

    /// VoiceOver: "850 Meter", "4,3 Kilometer", "18 Kilometer".
    public static func spokenDistance(km: Double) -> String {
        guard km.isFinite else { return "unbekannt" }
        let km = max(km, 0)
        if km < 0.05 { return "unter 50 Meter" }
        if km < 0.95 { return "\(Int((km * 1000 / 50).rounded()) * 50) Meter" }
        if km < 10 { return String(format: "%.1f Kilometer", km).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(km.rounded())) Kilometer"
    }

    /// "ca. 118 km/h": the number alone, for the big figure. The words "· geschätzt" follow as a separate line.
    public static func speedValue(kmh: Double) -> String { "ca. \(Int(kmh.rounded())) km/h" }

    /// "ca. 118 km/h · geschätzt"; nil when the train stands or the speed is unknown (nothing is shown then).
    public static func speed(_ reading: CockpitSpeedEstimator.Reading) -> String? {
        guard let kmh = reading.kmh else { return nil }
        return "\(speedValue(kmh: kmh)) · \(speedNote)"
    }

    /// VoiceOver: "etwa 118 Kilometer pro Stunde, geschätzt".
    public static func spokenSpeed(_ reading: CockpitSpeedEstimator.Reading) -> String? {
        guard let kmh = reading.kmh else { return nil }
        return "etwa \(Int(kmh.rounded())) Kilometer pro Stunde, geschätzt"
    }

    /// "Stand vor 12 s", "Stand gerade eben", "Stand vor 2 Min".
    public static func age(_ seconds: TimeInterval) -> String {
        let text = RadarStatusText.age(seconds)
        return "Stand \(text)"
    }

    public static func spokenAge(_ seconds: TimeInterval) -> String { "Stand \(RadarStatusText.spokenAge(seconds))" }

    // MARK: Phase

    /// The line under the big stop name: what the train is doing.
    public static func phaseLine(_ summary: CockpitSummary) -> String {
        switch summary.phase {
        case .beforeDeparture(let stop, let departure):
            return departure.map { "Steht in \(stop) · Abfahrt \(clock($0))" } ?? "Steht in \(stop)"
        case .atStop(let stop, let departure):
            return departure.map { "Hält in \(stop) · weiter um \(clock($0))" } ?? "Hält in \(stop)"
        case .underway:
            return "Unterwegs"
        case .arrived(let stop):
            return "Am Ziel in \(stop)"
        case .cancelled:
            return "Dieser Zug fällt aus"
        }
    }

    /// The small label over the stop name: "Nächster Halt", "Ziel erreicht".
    public static func stopLabel(_ summary: CockpitSummary) -> String {
        switch summary.phase {
        case .arrived: return "Ziel erreicht"
        case .cancelled: return "Fällt aus"
        default: return summary.nextIsFinal ? "Ziel" : "Nächster Halt"
        }
    }

    // MARK: Link

    public static let endedTitle = "Fahrt beendet"

    /// "Der Zug hat Linz Hbf erreicht." / "Die Fahrt ist laut Fahrplan zu Ende."
    public static func endedDetail(lastStop: String?, reachedLastStop: Bool) -> String {
        if reachedLastStop, let lastStop { return "Der Zug hat \(lastStop) erreicht." }
        return "Die Fahrt ist laut Fahrplan zu Ende."
    }

    public static let lostTitle = "Keine Position mehr"

    /// Why, and since when. `sinceSeconds`: the age of the last position.
    public static func lostDetail(reason: CockpitSession.LostReason, sinceSeconds: TimeInterval?) -> String {
        let since = sinceSeconds.map { " Zuletzt gesehen \(RadarStatusText.age($0))." } ?? ""
        switch reason {
        case .noAnswers: return "Keine Verbindung zu ÖBB.\(since)"
        case .notListed: return "Die Auskunft meldet den Zug gerade nicht.\(since)"
        }
    }

    public static let waitingTitle = "Suche den Zug …"
    public static let waitingDetail = "Die erste Position kommt gleich."

    // MARK: Whole HUD

    /// One sentence for VoiceOver: the HUD as a single element.
    public static func spoken(_ summary: CockpitSummary, now: Date) -> String {
        var parts = [summary.lineTitle]
        if let destination = summary.destination { parts[0] += " nach \(destination)" }
        switch summary.phase {
        case .cancelled:
            parts.append("fällt aus")
        case .arrived(let stop):
            parts.append("Ziel erreicht: \(stop)")
        case .beforeDeparture(let stop, let departure):
            parts.append("steht in \(stop)" + (departure.map { ", Abfahrt \(clock($0)) Uhr" } ?? ""))
        case .atStop(let stop, let departure):
            parts.append("hält in \(stop)" + (departure.map { ", weiter um \(clock($0)) Uhr" } ?? ""))
        case .underway:
            break
        }
        if let next = summary.nextStop {
            var line = "Nächster Halt \(next)"
            if let platform = summary.platform { line += ", \(platform.spoken)" }
            parts.append(line)
            if let eta = summary.eta {
                var arrival = "Ankunft \(clock(eta)) Uhr, \(spokenDelay(seconds: summary.delaySeconds, state: summary.delayState))"
                if summary.showsCountdown(now: now), let seconds = summary.secondsToArrival(now: now), let spoken = spokenCountdown(seconds: seconds) {
                    arrival += ", \(spoken)"
                }
                parts.append(arrival)
            }
            if let km = summary.distanceKm { parts.append("noch \(spokenDistance(km: km))") }
        }
        parts.append("\(Int((summary.progress * 100).rounded())) Prozent der Strecke")
        if let speed = spokenSpeed(summary.speed) { parts.append(speed) }
        if let age = summary.fixAge { parts.append(spokenAge(age)) }
        return parts.joined(separator: ". ") + "."
    }

    /// The text of "Teilen": line, next stop, expected arrival. No coordinates, no trip id.
    public static func share(_ summary: CockpitSummary) -> String {
        var line = summary.lineTitle
        if let destination = summary.destination { line += " nach \(destination)" }
        switch summary.phase {
        case .cancelled: return "\(line) fällt aus."
        case .arrived(let stop): return "\(line) hat \(stop) erreicht."
        default: break
        }
        guard let next = summary.nextStop else { return line }
        var text = "\(line): nächster Halt \(next)"
        if let eta = summary.eta {
            text += ", Ankunft \(clock(eta))"
            if summary.delayState != .unknown, summary.delayState != .cancelled {
                let chip = delayChip(seconds: summary.delaySeconds, state: summary.delayState)
                text += " (\(chip))"
            }
        }
        return text + ". Live verfolgt mit KlimaBilanz."
    }
}
