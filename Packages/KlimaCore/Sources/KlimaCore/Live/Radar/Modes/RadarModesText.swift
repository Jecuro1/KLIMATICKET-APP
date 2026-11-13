import Foundation

// MARK: radarmodes – every visible string of the radar's modes, lanes, counts, legend and notes (docs/RADAR_MODES.md §9). Honest words only: the
// positions are calculated by the ÖBB-Auskunft („berechnet“), never GPS; an empty map means the Auskunft knows no vehicle there, never that
// nothing runs.

public enum RadarModesText {
    // MARK: Nouns

    /// The label of a mode in the counts line and the legend ("Zug", "S-Bahn", "Bus", "Bim", "U-Bahn"; nil: "Andere").
    public static func label(_ mode: RadarMode?) -> String {
        guard let mode else { return "Andere" }
        switch mode {
        case .rail: return "Zug"
        case .suburban: return "S-Bahn"
        case .bus: return "Bus"
        case .tram: return "Bim"
        case .subway: return "U-Bahn"
        }
    }

    /// "1 Zug", "21 Züge", "1 Bus", "180 Busse", "3 andere Fahrzeuge", "1 anderes Fahrzeug".
    public static func counted(_ count: Int, _ mode: RadarMode?) -> String {
        "\(count) \(count == 1 ? singular(mode) : plural(mode))"
    }

    public static func singular(_ mode: RadarMode?) -> String {
        mode == nil ? "anderes Fahrzeug" : label(mode)
    }

    public static func plural(_ mode: RadarMode?) -> String {
        guard let mode else { return "andere Fahrzeuge" }
        switch mode {
        case .rail: return "Züge"
        case .suburban: return "S-Bahnen"
        case .bus: return "Busse"
        case .tram: return "Bims"
        case .subway: return "U-Bahnen"
        }
    }

    /// "Bus", "Bus und Bim", "Bus, Bim und U-Bahn": the chip titles of the city modes that are on.
    public static func names(_ modes: [RadarMode]) -> String {
        list(modes.map(\.title))
    }

    /// "Busse und Bims", "Busse, Bims und U-Bahnen".
    public static func pluralNames(_ modes: [RadarMode]) -> String {
        list(modes.map { plural($0) })
    }

    static func list(_ words: [String]) -> String {
        switch words.count {
        case 0: return ""
        case 1: return words[0]
        default: return words.dropLast().joined(separator: ", ") + " und " + words[words.count - 1]
        }
    }

    // MARK: Chips

    /// The VoiceOver value of a mode chip: „an“, „aus“, or for a city mode out of zoom „an, erscheint beim Heranzoomen“.
    public static func chipValue(isOn: Bool, outOfZoom: Bool) -> String {
        guard isOn else { return "aus" }
        return outOfZoom ? "an, erscheint beim Heranzoomen" : "an"
    }

    /// The footer of the Verkehrsmittel section; the km figure follows the span limit (0.6° → 67 km).
    public static func modesFooter(limit: Double = RadarLanePlan.citySpanLimit) -> String {
        "Das Radar fragt jedes eingeschaltete Verkehrsmittel bei der ÖBB-Auskunft ab. Bus, Bim und U-Bahn kommen erst, wenn die Karte höchstens " +
            "etwa \(RadarLanePlan.cityLimitKilometres(limit)) km hoch ist. Mindestens eins bleibt an."
    }

    // MARK: Notes

    /// „Bus, Bim und U-Bahn erscheinen, wenn du näher heranzoomst.“ – „Bus erscheint, …“ for one mode.
    public static func zoomHint(_ modes: [RadarMode]) -> String {
        "\(names(modes)) \(modes.count == 1 ? "erscheint" : "erscheinen"), wenn du näher heranzoomst."
    }

    /// „Bus, Bim und U-Bahn: 4 von 9 Gebieten geladen.“
    public static func loading(_ modes: [RadarMode], answered: Int, of total: Int) -> String {
        "\(names(modes)): \(answered) von \(total) \(total == 1 ? "Gebiet" : "Gebieten") geladen."
    }

