import Foundation

// Anschluss-Wächter, every visible and spoken string (docs/CONNECTION_GUARD.md §8). German, du-Form, „Min“ in compact rows
// and „Minuten“ for VoiceOver, 24-hour times in Europe/Vienna. Honest words only: „laut Prognose“ for realtime forecasts,
// „laut Fahrplan“ without realtime, never that a train „wartet“ – the Auskunft does not say it.

/// What the card's status line says.
public enum GuardStatus: Sendable, Hashable {
    /// A request is on its way.
    case checking(lastAt: Date?)
    /// The last answer and, while the loop runs, the next check.
    case updated(at: Date, next: Date?)
    case beforeWindow(lastAt: Date?, start: Date)
    case lowPower(lastAt: Date?)
    case switchedOff
    case offline(lastAt: Date?)
    case liveOff
    /// The last request failed; the next try at `retry`.
    case failed(lastAt: Date?, retry: Date?)
    case ended(lastAt: Date?)
}

/// The big line, split so the number can be large: „6“ + „Min zum Umsteigen“, „Es fehlen dir“ + „4“ + „Min“.
public struct GuardHeadline: Sendable, Hashable {
    public var prefix: String?
    public var number: String?
    public var suffix: String
    /// The whole line as one sentence part („6 Min zum Umsteigen“).
    public var full: String
}

public enum GuardText {
    // MARK: Card

    /// „Anschluss in St. Pölten Hbf“.
    public static func title(_ station: String) -> String { "Anschluss in \(station)" }

    /// The chip word.
    public static func chip(_ state: GuardState) -> String {
        switch state {
        case .safe: "Sicher"
        case .tighter: "Wird knapper"
        case .shaky: "Wackelt"
        case .likelyMissed: "Wahrscheinlich verpasst"
        case .missed: "Verpasst"
        case .cancelled: "Fällt aus"
        case .scheduled: "Nach Fahrplan"
        case .over: "Umstieg vorbei"
        }
    }

    /// The line of the train a cancellation hit (the connection when unknown).
    public static func cancelledLine(_ a: GuardAssessment) -> String {
        a.cancelledLeg == .feeder ? a.feeder.lineName : a.connection.lineName
    }

    /// „6 Min zum Umsteigen“ · „1 Min zum Umsteigen“ · „Es fehlt dir 1 Min“ · „Es fehlen dir 4 Min“ · „REX 2 fällt aus“.
    public static func headline(_ a: GuardAssessment) -> GuardHeadline {
        if a.state == .cancelled || a.rawState == .cancelled {
            let text = "\(cancelledLine(a)) fällt aus"
            return GuardHeadline(prefix: nil, number: nil, suffix: text, full: text)
        }
        if a.state == .over {
            let text = "\(a.connection.lineName) ist abgefahren"
            return GuardHeadline(prefix: nil, number: nil, suffix: text, full: text)
        }
        guard let buffer = a.bufferMinutes else {
            let text = "Umstiegszeit nicht bekannt"
            return GuardHeadline(prefix: nil, number: nil, suffix: text, full: text)
        }
        if buffer >= 0 {
            return GuardHeadline(prefix: nil, number: "\(buffer)", suffix: "Min zum Umsteigen", full: "\(buffer) Min zum Umsteigen")
        }
        let missing = -buffer
        let prefix = missing == 1 ? "Es fehlt dir" : "Es fehlen dir"
        return GuardHeadline(prefix: prefix, number: "\(missing)", suffix: "Min", full: "\(prefix) \(missing) Min")
    }

    /// „Wird knapper: vor 4 Min waren es 9 Min“ · „Gleichbleibend“ · „Entspannt sich: vor 3 Min waren es 2 Min“. nil without
    /// two answers to compare, and for the end states.
    public static func trend(_ a: GuardAssessment, now: Date) -> String? {
        guard a.hasTrendHistory, a.bufferMinutes != nil else { return nil }
        switch a.state {
        case .cancelled, .missed, .over: return nil
        default: break
        }
        switch a.trend {
        case .steady:
            return "Gleichbleibend"
        case .falling:
            guard let ref = a.trendReference else { return "Wird knapper" }
            return "Wird knapper: vor \(minutesAgo(ref.at, now: now)) Min waren es \(ref.minutes) Min"
        case .rising:
            guard let ref = a.trendReference else { return "Entspannt sich" }
            return "Entspannt sich: vor \(minutesAgo(ref.at, now: now)) Min waren es \(ref.minutes) Min"
        }
    }

