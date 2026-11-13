import Foundation

// Automatik (docs/AUTOMATION.md): every German sentence of the rules – the rule as a sentence, the Testlauf's explanation, the
// notice texts, the „nächste“ line and the budget warning. Locale-independent (€ 23,50, „29. Jän.“), so the tests read
// exactly what the app shows.

public enum AutoText {
    /// The promise of the whole feature, said on its screen.
    public static let honestyLine = "Regeln laufen nur, wenn die App offen ist oder wenn iOS eine vorab geplante Mitteilung zustellt."

    // MARK: Numbers and dates

    /// „€ 20“, „€ 1.400“, „€ 23,50“.
    public static func euro(_ value: Double) -> String {
        let cents = Int((abs(value) * 100).rounded())
        let euros = cents / 100
        let rest = cents % 100
        var digits = String(euros)
        var grouped = ""
        while digits.count > 3 {
            grouped = "." + digits.suffix(3) + grouped
            digits = String(digits.dropLast(3))
        }
        let whole = digits + grouped
        let sign = value < 0 && cents > 0 ? "– " : ""
        return rest == 0 ? "\(sign)€ \(whole)" : "\(sign)€ \(whole),\(rest < 10 ? "0" : "")\(rest)"
    }

    static let monthShort = ["Jän.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez."]