    /// „Für alle Busse und Bims hier bräuchte das Radar mehr Abfragen, als es senden darf. Ein Teil fehlt. Zoom näher heran.“
    public static func crowded(_ modes: [RadarMode]) -> String {
        "Für alle \(pluralNames(modes)) hier bräuchte das Radar mehr Abfragen, als es senden darf. Ein Teil fehlt. Zoom näher heran."
    }

    /// „In 2 kleinen Gebieten fahren mehr Fahrzeuge, als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte.“
    public static func cityCapped(_ tiles: Int) -> String {
        let where_ = tiles == 1 ? "In einem kleinen Gebiet" : "In \(tiles) kleinen Gebieten"
        return "\(where_) fahren mehr Fahrzeuge, als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte."
    }

    /// „Bus, Bim und U-Bahn: etwa 12 MB pro Minute (geschätzt).“
    public static func dataEstimate(_ modes: [RadarMode], megabytes: Int) -> String {
        "\(names(modes)): etwa \(megabytes) MB pro Minute (geschätzt)."
    }

    /// „Über mobile Daten kommen Bus, Bim und U-Bahn alle 60 s.“
    public static func metered(_ modes: [RadarMode], seconds: Int = Int(RadarLanePlan.cityIntervalMetered)) -> String {
        "Über mobile Daten \(modes.count == 1 ? "kommt" : "kommen") \(names(modes)) alle \(seconds) s."
    }

    public static let empty = "Die Auskunft kennt in diesem Ausschnitt gerade keine Fahrzeuge."

    /// „Kein Fahrzeug passt zum Filter. Ohne Filter wären es 84.“
    public static func emptyWithFilter(unfiltered: Int) -> String {
        "Kein Fahrzeug passt zum Filter. Ohne Filter \(unfiltered == 1 ? "wäre es eins" : "wären es \(unfiltered)")."
    }

    public static let filterOff = "Filter aus"

    /// Where the Zeitreise's clock chip sits while a city mode is on.
    public static let timeTravelHint = "Zeitreise gibt es nur mit Zügen und S-Bahn."

    static let partialFailure = "Für einen Teil der Karte kam keine Antwort. Es wird neu versucht."

    /// Everything the radar knows about this moment, for the notes under the pill (most important first).
    public struct Situation: Equatable, Sendable {
        public var status: RadarStatus
        public var selection: RadarModeSelection
        /// The city refresh came out at 60 s because the connection is metered („Automatisch“).
        public var meteredCity: Bool
        public var pinCount: Int
        /// The vehicles the map would show without the filter (modes, box and zoom applied).
        public var unfilteredCount: Int
        public var filterActive: Bool

        public init(status: RadarStatus, selection: RadarModeSelection, meteredCity: Bool = false, pinCount: Int, unfilteredCount: Int,
                    filterActive: Bool) {
            self.status = status
            self.selection = selection
            self.meteredCity = meteredCity
            self.pinCount = pinCount
            self.unfilteredCount = unfilteredCount
            self.filterActive = filterActive
        }
    }

    /// The notes under the pill: the zoom hint, the wide lane's notes (`RadarStatusText`), the city lane's loading, crowded, cut-off and failure
    /// notes, one cadence note for both lanes, the metered and data notes, and an empty map.
    public static func notes(_ s: Situation) -> [String] {
        let status = s.status
        let city = status.city
        let cityModes = s.selection.cityModes
        let cityRuns = city.visibleTiles > 0
        var notes: [String] = []
        if city.outOfZoom, !cityModes.isEmpty { notes.append(zoomHint(cityModes)) }
        // An empty map first: it is what the user sees (the screenshot of the first run had it under the data note).
        if status.anyAnswered, s.pinCount == 0, !status.anyPending, !status.isPausedOnBothLanes, !status.outsideCoverage {
            notes.append(s.filterActive && s.unfilteredCount > 0 ? emptyWithFilter(unfiltered: s.unfilteredCount) : empty)
        }
        // The wide lane's notes; while the city lane runs the cadence note below speaks for both lanes.
        var wide = status
        if cityRuns { wide.period = 0 }
        let hasVehicles = s.pinCount > 0 || status.anyAnswered
        notes += RadarStatusText.notes(wide, rail: s.selection.carriesOnlyTrains, hasVehicles: hasVehicles)
        if cityRuns, !cityModes.isEmpty {
            if city.pendingTiles > 0, !city.isPaused {
                notes.append(loading(cityModes, answered: city.answeredTiles, of: city.visibleTiles))
            }
            if city.crowdedTiles > 0 { notes.append(crowded(cityModes)) }
            if city.cappedTiles > 0 { notes.append(cityCapped(city.cappedTiles)) }
            if city.failedTiles > 0, !city.isPaused, !notes.contains(partialFailure) { notes.append(partialFailure) }
            let period = max(status.answeredTiles > 0 ? status.period : 0, city.answeredTiles > 0 ? city.period : 0)
            // A refresh of 60 s on a metered path is said by the metered note; the cadence note is for a stretched budget.
            if period > RadarStatusText.cadenceNoteAbove, status.budgetLimited || !s.meteredCity {
                notes.append("Dieser Ausschnitt · aktualisiert alle ~\(RadarStatusText.roundedPeriod(period)) s")
            }
            if s.meteredCity { notes.append(metered(cityModes)) }
            let megabytes = RadarDataEstimate.megabytesPerMinute(cityTileCounts: city.vehicleCounts, period: city.period)
            if let rounded = RadarDataEstimate.noteMegabytes(megabytes) { notes.append(dataEstimate(cityModes, megabytes: rounded)) }
        }
        return notes
    }
}

