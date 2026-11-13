import Foundation

/// The small Live Activity layout (`ActivityFamily.small`): what the Apple Watch Smart Stack shows of a followed train or a
/// running ride, without a watch app (docs/WIDGETS_SMARTSTACK.md §5). One line "RJX 66 07:42 +3", the destination, a
/// countdown the system runs by itself (`Text(timerInterval:)`) and "Stand 07:40" once the data is old. ContentState and
/// attributes are not changed: everything here is derived from what the activity already carries. Pure, unit-tested.
public struct ActivitySmallLine: Equatable, Sendable {
    /// "RJX 66 07:42 +3", "Zug 07:42", "S 4 fällt aus".
    public var headline: String
    /// The delay part of the headline on its own ("+3"), for a separate tint; nil when on time or unknown.
    public var delay: String?
    /// "Wien Hbf" (shortened station name).
    public var destination: String
    /// What the countdown counts to; nil when nothing is ahead (arrived, cancelled, ended).
    public var countdownTarget: Date?
    /// "Abfahrt in", "Ankunft in", "Umstieg in"; for a running ride without arrival "Unterwegs seit".
    public var countdownLabel: String
    /// True when the timer counts up from `countdownTarget` (a ride without a known arrival).
    public var countsUp: Bool
    /// "Stand 07:40" (follow) or "Noch nicht gespeichert" (ride) when the data is old; nil otherwise.
    public var footnote: String?
    /// The whole line as one German sentence for VoiceOver.
    public var spoken: String
}

public enum ActivitySmallText {
    /// Longest line label kept as it is; longer ones become the mode word ("Zug").
    public static let maxLineLabel = 8

    // MARK: Live verfolgen

    /// A followed ride. Before departure the line shows the planned departure and the departure delay (derived from the
    /// effective boarding time), while riding the planned arrival and the delay at the alighting stop.
    public static func follow(lineName: String, alightName: String, stage: FollowStage, plannedDeparture: Date?,
                              plannedArrival: Date?, nextStopTime: Date?, delayMinutes: Int?, transferStation: String?,
                              transferDeparture: Date?, updatedAt: Date?, isStale: Bool) -> ActivitySmallLine {
        let label = lineLabel(lineName, fallback: "Zug")
        let destination = shortStation(alightName)
        let stand = isStale ? updatedAt.map { "Stand \(RealtimePresentation.time($0))" } ?? "Keine aktuellen Daten" : nil
        let spokenStand = isStale ? updatedAt.map { " Stand \(RealtimePresentation.time($0)), keine aktuellen Daten." }
            ?? " Keine aktuellen Daten." : ""

        switch stage {
        case .beforeDeparture, .boarding:
            let effective = nextStopTime ?? plannedDeparture
            let delay = departureDelay(planned: plannedDeparture, effective: nextStopTime)
            let planned = plannedDeparture ?? effective
            let delayText = delay.flatMap(delayBadge)
            let headline = [label, planned.map(RealtimePresentation.time), delayText].compactMap { $0 }.joined(separator: " ")
            var spoken = "\(lineName) nach \(destination)"
            if let effective { spoken += ", Abfahrt um \(RealtimePresentation.time(effective))" }
            spoken += spokenDelay(delay) + "." + spokenStand
            return ActivitySmallLine(headline: headline, delay: delayText, destination: destination,
                                     countdownTarget: effective, countdownLabel: "Abfahrt in", countsUp: false,
                                     footnote: stand, spoken: spoken)
        case .riding:
            let effective = plannedArrival.map { arrival in arrival.addingTimeInterval(TimeInterval((delayMinutes ?? 0) * 60)) }
            let delayText = delayMinutes.flatMap(delayBadge)
            let headline = [label, plannedArrival.map(RealtimePresentation.time), delayText].compactMap { $0 }.joined(separator: " ")
            var spoken = "\(lineName) nach \(destination)"
            if let effective { spoken += ", Ankunft um \(RealtimePresentation.time(effective))" }
            spoken += spokenDelay(delayMinutes) + "." + spokenStand
            return ActivitySmallLine(headline: headline, delay: delayText, destination: destination,
                                     countdownTarget: effective, countdownLabel: "Ankunft in", countsUp: false,
                                     footnote: stand, spoken: spoken)
        case .transfer:
            let station = transferStation.map(shortStation) ?? destination
            let headline = [label, transferDeparture.map { "→ \(RealtimePresentation.time($0))" }].compactMap { $0 }
                .joined(separator: " ")
            var spoken = "Umstieg in \(station)"
            if let transferDeparture { spoken += ", Weiterfahrt um \(RealtimePresentation.time(transferDeparture))" }
            spoken += "." + spokenStand
            return ActivitySmallLine(headline: headline, delay: nil, destination: station,
                                     countdownTarget: transferDeparture, countdownLabel: "Umstieg in", countsUp: false,
                                     footnote: stand, spoken: spoken)
        case .arrived:
            return ActivitySmallLine(headline: "\(label) angekommen", delay: nil, destination: destination,
                                     countdownTarget: nil, countdownLabel: "", countsUp: false, footnote: nil,
                                     spoken: "\(lineName) ist in \(destination) angekommen.")
        case .cancelled:
            return ActivitySmallLine(headline: "\(label) fällt aus", delay: nil, destination: destination,
                                     countdownTarget: nil, countdownLabel: "", countsUp: false, footnote: stand,
                                     spoken: "\(lineName) nach \(destination) fällt aus." + spokenStand)
        }
    }

