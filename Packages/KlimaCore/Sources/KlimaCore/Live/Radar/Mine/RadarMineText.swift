import Foundation

// MARK: radar2-radarmine – every word of „Meine Fahrzeuge“ (docs/RADAR_MINE.md §9). The radar's honesty rules (specs radar2 README §7): positions are
// „berechnet“ by the ÖBB-Auskunft, never GPS; an empty list says what the Auskunft knows, never that nothing runs; times in Europe/Vienna, 24 hours;
// „Min“ in rows, „Minuten“ for VoiceOver; „1,2 km“ with a comma. Du-Form.

public enum RadarMineText {
    // MARK: Entry and panel

    public static let chip = "Meine"
    public static let chipSymbol = "star"
    public static let chipSpoken = "Meine Fahrzeuge"
    public static let panelTitle = "Meine Fahrzeuge"
    public static let close = "Schließen"
    public static let menu = "Mehr"
    public static let deleteLines = "Alle gemerkten Linien löschen"
    public static let deleteLinesQuestion = "Gemerkte Linien löschen?"
    public static let deleteStops = "Zuletzt gewählte Haltestellen löschen"
    public static let deleteStopsQuestion = "Zuletzt gewählte Haltestellen löschen?"
    public static let delete = "Löschen"
    public static let cancel = "Abbrechen"

    public enum Page: String, CaseIterable, Sendable, Hashable, Identifiable {
        case lines, near, stop
        public var id: Self { self }
        public var title: String {
            switch self {
            case .lines: "Linien"
            case .near: "In der Nähe"
            case .stop: "Haltestelle"
            }
        }
        public var symbol: String {
            switch self {
            case .lines: "star"
            case .near: "location"
            case .stop: "clock"
            }
        }
    }

    // MARK: Trip sheet row

    public static let remember = "Linie merken"
    public static let remembered = "Gemerkt"
    public static func rememberSpoken(_ title: String) -> String { "Linie \(title) merken" }
    public static func rememberedSpoken(_ title: String) -> String { "\(title) ist gemerkt. Doppeltippen zum Entfernen." }
    public static func rememberedToast(_ title: String) -> String { "\(title) gemerkt" }
    public static func forgottenToast(_ title: String) -> String { "\(title) nicht mehr gemerkt" }
    public static let full = "Du kannst bis zu \(RadarMineLines.capacity) Linien merken. Entferne zuerst eine."
    public static let trainFootnote = "Die gleiche Zugnummer kann an anderen Tagen anders fahren."

    // MARK: Linien

    public static let linesEmpty = "Noch keine Linie gemerkt. Tipp auf ein Fahrzeug und dann auf „Linie merken“."
    /// „3 unterwegs in den geladenen Gebieten“.
    public static func running(_ count: Int) -> String { "\(count) unterwegs in den geladenen Gebieten" }
    public static let noneLoaded = "Gerade keine in den geladenen Gebieten. Die Auskunft kennt nur, was in den geladenen Gebieten fährt."
    public static let toArea = "Zur gemerkten Gegend"
    /// The line's mode chip is off: the radar does not ask for it.
    public static func modeOff(_ mode: RadarMode) -> String { "„\(mode.title)“ ist oben ausgeschaltet. Das Radar fragt diese Linie gerade nicht ab." }
    public static let switchOn = "Einschalten"
    public static let highlight = "Nur meine Linien hervorheben"
    public static let highlightFooter = "Andere Fahrzeuge treten zurück, deine Linien bekommen einen Stern."
    public static let linesFooter = "Gemerkt wird nur der Linienname und grob die Gegend, auf diesem iPhone."
    public static let showOnMap = "Auf der Karte zeigen"
    public static let forget = "Nicht mehr merken"

    /// „Nächster: Richtung Hütteldorf · Westbahnhof in 3 Min (+1)“, „… Westbahnhof in 3 Min laut Fahrplan“, „… fällt aus“.
    public static func nextVehicle(direction: String?, stop: String, eta: RadarMineETA, now: Date) -> String {
        var text = "Nächster: "
        if let direction, !direction.isEmpty { text += "Richtung \(direction) · " }
        return text + stopETA(stop: stop, eta: eta, now: now)
    }

    /// „Westbahnhof in 3 Min (+1)“, „Westbahnhof in 3 Min laut Fahrplan“, „Westbahnhof · fällt aus“.
    public static func stopETA(stop: String, eta: RadarMineETA, now: Date) -> String {
        if eta.isCancelled { return "\(stop) · fällt aus" }
        let base = "\(stop) \(minutesText(eta.minutes(from: now)))"
        guard eta.isRealtime else { return base + " laut Fahrplan" }
        return base + delaySuffix(eta.delayMinutes)
    }

