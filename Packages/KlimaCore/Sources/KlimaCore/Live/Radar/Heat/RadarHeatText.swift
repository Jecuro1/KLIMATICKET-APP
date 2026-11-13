import Foundation

// Verspätungs-Heatmap, the words (docs/RADAR_HEATMAP.md §4). Pure: numbers in, German text out (du-Form, Austrian). Every sentence
// says only what is true: the percentage is over the trains with realtime data, the delay is the one ÖBB reports for the next stop,
// the positions are calculated.

public enum RadarHeatText {
    public static let layerTitle = "Pünktlichkeit"

    /// "Pünktlich (unter 5 Min)": the name of the headline figure, the same words in the panel, the legend and VoiceOver.
    public static let punctualLabel = "Pünktlich (unter 5 Min)"

    /// What every figure rests on, always shown under the numbers.
    /// It also says what the figure is not: one moment of the trains this app holds, not ÖBB's punctuality statistics (which count
    /// differently and over a whole day), so a "74 %" here is never read as the railway's official figure.
    public static let methodNote = "Die Verspätung ist die Echtzeit-Verspätung, die die ÖBB für den nächsten Halt meldet (fehlt sie dort: die am letzten Halt mit Echtzeit-Wert). Die Positionen sind berechnet, nicht gemessen. Züge ohne Echtzeit-Daten zählen nie als pünktlich: Sie fehlen in den Prozenten. Eine Momentaufnahme dieser App, keine Pünktlichkeitsstatistik der ÖBB."

    /// The area the numbers cover: the radar's rectangle holds Austria and some border regions.
    public static let areaNote = "Gezählt werden Züge und S-Bahnen im Radar-Bereich: Österreich und angrenzende Gebiete. Busse, Bims und U-Bahnen zählen nicht."

    public static func trains(_ count: Int) -> String { count == 1 ? "1 Zug" : "\(count) Züge" }

