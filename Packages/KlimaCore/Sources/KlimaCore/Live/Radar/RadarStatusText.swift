import Foundation

// The words of the Zug-Radar's status line (docs/OEBB_LIVE.md §R11). Pure: a `RadarStatus` and a count in, German text out.
// Every note says only what is true: the count is what is on the map, the age is the oldest answer among the visible tiles.

public enum RadarStatusText {
    /// A refresh slower than this (seconds) is said in the status ("aktualisiert alle ~45 s").
    public static let cadenceNoteAbove: TimeInterval = 25

    /// "gerade eben", "vor 12 s", "vor 2 Min".
    public static func age(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0).rounded())
        if s < 3 { return "gerade eben" }
        if s < 60 { return "vor \(s) s" }
        return "vor \(s / 60) Min"
    }

    /// The same for VoiceOver, without abbreviations.
    public static func spokenAge(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0).rounded())
        if s < 3 { return "gerade eben" }
        if s < 60 { return "vor \(s) Sekunden" }
        let minutes = s / 60
        return minutes == 1 ? "vor einer Minute" : "vor \(minutes) Minuten"
    }

    /// "923 Züge · vor 12 s": the vehicles in the visible area and the age of the oldest answer behind them.
    public static func pill(count: Int, rail: Bool, age: TimeInterval?) -> String {
        let noun = rail ? (count == 1 ? "Zug" : "Züge") : (count == 1 ? "Fahrzeug" : "Fahrzeuge")
        guard let age else { return "\(count) \(noun)" }
        return "\(count) \(noun) · \(Self.age(age))"
    }

    /// The notes under the pill, most important first. Empty when nothing needs saying. `hasVehicles`: the map shows vehicles
    /// already (answers of an earlier view count), so a note about tiles still to come is not redundant with "Lade Fahrzeuge …".
    public static func notes(_ status: RadarStatus, rail: Bool, hasVehicles: Bool = true) -> [String] {
        if status.outsideCoverage {
            return ["Außerhalb des Radar-Bereichs. Die Karte zeigt Züge in Österreich und der nahen Umgebung."]
        }
        var notes: [String] = []
        let what = rail ? "Züge" : "Fahrzeuge"
        // Only a tile on the finest level can still be cut off, and zooming in does not make it finer: the server answers the
        // first 1000 of a 5 × 9 km tile whatever the zoom. So the note says what is missing, not that zooming would help.
        if status.cappedTiles == 1 {
            notes.append("In einem Gebiet fahren mehr \(what), als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte.")
        } else if status.cappedTiles > 1 {
            notes.append("In \(status.cappedTiles) Gebieten fahren mehr \(what), als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte.")
        }
        if status.failedTiles > 0, !status.isPaused {
            notes.append("Für einen Teil der Karte kam keine Antwort. Es wird neu versucht.")
        }
        // Tiles of a new view that were not asked yet: the count above does not include their trains.
        if status.pendingTiles > 0, hasVehicles, !status.isPaused {
            notes.append("Ein Teil der Karte wird noch geladen.")
        }
        if status.answeredTiles > 0, status.period > cadenceNoteAbove {
            let scope = status.coversCountry ? "Ganz Österreich" : "Dieser Ausschnitt"
            notes.append("\(scope) · aktualisiert alle ~\(roundedPeriod(status.period)) s")
        }
        return notes
    }

    /// Up to the next multiple of five seconds ("~45 s"): the figure is an estimate, a precise one would claim too much.
    static func roundedPeriod(_ seconds: TimeInterval) -> Int {
        max(5, Int((seconds / 5 - 0.001).rounded(.up)) * 5)
    }
}
