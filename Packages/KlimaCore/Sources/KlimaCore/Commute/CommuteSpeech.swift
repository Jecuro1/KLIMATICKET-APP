import Foundation

// Pendel-Modus (docs/COMMUTE.md §6): what Siri says for „Wann fährt mein nächster Zug?“ – one or two short German sentences,
// built from the rows the card fetched while the app was open, or from the plan. Never a promise the data cannot keep: rows
// without realtime say „laut Fahrplan“, and the answer always carries the time of the data („Stand 07:31“).

public enum CommuteSpeech {
    /// Why there is no live answer – the last sentence of a planned answer.
    public enum LiveHint: Sendable, Hashable {
        /// Live data is on, but nothing fresh is cached: the app fetches when it is opened.
        case openApp
        /// Live data is off (no consent or switched off).
        case liveOff
        /// No hint.
        case none
    }

    /// „1 Minute“, „5 Minuten“.
    public static func minutes(_ n: Int) -> String { n == 1 ? "1 Minute" : "\(n) Minuten" }

    /// „pünktlich“, „1 Minute verspätet“, „5 Minuten verspätet“, „2 Minuten früher“.
    public static func delayPhrase(_ delay: Int) -> String {
        if delay == 0 { return "pünktlich" }
        return delay > 0 ? "\(minutes(delay)) verspätet" : "\(minutes(-delay)) früher"
    }

    /// The answer from fetched rows (the card's last search): the next connection with its delay and platform, a cancelled
    /// or very late one with the alternative of the same search, then „Stand 07:31.“. nil without rows.
    public static func next(rows: [CommuteRow], destination: String, fetchedAt: Date?, now: Date) -> String? {
        guard let first = rows.first else { return nil }
        var text: String
        if first.isCancelled {
            text = "\(CommuteAdvisor.yourVehicle(first.mode)) um \(first.timeText) nach \(destination) fällt aus."
        } else if let delay = first.delayMinutes {
            text = "\(nextVehicle(first.mode)) nach \(destination) fährt um \(first.timeText), \(delayPhrase(delay))\(platformPart(first))."
        } else {
            text = "\(nextVehicle(first.mode)) nach \(destination) fährt laut Fahrplan um \(first.timeText)\(platformPart(first))."
        }
        if let advice = CommuteAdvisor.advice(rows: rows, now: now) {
            if let alternative = advice.alternative {
                let lead = advice.reason == .cancelled ? "Die nächste Verbindung fährt" : "Schneller ist die Verbindung"
                text += " \(lead) um \(alternative.timeText)\(alternative.delayMinutes.map { $0 > 0 ? ", \(delayPhrase($0))" : "" } ?? "")\(platformPart(alternative))."
            } else if advice.reason == .cancelled {
                text += " In der letzten Abfrage gab es keine weitere Verbindung."
            }
        }
        if let fetchedAt { text += " Stand \(RealtimePresentation.time(fetchedAt))." }
        return text
    }

    /// The answer from the plan alone: „Laut deinem Plan fährst du heute um 17:12 von Innsbruck nach St. Anton.“ plus the hint.
    public static func planned(slot: CommuteSlot, origin: String, destination: String, now: Date, calendar: Calendar,
                               hint: LiveHint) -> String {
        let from = slot.direction == .outbound ? origin : destination
        let to = slot.direction == .outbound ? destination : origin
        let when = CommuteWindow.dayText(slot.departure, now: now, calendar: calendar)
        let day = spokenDay(when)
        var text = "Laut deinem Plan fährst du \(day) von \(from) nach \(to)."
        switch hint {
        case .openApp: text += " Verspätungen siehst du, wenn du KlimaBilanz öffnest."
        case .liveOff: text += " Live-Daten sind ausgeschaltet, deshalb kenne ich keine Verspätungen."
        case .none: break
        }
        return text
    }

    public static let notSetUp = "Du hast noch keine Stammstrecke. Richte sie in KlimaBilanz unter Einstellungen bei „Pendeln“ ein."
    public static let noWeekday = "Für deine Stammstrecke ist kein Wochentag gewählt."

    /// „heute 17:12“ → „heute um 17:12“, „Mo 07:20“ → „am Montag um 07:20“.
    static func spokenDay(_ dayText: String) -> String {
        let parts = dayText.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return dayText }
        let names = ["Mo": "Montag", "Di": "Dienstag", "Mi": "Mittwoch", "Do": "Donnerstag", "Fr": "Freitag", "Sa": "Samstag", "So": "Sonntag"]
        if let name = names[parts[0]] { return "am \(name) um \(parts[1])" }
        return "\(parts[0]) um \(parts[1])"
    }

    /// „Dein nächster Zug“, „Deine nächste Bim“, „Dein nächstes Schiff“.
    static func nextVehicle(_ mode: TransportMode) -> String {
        switch mode {
        case .bus: "Dein nächster Bus"
        case .tram: "Deine nächste Bim"
        case .ferry: "Dein nächstes Schiff"
        case .cableCar: "Deine nächste Gondel"
        default: "Dein nächster Zug"
        }
    }

    /// „, von Gleis 4“ · „, von Steig B“ · „“.
    static func platformPart(_ row: CommuteRow) -> String {
        guard let platform = row.platform else { return "" }
        return ", von \(platform.spoken)"
    }
}