    /// "12 Min": whole minutes, rounded down like the trip sheet and the marker do (4:59 is "4 Min", and green).
    public static func minutes(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "–" }
        return "\(Int((max(seconds, 0) / 60).rounded(.down))) Min"
    }

    /// "12 Minuten" for VoiceOver.
    public static func spokenMinutes(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "unbekannt" }
        let value = Int((max(seconds, 0) / 60).rounded(.down))
        return value == 1 ? "1 Minute" : "\(value) Minuten"
    }

    /// "+12 Min" for a train's delay.
    public static func signedDelay(_ seconds: Int) -> String { "+" + minutes(Double(seconds)) }

    // MARK: Summary

    /// "Pünktlich (unter 5 Min): 87 %"; without a single train with realtime data there is nothing to say.
    public static func headline(_ summary: HeatSummary) -> String {
        guard let percent = summary.punctualPercent else { return "Noch keine Echtzeit-Daten" }
        return "\(punctualLabel): \(percent) %"
    }

    /// "412 Züge mit Echtzeit-Daten, 38 ohne".
    public static func realtimeLine(_ summary: HeatSummary) -> String {
        if summary.total == 0 { return "Noch keine Züge geladen" }
        if summary.withRealtime == 0 {
            return summary.total == 1 ? "Keine Echtzeit-Daten bei dem geladenen Zug" : "Keine Echtzeit-Daten bei den \(summary.total) geladenen Zügen"
        }
        var text = "\(trains(summary.withRealtime)) mit Echtzeit-Daten"
        if summary.noRealtime > 0 { text += ", \(summary.noRealtime) ohne" }
        return text
    }

    /// "Ø 11 Min bei den 52 verspäteten Zügen"; "Kein Zug ist 5 Min oder mehr verspätet" when none is.
    public static func averageLine(_ summary: HeatSummary) -> String {
        guard let average = summary.averageLateSeconds, summary.late > 0 else {
            return summary.withRealtime > 0 ? "Kein Zug ist 5 Min oder mehr verspätet" : ""
        }
        let rounded = Int((average / 60).rounded())
        let noun = summary.late == 1 ? "dem verspäteten Zug" : "den \(summary.late) verspäteten Zügen"
        return "Ø \(rounded) Min bei \(noun)"
    }

    /// The legend of the stacked bar, one entry per part.
    public static func legend(_ bucket: HeatBucket) -> String {
        switch bucket {
        case .onTime: "unter 5 Min"
        case .delayed: "5 bis 15 Min"
        case .severe: "über 15 Min"
        case .cancelled: "ausgefallen"
        case .noRealtime: "ohne Echtzeit"
        }
    }

    /// "87 unter 5 Minuten, 9 zwischen 5 und 15 Minuten, …": the bar for VoiceOver, which cannot see it.
    public static func spokenSegments(_ summary: HeatSummary) -> String {
        summary.segments.map { segment in
            let words: String
            switch segment.bucket {
            case .onTime: words = "unter 5 Minuten"
            case .delayed: words = "zwischen 5 und 15 Minuten"
            case .severe: words = "über 15 Minuten"
            case .cancelled: words = "ausgefallen"
            case .noRealtime: words = "ohne Echtzeit"
            }
            return "\(segment.count) \(words)"
        }.joined(separator: ", ")
    }

    /// The whole summary as one VoiceOver sentence.
    public static func spokenSummary(_ summary: HeatSummary, ageSeconds: TimeInterval?) -> String {
        var parts = ["Pünktlichkeit der Züge im Radar-Bereich"]
        if let percent = summary.punctualPercent {
            parts.append("\(percent) Prozent der Züge mit Echtzeit-Daten sind pünktlich, also unter 5 Minuten verspätet")
        } else {
            parts.append("noch keine Echtzeit-Daten")
        }
        parts.append(realtimeLine(summary))
        let average = averageLine(summary)
        if !average.isEmpty { parts.append(average) }
        if summary.withRealtime > 0 { parts.append(spokenSegments(summary)) }
        if let ageSeconds { parts.append("Stand " + RadarStatusText.spokenAge(ageSeconds)) }
        return parts.joined(separator: ". ")
    }

    // MARK: Cells and rows

    /// What a cell without colour looks like and why: said once in the legend. On the country view such a cell is a faint grey
    /// outline, close up it is dashed and hatched: the words fit both.
    public static let neutralLegend = "Grau umrandet oder schraffiert: weniger als \(RadarHeat.minimumSample) Züge mit Echtzeit-Daten, keine Farbe."

    /// "Farbe in 46 von 298 Feldern mit Zügen": how much of the map the rule "mindestens 3 Züge" colours. Nil without trains.
    public static func coverageLine(_ snapshot: HeatSnapshot) -> String? {
        let populated = snapshot.populatedCellCount
        guard populated > 0 else { return nil }
        let noun = populated == 1 ? "Feld" : "Feldern"
        return "Farbe in \(snapshot.colouredCellCount) von \(populated) \(noun) mit Zügen"
    }

    /// "Mittlere Verspätung (Median) 12 Min" for a coloured cell; the reason for the missing colour otherwise. The value is the median,
    /// and it says so: "Ø" would be a mean.
    public static func cellTitle(_ cell: HeatCell) -> String {
        guard let median = cell.medianDelaySeconds else {
            return "Zu wenige Züge mit Echtzeit-Daten für eine Farbe (mindestens \(RadarHeat.minimumSample))"
        }
        return "Mittlere Verspätung (Median) \(minutes(median))"
    }

    /// "5 Züge · 3 mit Echtzeit-Daten": what the cell rests on.
    public static func cellBase(_ cell: HeatCell) -> String {
        var text = "\(trains(cell.trainCount)) · \(cell.sampleCount) mit Verspätungswert"
        if cell.cancelledCount > 0 { text += " · \(cell.cancelledCount) ausgefallen" }
        if cell.noRealtimeCount > 0 { text += " · \(cell.noRealtimeCount) ohne Echtzeit" }
        return text
    }

    /// The place of a hot spot: "Raum Jenbach" (the most common next stop of its trains).
    public static func place(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "Gebiet ohne Haltestelle" }
        return "Raum \(name)"
    }

    /// "Median 12 Min · 4 von 6 verspätet · 63 Min zusammen" (the median of the cell, not a mean).
    public static func hotspotDetail(_ hotspot: HeatHotspot) -> String {
        "Median \(minutes(hotspot.medianDelaySeconds)) · \(hotspot.lateCount) von \(hotspot.sampleCount) verspätet · \(Int(hotspot.delaySumMinutes.rounded())) Min zusammen"
    }

    /// A train in the list of the largest delays or in a cell.
    public static func trainRow(_ sample: HeatSample) -> (title: String, detail: String, value: String) {
        let value: String
        if sample.isCancelled {
            value = "fällt aus"
        } else if let seconds = sample.delaySeconds {
            value = seconds < 60 ? "pünktlich" : signedDelay(seconds)
        } else {
            value = "ohne Echtzeit"
        }
        return (sample.lineTitle, sample.direction.map { "nach \($0)" } ?? "", value)
    }

    /// A train for VoiceOver: "RJX 66 nach Innsbruck Hbf, 18 Minuten verspätet".
    public static func spokenTrain(_ sample: HeatSample) -> String {
        var parts = [sample.lineTitle]
        if let direction = sample.direction { parts[0] += " nach \(direction)" }
        if sample.isCancelled {
            parts.append("fällt aus")
        } else if let delay = sample.delaySeconds {
            parts.append(delay >= RadarHeat.lateThresholdSeconds ? "\(spokenMinutes(Double(delay))) verspätet" : "pünktlich")
        } else {
            parts.append("keine Echtzeit-Daten")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Layer notes

    /// Shown when no mode that carries trains is on: the numbers are about trains and S-Bahnen only.
    public static let noRailNote = "Die Pünktlichkeit zählt nur Züge und S-Bahnen. Schalte oben „Züge“ oder „S-Bahn“ ein."

    /// The note under the panel when the data is incomplete: some tiles are still loading or failed, or their last answer is so old
    /// that its trains have left the radar (after a minute or more in the background, under the cockpit or in Low Power Mode).
    public static func completenessNote(_ status: RadarStatus) -> String? {
        if status.isPaused { return "Das Radar pausiert. Die Zahlen sind vom letzten Stand." }
        if status.failedTiles > 0 { return "Für einen Teil des Landes kam keine Antwort. Die Zahlen gelten für die geladenen Gebiete." }
        if status.staleTiles > 0, status.staleTiles >= status.answeredTiles {
            return "Die Daten sind zu alt und zählen nicht mehr. Neue Zahlen kommen mit der nächsten Antwort."
        }
        if status.staleTiles > 0 { return "Für einen Teil des Landes ist die letzte Antwort zu alt. Die Zahlen gelten für die übrigen Gebiete." }
        if status.pendingTiles > 0 { return "Ein Teil des Landes wird noch geladen. Die Zahlen gelten für die geladenen Gebiete." }
        if status.cappedTiles > 0 { return "In einem Gebiet fehlt ein Teil der Züge: Mehr als die Auskunft je Abfrage liefert." }
        return nil
    }
}
