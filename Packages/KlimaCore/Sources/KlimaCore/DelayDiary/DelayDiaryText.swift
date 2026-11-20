import Foundation

// MARK: - „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md) – every sentence whose wording matters, in one place (tested)
//
// The diary is a personal log: never „Anspruch“, never an amount of money, never a verdict on a compensation. The caveat is on
// the screen and in the PDF.

public enum DelayDiaryText {
    /// Under the share on the screen and in the PDF.
    public static let caveat = "Das ist deine persönliche Quote. Für eine Entschädigung zählt laut AGB die Pünktlichkeit der Bahn im Gültigkeitsmonat (Punkt 24), nicht einzelne Verspätungen."
    /// The PDF's caveat (the document may be read by someone else: no „deine“).
    public static let reportCaveat = "Die Quote ist eine persönliche Aufzeichnung. Für eine Entschädigung zählt laut AGB des KlimaTicket Ö die Pünktlichkeit der Bahn im Gültigkeitsmonat (Punkt 24), nicht einzelne Verspätungen."
    public static let emptyState = "Noch keine Verspätung eingetragen – tippe bei einer Fahrt auf Verspätung."
    public static let tooFewForShare = "zu wenig Fahrten für eine Quote"
    public static let title = "Verspätungs-Tagebuch"
    public static let reportTitle = "Verspätungs-Tagebuch – persönliche Aufzeichnung"

    /// The PDF's neutral first paragraph. It names live data only when a listed row came from it (this build records by hand).
    public static func reportIntro(threshold: Int, scope: DelayDiaryScope, hasLive: Bool = false) -> String {
        let fahrten = scope == .rail ? "Zug- und S-Bahn-Fahrten" : "Fahrten"
        let origin = hasLive ? "Die Minuten wurden von Hand eingetragen oder aus Live-Daten übernommen" : "Die Minuten wurden von Hand eingetragen"
        return "Diese Liste wurde mit der App KlimaBilanz auf dem eigenen iPhone geführt. Sie nennt \(fahrten), bei denen die Ankunft mindestens \(threshold)\u{00A0}Minuten später war als geplant. \(origin); es sind keine amtlichen Pünktlichkeitswerte."
    }

    /// The entry sheet's verdict for a trip that „Nur Bahn“ leaves out (a bus, a Bim): the minutes still count in the Zeitbilanz,
    /// the diary does not count the trip at all (review-delaydiary: the sheet said „Zählt als verspätet“ for it).
    public static let outsideScopeLine = "Zählt nicht im Tagebuch – dort zählen gerade nur Zug und S-Bahn"

    /// „Verspätet heißt hier: ab 5 Min. Ankunft – deine eigene Grenze, keine Regel aus den AGB.“
    public static func thresholdLine(_ threshold: Int) -> String {
        "Verspätet heißt hier: ab \(threshold)\u{00A0}Min. bei der Ankunft – deine eigene Grenze, keine Regel aus den AGB."
    }

    // MARK: Numbers

    /// The share as whole percent, rounded DOWN below 100 (one late Fahrt in 300 is „99 %“, never „100 %“); „< 1 %“ for a
    /// share above 0 that rounds to 0.
    public static func percent(_ share: Double) -> String {
        guard share.isFinite else { return "–" }
        if share >= 1 { return "100\u{00A0}%" }
        let whole = Int((max(0, share) * 100).rounded(.down))
        if whole == 0 && share > 0 { return "< 1\u{00A0}%" }
        return "\(whole)\u{00A0}%"
    }

    /// „+12 Min.“, „pünktlich“ for 0.
    public static func minutes(_ minutes: Int) -> String {
        minutes <= 0 ? "pünktlich" : "+\(minutes)\u{00A0}Min."
    }

    /// „von Hand“ / „live“.
    public static func sourceName(_ source: TripDelaySource) -> String {
        switch source {
        case .manual: "von Hand"
        case .live: "live"
        }
    }

    /// The trip detail's row value: „+12 Min. · von Hand“, „pünktlich · live“, „nicht erfasst“.
    public static func rowValue(minutes: Int?, source: TripDelaySource?) -> String {
        guard let minutes, let source else { return "nicht erfasst" }
        return "\(Self.minutes(minutes)) · \(sourceName(source))"
    }

