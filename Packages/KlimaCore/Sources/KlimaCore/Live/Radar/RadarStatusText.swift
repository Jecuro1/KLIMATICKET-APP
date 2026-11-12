import Foundation

// The words of the Zug-Radar's status line (docs/OEBB_LIVE.md §R11). Pure: a `RadarStatus` and a count in, German text out.
// Every note says only what is true: the count is what is on the map, the age is the oldest answer among the visible tiles.

public enum RadarStatusText {
    /// A refresh slower than this (seconds) is said in the status ("aktualisiert alle ~45 s").
    public static let cadenceNoteAbove: TimeInterval = 25
    /// From this latitude span (degrees) the view counts as "ganz Österreich" in the note.
    public static let countryViewSpan = 2.0

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

    /// The notes under the pill, most important first. Empty when nothing needs saying.
    public static func notes(_ status: RadarStatus, rail: Bool) -> [String] {
        if status.outsideCoverage {
            return ["Außerhalb des Radar-Bereichs. Die Karte zeigt Züge in Österreich und der nahen Umgebung."]
        }
        var notes: [String] = []
        let what = rail ? "Züge" : "Fahrzeuge"
        if status.cappedTiles == 1 {
            notes.append("In einem Ausschnitt gibt es mehr \(what), als die Auskunft je Abfrage liefert. Zoom näher heran, dann siehst du alle.")
        } else if status.cappedTiles > 1 {
            notes.append("In \(status.cappedTiles) Ausschnitten gibt es mehr \(what), als die Auskunft je Abfrage liefert. Zoom näher heran, dann siehst du alle.")
        }
        if status.failedTiles > 0, !status.isPaused {
            notes.append("Für einen Teil der Karte kam keine Antwort. Es wird neu versucht.")
        }
        if status.answeredTiles > 0, status.period > cadenceNoteAbove {
            let scope = status.latitudeSpan >= countryViewSpan ? "Ganz Österreich" : "Dieser Ausschnitt"
            notes.append("\(scope) · aktualisiert alle ~\(roundedPeriod(status.period)) s")
        }
        return notes
    }

    /// Up to the next multiple of five seconds ("~45 s"): the figure is an estimate, a precise one would claim too much.
    static func roundedPeriod(_ seconds: TimeInterval) -> Int {
        max(5, Int((seconds / 5 - 0.001).rounded(.up)) * 5)
    }
}