    /// „14:31 (+3)“ · „14:30 (-1)“ · „14:31 (pünktlich)“ · „14:40 laut Fahrplan“ · „14:40 · fällt aus“.
    public static func legTime(_ f: GuardLegFigure) -> String {
        guard let shown = f.effective else { return "Zeit nicht bekannt" }
        let time = RealtimePresentation.time(shown)
        if f.isCancelled { return "\(RealtimePresentation.time(f.planned ?? shown)) · fällt aus" }
        guard f.hasRealtime, let delay = f.delayMinutes else { return "\(time) laut Fahrplan" }
        if delay == 0 { return "\(time) (pünktlich)" }
        return delay > 0 ? "\(time) (+\(delay))" : "\(time) (\(delay))"
    }

    /// „Gleis 4“ / „Steig B“; nil without a platform.
    public static func platform(_ f: GuardLegFigure) -> String? {
        f.platform.map { "\(f.isStand ? "Steig" : "Gleis") \($0)" }
    }

    /// „Ankunft RJX 66 · 14:31 (+3) · Gleis 4“.
    public static func arrivalLine(_ f: GuardLegFigure) -> String { legLine("Ankunft", f) }

    /// „Abfahrt REX 2 · 14:40 (+1) · Gleis 7“.
    public static func departureLine(_ f: GuardLegFigure) -> String { legLine("Abfahrt", f) }

    static func legLine(_ kind: String, _ f: GuardLegFigure) -> String {
        [ "\(kind) \(f.lineName)", legTime(f), platform(f) ].compactMap { $0 }.joined(separator: " · ")
    }

    /// „Fußweg laut Fahrplan: 3 Min“ · „Kein eigener Fußweg laut Fahrplan“ · „Fußweg nicht bekannt“.
    public static func walk(_ a: GuardAssessment) -> String {
        guard a.walkKnown else { return "Fußweg nicht bekannt" }
        return a.walkMinutes > 0 ? "Fußweg laut Fahrplan: \(a.walkMinutes) Min" : "Kein eigener Fußweg laut Fahrplan"
    }

    /// „Gleis geändert: 5 → 7“ for the connection's departure; nil without a change.
    public static func platformChange(_ f: GuardLegFigure) -> String? {
        guard f.platformChanged, let to = f.platform else { return nil }
        let word = f.isStand ? "Steig" : "Gleis"
        guard let from = f.plannedPlatform, from != to else { return "\(word) geändert: jetzt \(to)" }
        return "\(word) geändert: \(from) → \(to)"
    }

    /// „REX 2 ist laut Prognose um 14:40 abgefahren.“ (laut Fahrplan without realtime).
    public static func missedNote(_ a: GuardAssessment) -> String? {
        guard a.state == .missed, let departure = a.connection.effective else { return nil }
        let source = a.connection.hasRealtime ? "laut Prognose" : "laut Fahrplan"
        return "\(a.connection.lineName) ist \(source) um \(RealtimePresentation.time(departure)) abgefahren."
    }

    public static let unreachableNote = "Die ÖBB-Auskunft markiert den Anschluss als nicht erreichbar."
    public static let noRealtimeNote = "Keine Echtzeit-Daten: gerechnet nach Fahrplan."
    public static let overNote = "Der Wächter ist für diese Fahrt fertig."

    /// „Danach: Umstieg in Wiener Neustadt Hbf, 12 Min laut Fahrplan“.
    public static func laterTransfer(_ t: GuardLaterTransfer) -> String {
        guard let minutes = t.plannedBufferMinutes else { return "Danach: Umstieg in \(t.stationName)" }
        return "Danach: Umstieg in \(t.stationName), \(minutes) Min laut Fahrplan"
    }