    /// The row's sentence for VoiceOver.
    public static func lineSpoken(title: String, running: Int, next: String?) -> String {
        guard running > 0 else { return "\(title). \(noneLoaded)" }
        return [title, self.running(running), next].compactMap { $0 }.joined(separator: ". ")
    }

    // MARK: In der Nähe

    public static let nearIntro = "Zeigt Fahrzeuge im Umkreis von 1,5 km. Dein Standort bleibt auf dem iPhone. Das Radar lädt dann die Kartenausschnitte rund um dich, wie beim Verschieben der Karte – daran sieht die ÖBB-Auskunft grob die Gegend."
    public static let nearButton = "In meiner Nähe zeigen"
    public static let locating = "Suche deinen Standort …"
    public static let loadingNear = "Lade Fahrzeuge in deiner Nähe …"
    public static let cityOff = "Bus, Bim und U-Bahn sind aus."
    public static let nearEmpty = "Die Auskunft kennt im Umkreis von 1,5 km gerade kein Fahrzeug."
    public static let nearEmptyFiltered = "Die Auskunft kennt im Umkreis von 1,5 km gerade keines, das zum Filter passt."
    public static let denied = "Ohne Standort geht das nicht. Du kannst die Karte selbst verschieben oder eine Haltestelle wählen."
    public static let openSettings = "Einstellungen öffnen"
    public static let noFix = "Dein Standort kam gerade nicht. Versuch es gleich noch einmal."
    public static let retry = "Erneut versuchen"
    public static let relocate = "Neu orten"
    /// The dot of the invented place in demo and screenshot launches (VoiceOver).
    public static let demoPlace = "Ort der Vorschau, erfunden"
    public static let nearFooter = "Dein Standort bleibt auf dem iPhone und wird nicht gespeichert. Die Positionen sind berechnet, kein GPS."
    // MARK: radar2-review-radarmine – the list says what it covers (`RadarNearby.Coverage`): „kennt kein Fahrzeug“ only for the whole, loaded circle
    /// The map no longer shows the whole circle.
    public static let nearOffMap = "Die Karte zeigt gerade nicht den ganzen Umkreis. Die Liste nennt nur, was dort zu sehen ist."
    /// Back to the circle around the fix.
    public static let toCircle = "Zum Umkreis"
    /// The radar loads nothing now (train layer off, no live data, Zeitreise, Cockpit, Low Power Mode, paused).
    public static let nearNotLoading = "Das Radar lädt gerade nichts nach. Die Liste nennt nur, was schon geladen ist."

    /// „Bus 13A → Hauptbahnhof“.
    public static func vehicleTitle(_ title: String, direction: String?) -> String {
        guard let direction, !direction.isEmpty else { return title }
        return "\(title) → \(direction)"
    }

    /// „240 m · nächster Halt Neubaugasse in 2 Min (+1)“.
    public static func nearDetail(_ row: RadarNearbyRow, now: Date) -> String {
        "\(distance(row.distanceKm)) · nächster Halt \(stopETA(stop: row.nextStop, eta: row.eta, now: now))"
    }

    /// „Bus 13A nach Hauptbahnhof, 240 Meter entfernt, nächster Halt Neubaugasse in 2 Minuten, 1 Minute verspätet, Position berechnet“.
    public static func nearSpoken(_ row: RadarNearbyRow, now: Date) -> String {
        var parts = [spokenLine(row.line, title: row.title)]
        if let direction = row.direction, !direction.isEmpty { parts[0] += " nach \(direction)" }
        parts.append("\(spokenDistance(row.distanceKm)) entfernt")
        if row.eta.isCancelled {
            parts.append("fällt aus")
        } else {
            parts.append("nächster Halt \(row.nextStop) \(spokenMinutes(row.eta.minutes(from: now)))")
            parts.append(spokenDelay(row.eta))
        }
        parts.append(row.isEstimate ? "Position geschätzt" : "Position berechnet")
        return parts.joined(separator: ", ")
    }

    // MARK: Haltestelle