    /// „Montag“ … „Sonntag“.
    public static func weekdayName(_ day: RouteWeekday) -> String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][day.rawValue]
    }

    /// „28. Feb.“.
    public static func dateText(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.day, .month], from: date)
        return "\(p.day ?? 1). \(monthShort[max(0, min(11, (p.month ?? 1) - 1))])"
    }

    /// „heute 19:00“, „morgen 19:00“, „Mo 19:00“ (within a week), „29. Jän. 09:00“.
    public static func whenShort(_ date: Date, now: Date, calendar: Calendar) -> String {
        let clock = AutoClock.clockText(AutoClock.minuteOfDay(date, calendar: calendar))
        switch dayDistance(from: now, to: date, calendar: calendar) {
        case 0: return "heute \(clock)"
        case 1: return "morgen \(clock)"
        case 2...6: return "\(AutoClock.weekday(date, calendar: calendar).shortName) \(clock)"
        default: return "\(dateText(date, calendar: calendar)) \(clock)"
        }
    }

    /// „heute um 19:00“, „morgen um 19:00“, „am Mo um 19:00“, „am 29. Jän. um 09:00“.
    public static func whenPhrase(_ date: Date, now: Date, calendar: Calendar) -> String {
        let clock = AutoClock.clockText(AutoClock.minuteOfDay(date, calendar: calendar))
        switch dayDistance(from: now, to: date, calendar: calendar) {
        case 0: return "heute um \(clock)"
        case 1: return "morgen um \(clock)"
        case 2...6: return "am \(AutoClock.weekday(date, calendar: calendar).shortName) um \(clock)"
        default: return "am \(dateText(date, calendar: calendar)) um \(clock)"
        }
    }

    /// Calendar days from `now`'s day to `date`'s day (negative in the past).
    static func dayDistance(from now: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// „Mo–Fr“, „Sa–So“, „täglich“, „Mo, Mi, Fr“.
    public static func days(_ set: Set<RouteWeekday>) -> String {
        if set.count == 7 { return "täglich" }
        if set.isEmpty { return "an keinem Tag" }
        return RouteSchedule(weekdays: set, hour: 0, minute: 0).dayText
    }

    // MARK: The rule as a sentence

    /// „30 Tage vor Ablauf meines Tickets“ – the part after „Wenn“.
    public static func triggerPhrase(_ trigger: AutoTrigger) -> String {
        switch trigger.normalized {
        case let .ticketDeadline(days):
            switch days {
            case 0: return "mein Ticket heute abläuft"
            case 1: return "mein Ticket morgen abläuft"
            default: return "mein Ticket in \(days) Tagen abläuft"
            }
        case let .milestone(percents):
            return "mein Ticket \(percentList(percents)) amortisiert ist"
        case let .dayWithoutTrip(weekdays, minute):
            return "\(days(weekdays)) um \(AutoClock.clockText(minute)) noch keine Fahrt erfasst ist"
        case let .followDelay(minutes):
            return "meine verfolgte Fahrt \(minutes) Min Verspätung hat"
        case let .tripLogged(filter):
            return "ich eine Fahrt\(filterPhrase(filter)) erfasse"
        }
    }

    /// „50, 75 oder 100 %“.
    public static func percentList(_ percents: Set<Int>) -> String {
        let sorted = percents.sorted().map(String.init)
        guard sorted.count > 1 else { return "\(sorted.first ?? "100") %" }
        return sorted.dropLast().joined(separator: ", ") + " oder " + (sorted.last ?? "") + " %"
    }

    /// „ über € 20 mit dem Zug auf St. Anton ⇄ Innsbruck“ – empty for every trip.
    public static func filterPhrase(_ filter: AutoTripFilter) -> String {
        var parts: [String] = []
        if let minimum = filter.minValueEUR { parts.append("ab \(euro(minimum))") }
        if !filter.modes.isEmpty { parts.append("mit \(modeList(filter.modes))") }
        if let route = filter.route { parts.append("auf \(route.fromName) ⇄ \(route.toName)") }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    /// „Zug oder Bus“ in the app's mode order.
    public static func modeList(_ modes: Set<TransportMode>) -> String {
        let names = TransportMode.allCases.filter { modes.contains($0) }.map(\.displayName)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " oder " + (names.last ?? "")
    }

    /// „es Mo–Fr ist“ – the part after „und“.
    public static func conditionPhrase(_ condition: AutoCondition) -> String {
        switch condition {
        case let .weekdays(set): return set.count == 7 ? "es ein beliebiger Tag ist" : "es \(days(set)) ist"
        case let .timeWindow(start, end): return "es zwischen \(AutoClock.clockText(start)) und \(AutoClock.clockText(end)) ist"
        case .noTripToday: return "heute noch keine Fahrt erfasst ist"
        case .validTicket: return "ein Ticket gilt"
        }
    }

    /// „sag es mir“ – the part after „dann“.
    public static func actionPhrase(_ rule: AutoRule) -> String {
        let rule = rule.normalized
        var phrase = rule.addTrip != nil ? "erinnere mich und öffne „Fahrt erfassen“" : "sag es mir"
        if let shortcut = rule.shortcutName { phrase += " und biete den Kurzbefehl „\(shortcut)“ an" }
        return phrase
    }

    /// „Wenn meine verfolgte Fahrt 10 Min Verspätung hat und es Mo–Fr ist, dann sag es mir.“
    public static func sentence(_ rule: AutoRule) -> String {
        let rule = rule.normalized
        let conditions = rule.conditions.map(conditionPhrase)
        let middle = conditions.isEmpty ? "" : " und " + conditions.joined(separator: " und ")
        return "Wenn \(triggerPhrase(rule.trigger))\(middle), dann \(actionPhrase(rule))."
    }

    /// The name a new rule gets when its owner gives none.
    public static func defaultName(for kind: AutoTriggerKind) -> String {
        switch kind {
        case .ticketDeadline: "Vor Ablauf erinnern"
        case .milestone: "Meilensteine feiern"
        case .dayWithoutTrip: "Abendcheck"
        case .followDelay: "Verspätung melden"
        case .tripLogged: "Fahrt erfasst"
        }
    }

    /// „Vor Ablauf“ – the short name of a trigger in a picker.
    public static func kindTitle(_ kind: AutoTriggerKind) -> String {
        switch kind {
        case .ticketDeadline: "Vor Ablauf des Tickets"
        case .milestone: "Meilenstein erreicht"
        case .dayWithoutTrip: "Tag ohne Fahrt"
        case .followDelay: "Verspätung der verfolgten Fahrt"
        case .tripLogged: "Fahrt erfasst"
        }
    }

    /// „geplant“ or „nach dem Speichern“ – when a trigger can fire at all.
    public static func kindTiming(_ kind: AutoTriggerKind) -> String {
        switch kind {
        case .ticketDeadline, .dayWithoutTrip: "vorab geplante Mitteilung"
        case .milestone, .tripLogged: "nach dem Speichern einer Fahrt"
        case .followDelay: "bei jeder Antwort von „Live verfolgen“"
        }
    }

    // MARK: The Testlauf's explanation

    /// „Würde jetzt auslösen: Verspätung 8 Min ist mindestens 5 Min (RJ 66, Ausstieg Innsbruck Hbf), kein Cooldown“,
    /// „Würde heute um 19:00 auslösen: …“, „Löst nicht aus: erst 3 Min Verspätung, ausgelöst wird ab 5 Min“.
    public static func explanation(_ verdict: AutoVerdict, calendar: Calendar) -> String {
        let reason = reasonText(verdict.reason, now: verdict.now, calendar: calendar)
        switch verdict.outcome {
        case .now:
            var suffix = ""
            if verdict.conditionsMet { suffix += ", Bedingungen erfüllt" }
            if verdict.cooldownClear { suffix += ", kein Cooldown" }
            return "Würde jetzt auslösen: \(reason)\(suffix)"
        case let .at(date):
            let suffix = verdict.conditionsMet ? ", Bedingungen erfüllt" : ""
            return "Würde \(whenPhrase(date, now: verdict.now, calendar: calendar)) auslösen: \(reason)\(suffix)"
        case .silent:
            if case .tripToday = verdict.reason { return "Löst heute nicht aus: \(reason)" }
            return "Löst nicht aus: \(reason)"
        }
    }

    /// One reason in words (no prefix).
    public static func reasonText(_ reason: AutoReason, now: Date, calendar: Calendar) -> String {
        switch reason {
        case let .deadline(days, name, end, moved):
            let lead: String
            switch days {
            case 0: lead = "\(name) läuft heute ab"
            case 1: lead = "\(name) läuft morgen ab (\(dateText(end, calendar: calendar)))"
            default: lead = "\(days) Tage vor Ablauf von \(name) (gültig bis \(dateText(end, calendar: calendar)))"
            }
            return moved ? lead + ", wegen „Wochenende ruhig“ schon am Freitag" : lead
        case let .milestone(percent, current, _):
            return percent >= 100
                ? "\(current) % amortisiert – die Gipfelmarke ist erreicht und für dieses Ticket noch nicht gefeiert"
                : "\(current) % amortisiert – \(percent) % ist erreicht und für dieses Ticket noch nicht gefeiert"
        case let .dayWithoutTrip(_, isToday):
            return isToday ? "heute ist noch keine Fahrt erfasst" : "wenn bis dahin keine Fahrt für diesen Tag erfasst ist"
        case let .delay(minutes, threshold, stop, line):
            return "Verspätung \(minutes) Min ist mindestens \(threshold) Min (\(line), Ausstieg \(stop))"
        case let .tripMatched(trip, filter, count, isLast):
            let lead = isLast ? "deine letzte Fahrt " : ""
            let more = count > 1 ? " und \(count - 1) weitere" : ""
            let fit = filter.isEmpty ? "jede Fahrt zählt" : "passt zu „\(filterPhrase(filter).trimmingCharacters(in: .whitespaces))“"
            return "\(lead)\(trip.fromName) → \(trip.toName) · \(euro(trip.value))\(more) – \(fit)"
        case .ruleOff:
            return "die Regel ist ausgeschaltet"
        case .noTicket:
            return "es ist kein Ticket erfasst"
        case let .deadlinePassed(day):
            return "der Termin war am \(dateText(day, calendar: calendar))"
        case .ticketEnded:
            return "dein Ticket ist abgelaufen"
        case let .milestoneBelow(current, next):
            return "erst \(current) % amortisiert, nächster Meilenstein \(next) %"
        case let .milestonesDone(current):
            return "jetzt \(current) % – alle gewählten Meilensteine sind für dieses Ticket schon erreicht"
        case let .tripToday(next):
            guard let next else { return "an diesem Tag ist schon eine Fahrt erfasst" }
            return "heute ist schon eine Fahrt erfasst. Nächster Termin: \(whenShort(next, now: now, calendar: calendar))"
        case .noWeekday:
            return "kein Wochentag gewählt"
        case .noUpcomingSlot:
            return "in den nächsten \(AutoRuleScheduler.horizonDays) Tagen gibt es keinen passenden Termin"
        case .noFollow:
            return "keine Fahrt wird live verfolgt. Starte „Live verfolgen“ bei einer Verbindung"
        case .followEnded:
            return "die verfolgte Fahrt ist zu Ende"
        case .noDelayData:
            return "für deinen Ausstieg ist noch keine Echtzeit gemeldet"
        case let .delayBelow(minutes, threshold):
            return "erst \(minutes) Min Verspätung, ausgelöst wird ab \(threshold) Min"
        case let .alreadyReported(threshold):
            return "diese Verspätung ist schon gemeldet. Neu gemeldet wird, wenn sie unter \(threshold) Min fällt und wieder steigt"
        case .noTrip:
            return "es ist noch keine Fahrt erfasst"
        case .noNewTrip:
            return "seit der letzten Prüfung ist keine Fahrt dazugekommen"
        case let .tripNotMatched(trip, mismatch, isLast):
            let lead = isLast ? "deine letzte Fahrt" : "die neue Fahrt"
            switch mismatch {
            case let .route(route):
                return "\(lead) \(trip.fromName) → \(trip.toName) liegt nicht auf \(route.fromName) ⇄ \(route.toName)"
            case let .mode(found, wanted):
                return "\(lead) war mit \(modeList(found)), die Regel wartet auf \(modeList(wanted))"
            case let .value(found, minimum):
                return "\(lead) (\(euro(found))) liegt unter \(euro(minimum))"
            }
        case let .weekdayExcluded(day):
            return "\(weekdayName(day)) ist nicht gewählt"
        case let .outsideWindow(start, end):
            return "außerhalb von \(AutoClock.clockText(start))–\(AutoClock.clockText(end))"
        case .ticketInvalid:
            return "an diesem Tag gilt kein Ticket"
        case .quietWeekend:
            return "„Wochenende ruhig“ ist an"
        case let .cooldown(until):
            return "Cooldown bis \(AutoClock.clockText(AutoClock.minuteOfDay(until, calendar: calendar)))"
        case .otherEvent:
            return "die Regel wartet auf ihr eigenes Ereignis"
        }
    }

    // MARK: Notice texts

    /// Title and body of the notice a firing or a planned moment sends. The rule's own title or body replace the automatic ones.
    public static func content(rule: AutoRule, reason: AutoReason, calendar: Calendar) -> (title: String, body: String) {
        let automatic = automaticContent(rule: rule, reason: reason, calendar: calendar)
        let title = rule.customTitle.isEmpty ? automatic.title : rule.customTitle
        let body = rule.customBody.isEmpty ? automatic.body : rule.customBody
        return (title, body)
    }

    static func automaticContent(rule: AutoRule, reason: AutoReason, calendar: Calendar) -> (title: String, body: String) {
        let opensAdd = rule.addTrip != nil
        switch reason {
        case let .deadline(days, name, end, _):
            let title: String
            switch days {
            case 0: title = "Dein Ticket läuft heute ab"
            case 1: title = "Dein Ticket läuft morgen ab"
            default: title = "Noch \(days) Tage gültig"
            }
            return (title, "\(name) gilt bis \(dateText(end, calendar: calendar)) – denk rechtzeitig an Verlängerung oder Kündigung.")
        case let .milestone(percent, current, name):
            if percent >= 100 { return ("Dein Ticket hat sich rentiert", "\(name) ist zu \(current) % amortisiert. Ab jetzt ist jede Fahrt Gewinn.") }
            return ("\(percent) % geschafft", "\(name) ist zu \(current) % amortisiert. Weiter so!")
        case .dayWithoutTrip:
            return ("Heute noch keine Fahrt erfasst",
                    opensAdd ? "Warst du heute mit den Öffis unterwegs? Tippe hier und trag die Fahrt nach."
                             : "Warst du heute mit den Öffis unterwegs? Dann trag die Fahrt in KlimaBilanz nach.")
        case let .delay(minutes, _, stop, line):
            return ("Verspätung \(minutes) Min", "\(line) kommt in \(stop) etwa \(minutes) Min später an (ÖBB-Prognose).")
        case let .tripMatched(trip, filter, count, _):
            let title = filter.minValueEUR.map { "Fahrt ab \(euro($0)) erfasst" } ?? "Fahrt erfasst"
            let more = count > 1 ? " (und \(count - 1) weitere)" : ""
            return (title, "\(trip.fromName) → \(trip.toName) · \(euro(trip.value))\(more)")
        default:
            return (rule.name, sentence(rule))
        }
    }

    // MARK: State lines

    /// The line under a rule: „nächste: Mo 19:00“, „wartet auf „Live verfolgen““, „nächster Meilenstein: 75 %“.
    public static func nextLine(rule: AutoRule, plan: AutoPlan, state: AutoState, now: Date, calendar: Calendar) -> String {
        let rule = rule.normalized
        guard rule.isEnabled else { return "aus" }
        switch rule.trigger {
        case .ticketDeadline, .dayWithoutTrip:
            if let next = plan.next(for: rule.id) { return "nächste: \(whenShort(next, now: now, calendar: calendar))" }
            if plan.overflow.contains(where: { $0.ruleID == rule.id }) { return "gerade kein Platz frei" }
            let verdict = AutoRuleEngine.evaluate(rule, event: .probe, state: state, now: now, calendar: calendar)
            return reasonText(verdict.reason, now: now, calendar: calendar)
        case let .milestone(percents):
            guard let ticket = state.ticket else { return "wartet auf ein Ticket" }
            let done = state.ledger.celebrated(ruleID: rule.id, ticketID: ticket.id)
            let open = percents.filter { !done.contains($0) && ticket.amortizedFraction * 100 + 1e-9 < Double($0) }
            guard let next = open.min() else { return "alle Meilensteine erreicht" }
            return "nächster Meilenstein: \(next) % · jetzt \(ticket.percent) %"
        case .followDelay:
            guard let follow = state.follow, !follow.isFinished else { return "wartet auf „Live verfolgen“" }
            guard let delay = follow.delayMinutes else { return "verfolgt \(follow.lineName) · noch keine Echtzeit" }
            return "verfolgt \(follow.lineName) · jetzt \(delay) Min"
        case .tripLogged:
            return "wartet auf die nächste Fahrt"
        }
    }

    /// The warning when the rules want more planned notices than they have places. nil while everything fits.
    public static func budgetWarning(_ plan: AutoPlan, ruleNames: [UUID: String]) -> String? {
        guard plan.isOverCeiling else { return nil }
        let waiting = plan.overflow.count
        var text = "Mehr Termine als Plätze: \(waiting) \(waiting == 1 ? "Termin wartet" : "Termine warten") auf einen der \(plan.ceiling) Plätze. Sie rücken nach, wenn du die App öffnest und ein Platz frei ist."
        let names = plan.rulesWithoutSlot.compactMap { ruleNames[$0] }
        if names.count == 1, let name = names.first {
            text += " „\(name)“ hat gerade keinen Platz."
        } else if names.count > 1 {
            text += " \(names.count) Regeln haben gerade keinen Platz."
        }
        return text
    }
}