    // MARK: Unterwegs

    /// A running ride ("Unterwegs"): the line or mode with the start time, the destination, and the count down to the
    /// expected arrival when the planner knows it, else the elapsed time since the start.
    public static func ride(modeName: String, lineLabel rideLine: String?, toName: String, startedAt: Date,
                            expectedArrival: Date?, phase: RidePhase, isStale: Bool, endedAt: Date?) -> ActivitySmallLine {
        let label = rideLine.map { lineLabel($0, fallback: modeName) } ?? modeName
        let destination = shortStation(toName)
        let spokenName = (rideLine?.isEmpty == false ? rideLine : nil) ?? modeName
        switch phase {
        case .saved, .ended:
            let word = phase == .saved ? "Gespeichert" : "Beendet"
            let time = endedAt.map { " \(RealtimePresentation.time($0))" } ?? ""
            return ActivitySmallLine(headline: "\(word)\(time)", delay: nil, destination: destination, countdownTarget: nil,
                                     countdownLabel: "", countsUp: false, footnote: nil,
                                     spoken: "Fahrt nach \(destination) \(phase == .saved ? "gespeichert" : "beendet")\(endedAt.map { " um \(RealtimePresentation.time($0))" } ?? "").")
        case .arrived:
            return ActivitySmallLine(headline: "\(label) angekommen", delay: nil, destination: destination, countdownTarget: nil,
                                     countdownLabel: "", countsUp: false, footnote: "Fahrt speichern",
                                     spoken: "\(spokenName) ist in \(destination) angekommen. Fahrt noch speichern.")
        case .riding:
            let headline = "\(label) \(RealtimePresentation.time(startedAt))"
            let footnote = isStale ? "Noch nicht gespeichert" : nil
            if let expectedArrival, !isStale {
                return ActivitySmallLine(headline: headline, delay: nil, destination: destination,
                                         countdownTarget: expectedArrival, countdownLabel: "Ankunft in", countsUp: false,
                                         footnote: footnote,
                                         spoken: "\(spokenName) nach \(destination), seit \(RealtimePresentation.time(startedAt)) unterwegs, Ankunft um \(RealtimePresentation.time(expectedArrival)).")
            }
            return ActivitySmallLine(headline: headline, delay: nil, destination: destination,
                                     countdownTarget: startedAt, countdownLabel: "Unterwegs seit", countsUp: true,
                                     footnote: footnote,
                                     spoken: "\(spokenName) nach \(destination), seit \(RealtimePresentation.time(startedAt)) unterwegs." + (isStale ? " Noch nicht gespeichert." : ""))
        }
    }

    // MARK: Pieces

    /// "+3", "−2" for early; nil when on time (0) or unknown. Early trains get a real minus sign.
    public static func delayBadge(_ minutes: Int) -> String? {
        if minutes > 0 { return "+\(minutes)" }
        if minutes < 0 { return "\u{2212}\(-minutes)" }
        return nil
    }

    /// Whole minutes between the planned and the effective departure; nil without both.
    public static func departureDelay(planned: Date?, effective: Date?) -> Int? {
        guard let planned, let effective else { return nil }
        return Int((effective.timeIntervalSince(planned) / 60).rounded())
    }

    /// The line name when it is short ("RJX 66", "S 4", "Bus 750"), else the mode word.
    public static func lineLabel(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLineLabel else { return fallback }
        return trimmed
    }

    /// "Innsbruck Hauptbahnhof" → "Innsbruck Hbf", "Feldkirch Bahnhof" → "Feldkirch Bf", "St. Anton am Arlberg" → "St. Anton".
    public static func shortStation(_ name: String) -> String {
        var short = RideNames.short(name)
        if short.hasSuffix(" Bahnhof") { short = String(short.dropLast(" Bahnhof".count)) + " Bf" }
        return short
    }

    static func spokenDelay(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        if minutes == 0 { return ", pünktlich" }
        if minutes > 0 { return minutes == 1 ? ", 1 Minute später" : ", \(minutes) Minuten später" }
        return -minutes == 1 ? ", 1 Minute früher" : ", \(-minutes) Minuten früher"
    }
}