    public static let stopSearch = "Haltestelle suchen"
    public static let stopSearchEmpty = "Keine Haltestelle mit diesem Namen."
    public static func mapCentre(_ name: String) -> String { "Kartenmitte: \(name)" }
    public static func nearYou(_ name: String) -> String { "In der Nähe: \(name)" }
    public static let recent = "Zuletzt"
    public static let chooseStop = "Wähl eine Haltestelle, dann zeigt das Radar, wo ihre nächsten Abfahrten gerade sind."
    public static let otherStop = "Andere Haltestelle"
    /// The short button beside the stop's name (VoiceOver says `otherStop`).
    public static let changeStop = "Ändern"
    public static func from(_ name: String) -> String { "Ab \(name)" }
    public static let loadingBoard = "Lade Abfahrten …"
    public static let stopEmpty = "Die Auskunft kennt für die nächsten 30 Minuten keine Abfahrt ab hier."
    public static let stopFooter = "Abfahrten und Positionen laut ÖBB-Auskunft. Die Positionen sind berechnet, kein GPS. Die Linie zur Haltestelle ist die Luftlinie."
    /// Board and radar trip ids were never compared live (docs/RADAR_MINE.md §7): the same vehicle can show twice.
    public static let maybeTwice = "Ein Fahrzeug kann zweimal erscheinen: einmal vom Radar, einmal von der Abfahrtstafel."
    public static let allDepartures = "Alle Abfahrten"
    public static let unknownStop = "Diese Haltestelle findet die Auskunft nicht. Wähl bitte eine andere."
    public static let pausedTime = "Pausiert, solange die Zeitreise eine andere Zeit zeigt."
    public static let pausedCockpit = "Pausiert, solange das Cockpit offen ist."
    public static let pausedLowPower = "Stromspar-Modus: Die Abfahrten werden nicht aktualisiert."
    public static let refreshNow = "Jetzt aktualisieren"
    public static let pausedIdle = "Pausiert. Tippe zum Aktualisieren."
    public static let pausedTrainsOff = "Die Ebene „Züge“ ist aus. Ohne sie fragt das Radar keine Abfahrten ab."
    public static let needsLive = "Für Abfahrten braucht es Live-Daten."
    public static let settings = "Einstellungen"
    public static let offline = "Ohne Internet gibt es keine Abfahrten."
    /// MARK: radar2-review-radarmine – the whole radar pauses (rate limit, open circuit, failures): the board waits with it.
    public static let radarPaused = "Das Radar pausiert gerade – die Abfahrten auch, bis es weiterlädt."
    /// A row's mode chip is off: it stays in the list without a number on the map.
    public static func modesOffMap(_ modes: [RadarMode]) -> String {
        "\(RadarModesText.names(modes)) \(modes.count == 1 ? "ist" : "sind") aus – diese Abfahrten stehen in der Liste, aber nicht auf der Karte."
    }

    /// MARK: radar2-review-radarmine – a row's mode is on, but the map is too far out for it (the city lane): it is not „aus“.
    public static func modesOutOfZoom(_ modes: [RadarMode]) -> String {
        "\(RadarModesText.names(modes)) \(modes.count == 1 ? "erscheint" : "erscheinen") auf der Karte, wenn du näher heranzoomst – diese Abfahrten stehen schon in der Liste."
    }

    /// The pause line of the stop page; nil while it asks.
    public static func pause(_ pause: RadarStopPause?, idle: Bool) -> String? {
        switch pause {
        case nil, .panelClosed?: return idle ? pausedIdle : nil
        case .accessClosed?: return needsLive
        case .offline?: return offline
        case .trainsOff?: return pausedTrainsOff
        case .timeAway?: return pausedTime
        case .cockpit?: return pausedCockpit
        case .background?: return nil
        case .lowPower?: return pausedLowPower
        }
    }

    /// „Stand 14:32“.
    public static func stand(_ date: Date) -> String { "Stand \(RealtimePresentation.time(date))" }

    /// „in 4 Min“, „jetzt“.
    public static func minutesText(_ minutes: Int) -> String { minutes <= 0 ? "jetzt" : "in \(minutes) Min" }
    /// „in 4 Minuten“, „in 1 Minute“, „jetzt“.
    public static func spokenMinutes(_ minutes: Int) -> String {
        minutes <= 0 ? "jetzt" : (minutes == 1 ? "in 1 Minute" : "in \(minutes) Minuten")
    }

    /// The departure line of a stop row: „ab 14:36 · Steig 2“.
    public static func departure(_ arrival: RadarStopArrival) -> String {
        var text = "ab \(arrival.row.time)"
        if let platform = arrival.platform { text += " · \(platform)" }
        return text
    }

    /// The delay chip of a stop row: „+1“, „pünktlich“, „laut Fahrplan“, „fällt aus“.
    public static func delayChip(_ eta: RadarMineETA?) -> String {
        guard let eta else { return "laut Fahrplan" }
        if eta.isCancelled { return "fällt aus" }
        guard eta.isRealtime, let minutes = eta.delayMinutes else { return "laut Fahrplan" }
        if minutes == 0 { return "pünktlich" }
        return minutes > 0 ? "+\(minutes)" : "−\(-minutes)"
    }

    /// „noch 1,2 km“, „an der Haltestelle“, „Position unbekannt“.
    public static func position(_ position: RadarStopArrival.Position) -> String {
        switch position {
        case .atStop: "an der Haltestelle"
        case .away(let km): "noch \(distance(km))"
        case .unknown: "Position unbekannt"
        }
    }

