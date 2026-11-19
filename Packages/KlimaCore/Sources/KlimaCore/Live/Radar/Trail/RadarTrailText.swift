import Foundation

// MARK: radartrail – every word of „Spuren“ (docs/RADAR_TRAILS.md §8). The honesty rules of the radar (specs radar2 §7): positions are „berechnet“,
// never GPS; a trail is what this iPhone got while the radar was open, never a recording from ÖBB. Times in Europe/Vienna, 24 hours.

public enum RadarTrailText {
    // MARK: Setting („Darstellung“)

    public static let sectionTitle = "Spuren"
    public static let modeTitle = "Spuren"
    public static let modeOff = "Aus"
    public static let modeMine = "Ausgewählte und meine"
    public static let modeAll = "Alle im Ausschnitt"
    public static let lengthTitle = "Länge"
    public static let footer = "Eine Spur zeigt, wo die Auskunft das Fahrzeug berechnet hat, seit das Radar offen ist. Das Radar merkt sich das nur im Arbeitsspeicher und vergisst es beim Schließen."

    /// „5 Min“.
    public static func length(_ minutes: Int) -> String { "\(minutes) Min" }
    /// „5 Minuten“ (VoiceOver).
    public static func spokenLength(_ minutes: Int) -> String { minutes == 1 ? "1 Minute" : "\(minutes) Minuten" }

    // MARK: Caption under the status card

    /// „Spuren seit 14:21 · berechnete Positionen, kein GPS-Verlauf“.
    public static func caption(since: Date) -> String {
        "Spuren seit \(RealtimePresentation.time(since)) · berechnete Positionen, kein GPS-Verlauf"
    }

    /// „Spuren zeigen die Positionen, die dieses iPhone seit 14 Uhr 21 bekommen hat. Berechnet, kein GPS-Verlauf.“
    public static func spokenCaption(since: Date) -> String {
        "Spuren zeigen die Positionen, die dieses iPhone seit \(RadarTimeText.spokenClock(since)) bekommen hat. Berechnet, kein GPS-Verlauf."
    }

    /// „Alle im Ausschnitt“ on a map that is too wide or too full.
    public static func tooMany(hasMine: Bool) -> String {
        hasMine ? "Zu viele Fahrzeuge für alle Spuren. Gezeigt werden deine. Zoom näher heran."
            : "Zu viele Fahrzeuge für alle Spuren. Zoom näher heran."
    }

    /// The Zeitreise is away from now (only while the setting is on).
    public static let onlyNow = "Spuren gibt es nur bei „Jetzt“."

    /// The trails start at the first answer of this radar, but never earlier than the chosen length.
    public static func since(firstRecordedAt: Date, now: Date, length: TimeInterval) -> Date {
        max(firstRecordedAt, now.addingTimeInterval(-length))
    }

    // MARK: Trip sheet row

    public static let rowTitle = "Verspätung, seit du zuschaust"

    /// „+3 → +5 Min · steigt“, „+4 Min · gleich“, „+6 → +2 Min · sinkt“, „pünktlich → +5 Min · steigt“, „+5 Min → pünktlich · sinkt“,
    /// „+3 → +4 Min · etwa gleich“, „+3 Min → fällt aus“.
    public static func value(_ series: RadarDelaySeries) -> String {
        guard let first = series.first, let last = series.last else { return series.endsCancelled ? "fällt aus" : "" }
        if series.endsCancelled { return "\(amount(last, unit: true)) → fällt aus" }
        if first == last { return "\(amount(last, unit: true)) · gleich" }
        return "\(change(from: first, to: last)) · \(trendWord(series.trend))"
    }

    /// „Seit 14:21 · aus den Antworten, die dieses iPhone bekommen hat“.
    public static func sinceLine(_ start: Date) -> String {
        "Seit \(RealtimePresentation.time(start)) · aus den Antworten, die dieses iPhone bekommen hat"
    }

    /// „Verspätung seit 14 Uhr 21 von 3 auf 5 Minuten gestiegen.“ – the whole row as one sentence.
    public static func spoken(_ series: RadarDelaySeries) -> String {
        guard let start = series.start, let first = series.first, let last = series.last else { return rowTitle }
        let since = "Verspätung seit \(RadarTimeText.spokenClock(start))"
        if series.endsCancelled { return "\(since) zuletzt \(spokenAmount(last)), dann als ausgefallen gemeldet." }
        if first == last { return last == 0 ? "\(since) unverändert pünktlich." : "\(since) gleich bei \(spokenAmount(last))." }
        let fromTo: String
        if first > 0 && last > 0 {
            fromTo = "von \(first) auf \(spokenAmount(last))"
        } else {
            fromTo = "von \(spokenAmount(first)) auf \(spokenAmount(last))"
        }
        switch series.trend {
        case .rising: return "\(since) \(fromTo) gestiegen."
        case .falling: return "\(since) \(fromTo) gesunken."
        case .steady: return "\(since) etwa gleich, \(fromTo)."
        }
    }

    public static func trendWord(_ trend: RadarDelaySeries.Trend) -> String {
        switch trend {
        case .rising: "steigt"
        case .falling: "sinkt"
        case .steady: "etwa gleich"
        }
    }

    /// The chart's labels: „+3“, „pünktlich“, „−1“.
    public static func label(_ minutes: Int) -> String { amount(minutes, unit: false) }

    /// „+3 → +5 Min“, „pünktlich → +5 Min“, „+5 Min → pünktlich“.
    static func change(from first: Int, to last: Int) -> String {
        if last == 0 { return "\(amount(first, unit: true)) → pünktlich" }
        return "\(amount(first, unit: false)) → \(amount(last, unit: true))"
    }

    /// „+3 Min“ / „+3“, „pünktlich“, „−1 Min“ (a real minus sign).
    static func amount(_ minutes: Int, unit: Bool) -> String {
        if minutes == 0 { return "pünktlich" }
        let number = minutes > 0 ? "+\(minutes)" : "\u{2212}\(-minutes)"
        return unit ? "\(number) Min" : number
    }

    /// „3 Minuten“, „1 Minute“, „pünktlich“, „2 Minuten zu früh“.
    static func spokenAmount(_ minutes: Int) -> String {
        if minutes == 0 { return "pünktlich" }
        let n = abs(minutes)
        let words = n == 1 ? "1 Minute" : "\(n) Minuten"
        return minutes > 0 ? words : "\(words) zu früh"
    }
}