    /// The status line.
    public static func status(_ s: GuardStatus, now: Date) -> String {
        switch s {
        case .checking(let last):
            return stand(last).map { "\($0) · Prüfe gerade …" } ?? "Prüfe gerade …"
        case .updated(let at, let next):
            guard let next else { return "Stand \(RealtimePresentation.time(at))" }
            return "Stand \(RealtimePresentation.time(at)) · nächste Prüfung \(inMinutes(next.timeIntervalSince(now)))"
        case .beforeWindow(let last, let start):
            let begin = "Automatische Prüfung ab \(RealtimePresentation.time(start))"
            return stand(last).map { "\($0) · \(begin)" } ?? begin
        case .lowPower(let last):
            let text = "Stromspar-Modus: keine automatische Prüfung."
            return stand(last).map { "\($0) · \(text)" } ?? text
        case .switchedOff:
            return "Wächter für diese Fahrt aus."
        case .offline(let last):
            guard let last else { return "Ohne Internet keine Prüfung." }
            return "Ohne Internet keine Prüfung. Gezeigt ist der Stand von \(RealtimePresentation.time(last))."
        case .liveOff:
            return "Für die Prüfung braucht es Live-Daten."
        case .failed(let last, let retry):
            let base = "Die Auskunft antwortet gerade nicht"
            let tail = retry.map { " · neuer Versuch \(inMinutes($0.timeIntervalSince(now)))" } ?? ""
            return (stand(last).map { "\($0) · " } ?? "") + base + tail
        case .ended(let last):
            return stand(last).map { "\($0) · Prüfung beendet" } ?? "Prüfung beendet"
        }
    }

    // MARK: Buttons and footer

    public static let alternativesButton = "Alternativen ansehen"
    /// After „Umstieg vorbei“: „REX 41 weiter verfolgen“ (and VoiceOver „REX 41 live verfolgen“).
    public static func continueButton(_ line: String) -> String { "\(line) weiter verfolgen" }
    public static func continueSpoken(_ line: String) -> String { "\(line) live verfolgen" }
    public static let alarmButton = "Wecker fürs Umsteigen"
    public static let checkButton = "Jetzt prüfen"
    public static let switchOff = "Wächter aus"
    public static let switchOn = "Wächter an"
    /// „Jetzt prüfen“ was tapped less than 20 s ago.
    public static func checkTooSoon(_ seconds: TimeInterval) -> String {
        "Gerade geprüft · wieder in \(max(1, Int(seconds.rounded(.up)))) s"
    }

    public static let footerOpenOnly = "KlimaBilanz prüft deinen Anschluss nur, solange die App offen ist. Im Hintergrund kommt höchstens "
        + "die Mitteilung „Anschluss knapp“ – nur mit eingeschalteten Live-Mitteilungen und nur, wenn iOS die App kurz aufweckt. "
        + "Das ist nicht garantiert."
    public static let footerNoWaiting = "Ob ein Zug wartet, sagt die Auskunft nicht. Die Einschätzung rechnet mit den Prognosen beider Züge."

    // MARK: VoiceOver

    /// The card as one sentence: „Anschluss in St. Pölten Hbf: wackelt, 1 Minute zum Umsteigen, wird knapper. Ankunft RJX 66 um
    /// 14 Uhr 31, 3 Minuten später. Abfahrt REX 2 um 14 Uhr 40, 1 Minute später, Gleis 7. Fußweg 3 Minuten.“
    public static func accessibility(_ a: GuardAssessment, now: Date) -> String {
        var head = [spokenState(a.state)]
        head.append(spokenBuffer(a))
        if let trend = spokenTrend(a) { head.append(trend) }
        var sentences = ["\(title(a.stationName)): \(head.joined(separator: ", "))."]
        sentences.append(spokenLeg("Ankunft", a.feeder, platform: false) + ".")
        sentences.append(spokenLeg("Abfahrt", a.connection, platform: true) + ".")
        if a.walkKnown {
            sentences.append(a.walkMinutes > 0 ? "Fußweg \(RealtimePresentation.minutes(a.walkMinutes))." : "Kein eigener Fußweg laut Fahrplan.")
        } else {
            sentences.append("Fußweg nicht bekannt.")
        }
        if let change = platformChange(a.connection) { sentences.append(change.replacingOccurrences(of: " → ", with: " auf ") + ".") }
        if let missed = missedNote(a) { sentences.append(missed) }
        if a.flaggedUnreachable { sentences.append(unreachableNote) }
        if a.basedOnPlan { sentences.append(noRealtimeNote) }
        return sentences.joined(separator: " ")
    }