    /// „Position von vor 3 Min“ (older than two minutes).
    public static func positionAge(_ seconds: TimeInterval) -> String {
        "Position von \(RadarStatusText.age(seconds))"
    }

    /// „Bus 13A nach Hauptbahnhof, ab 14 Uhr 36, in 4 Minuten, 1 Minute verspätet, Steig 2, noch 1,2 Kilometer entfernt, Position berechnet“.
    public static func arrivalSpoken(_ arrival: RadarStopArrival, number: Int?, now: Date) -> String {
        var first = spokenLine(arrival.line, title: arrival.row.lineTitle.isEmpty ? "Fahrzeug" : arrival.row.lineTitle)
        // The destination as the Auskunft writes it („Hauptbahnhof“), not the row's short form („Hbf“), for VoiceOver.
        if !arrival.row.destination.raw.isEmpty { first += " nach \(arrival.row.destination.raw)" }
        var parts = [first]
        if let planned = arrival.planned { parts.append("ab \(RadarTimeText.spokenClock(planned))") }
        if arrival.isCancelled {
            parts.append("fällt aus")
        } else if let eta = arrival.eta {
            parts.append(spokenMinutes(eta.minutes(from: now)))
            parts.append(spokenDelay(eta))
        }
        if let platform = arrival.platform { parts.append(platform) }
        switch arrival.position {
        case .atStop: parts.append("an der Haltestelle, Position berechnet")
        case .away(let km): parts.append("noch \(spokenDistance(km)) entfernt, Position berechnet")
        case .unknown: parts.append("Position unbekannt")
        }
        if let at = arrival.positionAt, RadarStopArrivals.isStale(at, now: now) {
            parts.append("Position \(RadarStatusText.spokenAge(now.timeIntervalSince(at)))")
        }
        if let number { parts.append("Nummer \(number) auf der Karte") }
        return parts.joined(separator: ", ")
    }

    // MARK: Map markers

    /// MARK: radar2-review-radarmine – what VoiceOver adds to a vehicle marker that „Meine Fahrzeuge“ marks (the star, the number and the dimmed rest
    /// are drawn only): „deine Linie“, „Nummer 2 der Abfahrten“, „nicht hervorgehoben“; empty for an unmarked marker.
    public static func markerValue(star: Bool, number: Int?, dimmed: Bool) -> String {
        if let number { return "Nummer \(number) der Abfahrten" }
        if star { return "deine Linie" }
        return dimmed ? "nicht hervorgehoben" : ""
    }

    /// MARK: radar2-review-radarmine – a group of markers that holds a vehicle of your lines (beyond the 60 single ones): the ring gets the star, and
    /// VoiceOver hears it.
    public static let groupValue = "mit deiner Linie"

    // MARK: Units

    /// „240 m“ (to 10 m) below a kilometre, „1,2 km“ below ten, „12 km“ above.
    public static func distance(_ km: Double) -> String {
        guard km.isFinite, km >= 0 else { return "–" }
        if km < 0.995 { return "\(max(Int((km * 100).rounded()) * 10, 10)) m" }
        if km < 9.95 { return "\(decimal(km)) km" }
        return "\(Int(km.rounded())) km"
    }

    /// „240 Meter“, „1,2 Kilometer“, „1 Kilometer“.
    public static func spokenDistance(_ km: Double) -> String {
        guard km.isFinite, km >= 0 else { return "unbekannt weit" }
        if km < 0.995 { return "\(max(Int((km * 100).rounded()) * 10, 10)) Meter" }
        if km < 9.95 {
            let text = decimal(km)
            return text == "1" ? "1 Kilometer" : "\(text) Kilometer"
        }
        return "\(Int(km.rounded())) Kilometer"
    }

    /// One decimal with a comma, without „,0“: „1,2“, „3“.
    static func decimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10),\(tenths % 10)"
    }

    /// „ (+1)“ after a time; nothing on time or without realtime; „ (−1)“ early.
    static func delaySuffix(_ minutes: Int?) -> String {
        guard let minutes, minutes != 0 else { return "" }
        return minutes > 0 ? " (+\(minutes))" : " (−\(-minutes))"
    }

    /// „1 Minute verspätet“, „pünktlich“, „laut Fahrplan“.
    static func spokenDelay(_ eta: RadarMineETA) -> String {
        guard eta.isRealtime, let minutes = eta.delayMinutes else { return "laut Fahrplan" }
        if minutes == 0 { return "pünktlich" }
        if minutes < 0 { return minutes == -1 ? "1 Minute früher" : "\(-minutes) Minuten früher" }
        return minutes == 1 ? "1 Minute verspätet" : "\(minutes) Minuten verspätet"
    }

    static func spokenLine(_ line: Line?, title: String) -> String {
        guard let line else { return title }
        return RadarModesText.spokenLine(title: title, kind: LinePresentation.kind(line))
    }
}