// MARK: radarmodes – the legend and the marker's VoiceOver text
public extension RadarModesText {
    static let legendTitle = "Legende"

    /// The row title of a mode in the legend ("Zug", "S-Bahn", "Bus", "Bim", "U-Bahn").
    static func legendLabel(_ mode: RadarMode) -> String { label(mode) }

    /// What VoiceOver says for a mode's row: the plate in words, after the Wegzeichen plates.
    static func legendSpoken(_ mode: RadarMode) -> String {
        switch mode {
        case .rail: return "Zug: Keil mit der Zuggattung für Fernzüge, Rechteck mit Gattung und Linie für Regionalzüge, blau"
        case .suburban: return "S-Bahn: abgerundetes Schild mit S und Liniennummer, petrol"
        case .bus: return "Bus: Kapsel mit Liniennummer, orange"
        case .tram: return "Bim: abgerundetes Schild mit Bim-Symbol, violett"
        case .subway: return "U-Bahn: Quadrat mit der Linie, in der Farbe der Linie"
        }
    }

    static let legendModesFooter = "Form, Zeichen und Text unterscheiden die Verkehrsmittel, nicht die Farbe allein."
    static let legendOnTime = "Grüner Ring: pünktlich (unter 5 Min)"
    static let legendLate = "Oranger Ring: ab 5 Min verspätet"
    static let legendCancelled = "Roter Ring: fällt aus"
    static let legendUnknown = "Grauer Ring: keine Echtzeit-Daten"
    static let legendEstimate = "Gestrichelt: zwischen zwei Antworten geschätzt"
    static let legendArrow = "Pfeil: Richtung zum nächsten Halt"
    static let legendGroup = "Zahl im Kreis: mehrere Fahrzeuge an dieser Stelle"
    static let legendFooter = "Die Positionen berechnet die ÖBB-Auskunft aus Fahrplan und Echtzeit-Meldungen. Es ist kein GPS."

    /// The spoken name of a line on the radar: the title with the mode's noun where the title has none („S-Bahn S 45“, „Straßenbahn D“,
    /// „U-Bahn-Linie U6“; „Bus 13A“ and „RJX 66“ stay as they are).
    static func spokenLine(title: String, kind: LineKind) -> String {
        switch kind {
        case .tram:
            if title.hasPrefix("Tram ") { return "Straßenbahn " + title.dropFirst(5) }
            return title.localizedCaseInsensitiveContains("straßenbahn") ? title : "Straßenbahn \(title)"
        case .sBahn:
            return title.localizedCaseInsensitiveContains("s-bahn") ? title : "S-Bahn \(title)"
        case .uBahn:
            return title.localizedCaseInsensitiveContains("u-bahn") ? title : "U-Bahn-Linie \(title)"
        case .bus, .nachtbus, .skibus, .wanderbus, .rufbus:
            return title.localizedCaseInsensitiveContains("bus") ? title : "Bus \(title)"
        default:
            return title
        }
    }