    static func spokenState(_ s: GuardState) -> String {
        switch s {
        case .safe: "sicher"
        case .tighter: "wird knapper"
        case .shaky: "wackelt"
        case .likelyMissed: "wahrscheinlich verpasst"
        case .missed: "verpasst"
        case .cancelled: "fällt aus"
        case .scheduled: "nach Fahrplan"
        case .over: "Umstieg vorbei"
        }
    }

    static func spokenBuffer(_ a: GuardAssessment) -> String {
        if a.state == .cancelled || a.rawState == .cancelled { return "\(cancelledLine(a)) fällt aus" }
        if a.state == .over { return "\(a.connection.lineName) ist abgefahren" }
        guard let buffer = a.bufferMinutes else { return "Umstiegszeit nicht bekannt" }
        if buffer >= 0 { return "\(RealtimePresentation.minutes(buffer)) zum Umsteigen" }
        return buffer == -1 ? "es fehlt dir 1 Minute" : "es fehlen dir \(RealtimePresentation.minutes(-buffer))"
    }

    static func spokenTrend(_ a: GuardAssessment) -> String? {
        guard a.hasTrendHistory, a.bufferMinutes != nil else { return nil }
        switch a.state {
        case .cancelled, .missed, .over: return nil
        default: break
        }
        switch a.trend {
        case .falling: return a.state == .tighter ? nil : "wird knapper"
        case .rising: return "entspannt sich"
        case .steady: return "gleichbleibend"
        }
    }

    static func spokenLeg(_ kind: String, _ f: GuardLegFigure, platform withPlatform: Bool) -> String {
        guard let shown = f.effective else { return "\(kind) \(f.lineName), Zeit nicht bekannt" }
        var parts = ["\(kind) \(f.lineName) um \(spokenTime(f.isCancelled ? (f.planned ?? shown) : shown))"]
        if f.isCancelled {
            parts.append("fällt aus")
        } else if f.hasRealtime, let delay = f.delayMinutes {
            parts.append(delay == 0 ? "pünktlich" : (delay > 0 ? "\(RealtimePresentation.minutes(delay)) später"
                                                              : "\(RealtimePresentation.minutes(-delay)) früher"))
        } else {
            parts.append("laut Fahrplan")
        }
        if withPlatform, let p = platform(f) { parts.append(p) }
        return parts.joined(separator: ", ")
    }