    /// VoiceOver: „12 Minuten Verspätung“, „1 Minute Verspätung“, „Pünktlich“.
    public static func spoken(_ minutes: Int) -> String {
        switch minutes {
        case ...0: "Pünktlich"
        case 1: "1 Minute Verspätung"
        default: "\(minutes) Minuten Verspätung"
        }
    }

    /// The row as VoiceOver reads it: „12 Minuten Verspätung, von Hand eingetragen“ / „Nicht erfasst“.
    public static func spokenRow(minutes: Int?, source: TripDelaySource?) -> String {
        guard let minutes, let source else { return "Nicht erfasst" }
        let origin = source == .manual ? "von Hand eingetragen" : "aus Live-Daten übernommen"
        return "\(spoken(minutes)), \(origin)"
    }

    /// „1 Fahrt“ / „12 Fahrten“.
    public static func fahrten(_ count: Int) -> String { count == 1 ? "1\u{00A0}Fahrt" : "\(count)\u{00A0}Fahrten" }

    /// A month row's line: „12 Fahrten · 9 erfasst · 2 verspätet“ (only what is there). A number keeps its word on the line.
    public static func monthSummary(trips: Int, recorded: Int, late: Int) -> String {
        guard trips > 0 else { return "Keine Fahrten" }
        var parts = [fahrten(trips)]
        parts.append(recorded == trips ? "alle\u{00A0}erfasst" : "\(recorded)\u{00A0}erfasst")
        if recorded > 0 { parts.append("\(late)\u{00A0}verspätet") }
        return parts.joined(separator: " · ")
    }

    /// An open month without a late Fahrt, on the screen and in the PDF: „Keine Verspätung ab 5 Min. in diesem Monat.“ only
    /// when something was recorded – a month with no entry is not a punctual one.
    public static func noLateLine(threshold: Int, recorded: Int) -> String {
        recorded > 0 ? "Keine Verspätung ab \(threshold)\u{00A0}Min. in diesem Monat." : "In diesem Monat ist noch nichts eingetragen."
    }

    /// A month chip of „Nachweis als PDF“: „2 verspätet“, „0 erfasst“ for a month without an entry (not „0 verspätet“).
    public static func reportChipLine(recorded: Int, late: Int) -> String {
        recorded > 0 ? "\(late)\u{00A0}verspätet" : "0\u{00A0}erfasst"
    }

    /// The PDF's summary of the chosen months: „7 Gültigkeitsmonate · 68 Fahrten, davon 55 mit erfasster Ankunft, 9 verspätet
    /// (ab 5 Min.) · persönliche Quote dieser Monate: 83 % pünktlich“. The share is the chosen months' only (review-delaydiary:
    /// the default choice leaves out months without a late Fahrt, and an unqualified „persönliche Quote: 83 %“ read like the
    /// year's 85 % on the screen).
    public static func reportSummary(months: Int, trips: Int, recorded: Int, late: Int, threshold: Int, share: Double?) -> String {
        let monthWord = months == 1 ? "1 Gültigkeitsmonat" : "\(months) Gültigkeitsmonate"
        let quote = months == 1 ? "persönliche Quote dieses Monats" : "persönliche Quote dieser Monate"
        return "\(monthWord) · \(fahrten(trips)), davon \(recorded) mit erfasster Ankunft, \(late) verspätet (ab \(threshold)\u{00A0}Min.) · \(quote): \(shareLine(share))"
    }

    /// The share line of a month or the year: „87 % pünktlich“ or „zu wenig Fahrten für eine Quote“.
    public static func shareLine(_ share: Double?) -> String {
        share.map { "\(percent($0))\u{00A0}pünktlich" } ?? tooFewForShare
    }

    /// „St. Anton am Arlberg → Innsbruck Hbf“, with „(Hin & Retour)“ or „(3 Etappen)“.
    public static func route(from: String, to: String, roundTrip: Bool, legs: Int) -> String {
        var text = "\(from) → \(to)"
        if roundTrip { text += " (Hin & Retour)" }
        if legs > 1 { text += " (\(legs) Etappen)" }
        return text
    }

    /// The live-capture toast: „Verspätung +12 Min. übernommen“ / „Pünktlich angekommen – übernommen“.
    public static func capturedToast(_ minutes: Int) -> String {
        minutes <= 0 ? "Pünktlich angekommen – übernommen" : "Verspätung \(Self.minutes(minutes)) übernommen"
    }
}