    /// The end of a marker's VoiceOver text: „Position berechnet“ (by the Auskunft), or „Position geschätzt“ while the marker moves between
    /// two answers (our own interpolation).
    static func positionNote(isEstimate: Bool) -> String { isEstimate ? "Position geschätzt" : "Position berechnet" }
}

// MARK: radarmodes – the sheet „Filter & Darstellung“, the active-filter row and the search (docs/RADAR_MODES.md §6, §9)
public extension RadarModesText {
    static let sheetTitle = "Filter & Darstellung"
    static let filterPage = "Filter"
    static let displayPage = "Darstellung"
    static let resetAll = "Alles zurücksetzen"
    static let resetDisplay = "Darstellung zurücksetzen"

    static let quickHeader = "Schnellwahl"
    static let quickFooter = "Setzt Verkehrsmittel und Filter auf einmal. Du kannst danach alles einzeln ändern."
    static let modesHeader = "Verkehrsmittel"
    /// „gerade 180“ next to a mode's switch: the vehicles of that mode on the map now.
    static func countNow(_ count: Int) -> String { "gerade \(count)" }

    static let trainClassHeader = "Zugart"
    static let trainClassFooter = "Gilt nur für Züge und S-Bahnen. Ohne Auswahl sind alle zu sehen."

    static let linesHeader = "Linie oder Zugnummer"
    static let linesPlaceholder = "z. B. RJX 66, S 45, 13A, U6"
    static let linesSuggestions = "Im Ausschnitt:"
    static let linesFooter = "Nur diese Linien sind zu sehen. Gefunden wird, was das Radar gerade geladen hat."
    static func removeLine(_ line: String) -> String { "\(line) entfernen" }

    static let operatorHeader = "Betreiber"
    static let operatorFooter = "So, wie die Auskunft ihn nennt. Steht dort bei ÖBB-Zügen „Nahreisezug“, zeigt die App „ÖBB“."

    static let delayHeader = "Verspätung"
    static let delayOnlyLate = "Nur verspätet (ab 5 Min)"
    static let delayOnlyRealtime = "Nur mit Echtzeit-Daten"
    static let delayOnTime = "Pünktlich"
    static let delayCancelled = "Fällt aus"
    static let delayFooter = "„Nur verspätet“ ersetzt „Pünktlich“ und „Fällt aus“. Ohne Echtzeit-Daten weiß die Auskunft nicht, ob ein Fahrzeug pünktlich ist."

    static let regionHeader = "Region"
    static let regionPicker = "Bundesland"
    static let regionAll = "Alle"
    static let regionFooter = "Schätzung über Haltestellennamen und Richtung. Fahrzeuge ohne eindeutigen Treffer fallen bei einer Region heraus."

    static let previewHeader = "Vorschau"
    static let labelHeader = "Beschriftung"
    static let labelFooter = "Das Ziel steht nur bei nahem Zoom und höchstens 80 einzelnen Fahrzeugen dabei."
    static let sizeHeader = "Größe"
    static let groupsToggle = "Gruppen zusammenfassen"
    static let groupsFooter = "„Aus“ gilt bis 250 Fahrzeuge im Ausschnitt, darüber fasst das Radar wieder zusammen. Ohne Gruppen können sich Marker überdecken."
    static let arrowsToggle = "Richtungspfeil"
    static let cityRefreshHeader = "Bus, Bim und U-Bahn aktualisieren"
    static let cityRefreshFooter = "Automatisch heißt: im WLAN alle 20 s, mit mobilen Daten alle 60 s. Jede Aktualisierung holt alle Busse und Bims des Ausschnitts neu."

    /// „Filter: RJX, RJ · nur verspätet“.
    static func activeFilter(_ filter: RadarFilter) -> String { "Filter: \(filter.summary)" }

    /// Short enough for the field on a phone (the spec's „Linie oder Zugnummer, z. B. RJX 66 oder 13A“ was cut off on the CI screenshots).
    static let searchPlaceholder = "Linie oder Zug, z. B. 13A, RJX 66"
    static let searchNoMatch = "Nichts gefunden in den geladenen Gebieten. Zoom heraus, verschieb die Karte oder probier eine andere Nummer."
}