    /// „14 Uhr 31“, „9 Uhr 5“, „14 Uhr“.
    public static func spokenTime(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h) Uhr" : "\(h) Uhr \(m)"
    }

    // MARK: Toasts and badge

    /// „St. Pölten“ for „St. Pölten Hbf“ (toasts are short).
    public static func shortStation(_ name: String) -> String {
        var n = DisplayNames.name(name)
        for suffix in [" Hbf", " Bahnhof", " Bf"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
            break
        }
        return n
    }

    /// One toast per worsening: „Anschluss in St. Pölten wird knapper“ · „… wackelt“ · „… wahrscheinlich verpasst“ ·
    /// „… verpasst“ · „REX 2 fällt aus“. nil for states that are no worsening.
    public static func toast(_ a: GuardAssessment) -> String? {
        let station = shortStation(a.stationName)
        switch a.state {
        case .tighter: return "Anschluss in \(station) wird knapper"
        case .shaky: return "Anschluss in \(station) wackelt"
        case .likelyMissed: return "Anschluss in \(station) wahrscheinlich verpasst"
        case .missed: return "Anschluss in \(station) verpasst"
        case .cancelled: return "\(cancelledLine(a)) fällt aus"
        case .safe, .scheduled, .over: return nil
        }
    }

    /// The accessory badge: „Anschluss wird knapper“ …; nil when there is nothing to warn about.
    public static func badge(_ state: GuardState) -> String? {
        switch state {
        case .tighter: "Anschluss wird knapper"
        case .shaky: "Anschluss wackelt"
        case .likelyMissed: "Anschluss wahrscheinlich verpasst"
        case .missed: "Anschluss verpasst"
        case .cancelled: "Anschluss fällt aus"
        case .safe, .scheduled, .over: nil
        }
    }

    /// The compact badge word („wohl verpasst“ is the only shortened one; VoiceOver reads `badge`).
    public static func badgeCompact(_ state: GuardState) -> String? {
        switch state {
        case .tighter: "knapper"
        case .shaky: "wackelt"
        case .likelyMissed: "wohl verpasst"
        case .missed: "verpasst"
        case .cancelled: "fällt aus"
        case .safe, .scheduled, .over: nil
        }
    }

    // MARK: Alternatives

    /// „Weiter ab St. Pölten Hbf“.
    public static func alternativesTitle(_ origin: String) -> String { "Weiter ab \(DisplayNames.name(origin))" }

    /// „Nach Wiener Neustadt Hbf · ab 14:42“.
    public static func alternativesSubtitle(destination: String, from date: Date) -> String {
        "Nach \(DisplayNames.name(destination)) · ab \(RealtimePresentation.time(date))"
    }

    /// „ab 14:52 · Gleis 3“.
    public static func alternativeDeparture(_ journey: Journey) -> String {
        guard let event = journey.departure, let time = event.effective else { return "ab –" }
        let firstRide = journey.rideLegs.first
        let platform = firstRide.flatMap { JourneyPresentation.platformLabel($0.departure, mode: $0.line?.mode) }
        let word = platform.map { $0.label == "Steig" ? "Steig" : "Gleis" }
        return ["ab \(RealtimePresentation.time(time))", platform.flatMap { p in word.map { "\($0) \(p.display)" } }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// „an 16:10“.
    public static func alternativeArrival(_ journey: Journey) -> String {
        journey.arrival?.effective.map { "an \(RealtimePresentation.time($0))" } ?? "an –"
    }

    /// „22 Min später als geplant“ · „wie geplant“ · „3 Min früher als geplant“.
    public static func delta(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        if minutes == 0 { return "wie geplant" }
        return minutes > 0 ? "\(minutes) Min später als geplant" : "\(-minutes) Min früher als geplant"
    }

    /// „1 Umstieg“ (the planner's words).
    public static func changes(_ journey: Journey) -> String { JourneyPresentation.changesText(journey.changes) }

    public static let followButton = "Verfolgen"
    public static let followButtonSpoken = "Diese Verbindung live verfolgen"
    public static let plannerButton = "Im Fahrplan öffnen"
    public static let plannerSearchButton = "Im Fahrplan suchen"
    public static let alternativesTip = "Tipp: Mit „Verfolgen“ prüft KlimaBilanz auch den neuen Umstieg."
    public static let alternativesLoading = "Suche Verbindungen …"
    public static let alternativesEmpty = "Die Auskunft kennt gerade keine passende Verbindung. Sieh im Fahrplan nach."
    public static let alternativesFailed = "Die Suche hat gerade nicht geklappt. Sieh im Fahrplan nach."
    public static let alternativesNewSearch = "Neu suchen"

    /// „Neue Suche in 2 Min möglich“.
    public static func searchLimit(_ seconds: TimeInterval) -> String {
        "Neue Suche in \(max(1, Int((seconds / 60).rounded(.up)))) Min möglich"
    }

    /// „Eine Suche bei der ÖBB-Auskunft, gesucht wie im Fahrplan (Nur mit KlimaTicket gültig: an).“
    public static func alternativesFooter(klimaTicketOnly: Bool) -> String {
        "Eine Suche bei der ÖBB-Auskunft, gesucht wie im Fahrplan (Nur mit KlimaTicket gültig: \(klimaTicketOnly ? "an" : "aus"))."
    }

    /// VoiceOver of one alternative row.
    public static func alternativeSpoken(_ journey: Journey, originalArrival: Date?) -> String {
        let lines = journey.rideLegs.compactMap { $0.line.map { LinePresentation.title($0) } }.joined(separator: ", ")
        var parts = [alternativeDeparture(journey), alternativeArrival(journey)]
        if let d = delta(GuardAlternatives.deltaMinutes(journey, originalArrival: originalArrival)) { parts.append(d) }
        parts.append(changes(journey))
        if !lines.isEmpty { parts.append(lines) }
        return parts.joined(separator: ", ").replacingOccurrences(of: " · ", with: ", ")
    }

    // MARK: Helpers

    static func stand(_ date: Date?) -> String? { date.map { "Stand \(RealtimePresentation.time($0))" } }

    /// „in 1 Min“, „in 2 Min“; „gleich“ when due.
    static func inMinutes(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "gleich" }
        return "in \(max(1, Int((seconds / 60).rounded(.up)))) Min"
    }

    static func minutesAgo(_ at: Date, now: Date) -> Int {
        max(1, Int((now.timeIntervalSince(at) / 60).rounded()))
    }
}
