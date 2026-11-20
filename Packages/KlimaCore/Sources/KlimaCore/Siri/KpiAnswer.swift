import Foundation

// MARK: siri – the answer to one question for one period (docs/SIRI_QUESTIONS.md §4): the sentence Siri says and shows, the figure
// written out for the snippet and for a Kurzbefehl, and the bars under it. Pure: Siri, the Kurzbefehle-App and „Probier es aus“ in
// Einstellungen call the same function with the same table, so the app shows exactly what Siri says.

public struct KpiAnswer: Equatable, Sendable {
    public enum Status: String, Sendable {
        /// A figure (zero included for questions that are not about trips).
        case figure
        /// No trip in the period.
        case empty
        /// The app has not written a table yet.
        case noTable
        /// A ticket question without a ticket.
        case noTicket
    }

    public var question: KpiQuestion
    /// The period answered: the asked one, or the ticket year for a ticket question.
    public var period: KpiPeriod
    public var status: Status
    /// What Siri says and shows above the snippet – spoken figures („186 Euro 40“), the stale note included.
    public var sentence: String
    /// The figure as the app writes it („€ 186,40“, „14 Fahrten“, „45 Tage“); nil without one.
    public var value: String?
    /// What the figure is: „Wert deiner Fahrten · Oktober 2026“.
    public var label: String
    /// One bar per day (week, month) or per month (year, ticket year) of the asked figure; empty for ticket questions.
    public var bars: [KpiBar]
    /// 0 … 1 for a ticket question (share of the validity gone, share of the ticket price reached).
    public var progress: Double?
    /// The table is older than a day (the sentence says „Stand …“).
    public var isStale: Bool

    /// What a Kurzbefehl gets to work with: the written figure, or the sentence when there is none.
    public var shortcutValue: String { value ?? sentence }

    /// The period part of `label` („Oktober 2026“, „Ticketjahr 2026/27“); nil when the label names the question only.
    public var periodLabel: String? {
        let prefix = question.title + " · "
        return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : nil
    }
}

public struct KpiBar: Equatable, Sendable, Identifiable {
    /// The day key or „2026-10“.
    public var id: String
    /// „Mo“, „14“, „J“.
    public var label: String
    public var value: Double
    /// Today, or this month.
    public var isCurrent: Bool
}

extension KpiAnswer {
    public static let openAppSentence = "Öffne KlimaBilanz einmal – dann kennt Siri deine Zahlen."
    public static let noTicketSentence = "Öffne KlimaBilanz und lege zuerst dein Ticket an."

    /// The answer to `question` for `period` from `table` at `now`.
    /// - Parameter pending: when the Fahrten that widgets, Control Center and Siri queued („Lieblingsfahrt erfassen“) were logged –
    ///   they reach the table only once the app opens and saves them. Those of the answered period are named after the figure
    ///   (MARK: review-siri – „Ticket-Bilanz anzeigen“ already counts them, so Siri's two answers would disagree silently).
    public static func make(_ question: KpiQuestion, period: KpiPeriod, table: KpiDailyTable?, now: Date, pending: [Date] = [],
                            calendar: Calendar = .vienna) -> KpiAnswer {
        let answered: KpiPeriod = question.isTicketOnly ? .ticketYear : period
        guard let table else {
            return KpiAnswer(question: question, period: answered, status: .noTable, sentence: openAppSentence, value: nil,
                             label: question.title, bars: [], progress: nil, isStale: false)
        }
        var answer = question.isTicketOnly
            ? ticketAnswer(question, asked: period, table: table, now: now, calendar: calendar)
            : periodAnswer(question, period: period, table: table, now: now, calendar: calendar)
        if answer.status != .noTicket, let note = pendingNote(question, period: answered, table: table, pending: pending, now: now, calendar: calendar) {
            answer.sentence += " " + note
        }
        if table.isStale(at: now) {
            answer.isStale = true
            answer.sentence += " Stand \(KpiSpoken.date(table.generatedAt, now: now, calendar: calendar)). Öffne die App, um zu aktualisieren."
        }
        return answer
    }

    /// „Noch nicht dabei: 1 Fahrt aus Widget oder Siri – sie zählt, sobald du KlimaBilanz öffnest.“ for the queued Fahrten of the
    /// answered period; nil for none, and for the questions they do not change (a date, a price per day).
    static func pendingNote(_ question: KpiQuestion, period: KpiPeriod, table: KpiDailyTable, pending: [Date], now: Date,
                            calendar: Calendar) -> String? {
        guard !pending.isEmpty, question != .daysLeft, question != .costPerDay else { return nil }
        let count: Int
        if let range = period.range(now: now, weekStart: table.format.weekStart, calendar: calendar) {
            count = pending.filter { date in
                let key = KpiDailyTable.dayKey(date, calendar: calendar)
                return key >= range.first && key <= range.last
            }.count
        } else if let ticket = table.ticket {
            count = pending.filter { ticket.period.contains($0) }.count
        } else {
            count = 0
        }
        guard count > 0 else { return nil }
        return count == 1
            ? "Noch nicht dabei: 1\(KpiSpoken.glue)Fahrt aus Widget oder Siri – sie zählt, sobald du KlimaBilanz öffnest."
            : "Noch nicht dabei: \(KpiSpoken.trips(count)) aus Widget oder Siri – sie zählen, sobald du KlimaBilanz öffnest."
    }

    // MARK: Trips, value, km, CO₂

    private static func periodAnswer(_ question: KpiQuestion, period: KpiPeriod, table: KpiDailyTable, now: Date,
                                     calendar: Calendar) -> KpiAnswer {
        let format = table.format
        let figures: (journeys: Int, value: Double, km: Double, co2: Double)
        let hasTrips: Bool
        let name: String
        let label: String
        let bars: [KpiBar]
        if let range = period.range(now: now, weekStart: format.weekStart, calendar: calendar) {
            let sum = table.sum(from: range.first, through: range.last)
            figures = (sum.journeys, sum.value, sum.km, sum.co2)
            hasTrips = table.days.contains { $0.day >= range.first && $0.day <= range.last }
            name = range.name
            label = range.label
            bars = dayBars(question, period: period, range: range, table: table, now: now, calendar: calendar)
        } else {
            guard let ticket = table.ticket else {
                return KpiAnswer(question: question, period: period, status: .noTicket, sentence: noTicketSentence, value: nil,
                                 label: question.title, bars: [], progress: nil, isStale: false)
            }
            figures = (ticket.tripCount, ticket.totalValue, ticket.distanceKm, ticket.co2SavedKg)
            hasTrips = ticket.tripCount > 0
            name = "im Ticketjahr"
            label = "Ticketjahr \(ticketYear(ticket, calendar: calendar))"
            // MARK: review-siri – only the ticket's own days (its first and last month held trips of the ticket before and after,
            // so the bars did not add up to the figure above them or match Statistik's months); none when the table's days do not
            // reach back to the ticket's start (an old ticket year: its early months would read empty).
            let first = KpiDailyTable.dayKey(ticket.start, calendar: calendar), last = KpiDailyTable.dayKey(ticket.end, calendar: calendar)
            bars = first >= table.firstCoveredDay(calendar: calendar)
                ? monthBars(question, from: ticket.start, to: ticket.end, days: (first, last), table: table, now: now, calendar: calendar)
                : []
        }
        let title = "\(question.title) · \(label)"
        let opening = name.prefix(1).uppercased() + name.dropFirst()
        let value: String
        let sentence: String
        switch question {
        case .trips:
            value = KpiSpoken.trips(figures.journeys)
            sentence = "\(opening) hast du \(KpiSpoken.trips(figures.journeys)) erfasst."
        case .value:
            value = KpiSpoken.writtenEuro(figures.value, format: format)
            sentence = "Der Wert deiner Fahrten \(name): \(KpiSpoken.euro(figures.value)). So viel hätten sie einzeln gekostet."
        case .distance:
            value = KpiSpoken.writtenKm(figures.km)
            sentence = "\(opening) bist du \(KpiSpoken.km(figures.km)) gefahren."
        default:   // .co2 – the ticket questions never get here
            value = KpiSpoken.writtenCO2(figures.co2, format: format)
            sentence = "\(opening) hast du gegenüber dem Auto etwa \(KpiSpoken.co2(figures.co2, format: format)) CO₂ gespart."
        }
        guard hasTrips else {
            let still = period == .ticketYear && now <= (table.ticket?.end ?? now) ? "noch " : ""
            return KpiAnswer(question: question, period: period, status: .empty, sentence: "\(opening) hast du \(still)keine Fahrt erfasst.",
                             value: value, label: title, bars: bars, progress: nil, isStale: false)
        }
        return KpiAnswer(question: question, period: period, status: .figure, sentence: sentence, value: value, label: title, bars: bars,
                         progress: nil, isStale: false)
    }

    // MARK: Ticket questions

    private static func ticketAnswer(_ question: KpiQuestion, asked: KpiPeriod, table: KpiDailyTable, now: Date,
                                     calendar: Calendar) -> KpiAnswer {
        guard let ticket = table.ticket else {
            return KpiAnswer(question: question, period: .ticketYear, status: .noTicket, sentence: noTicketSentence, value: nil,
                             label: question.title, bars: [], progress: nil, isStale: false)
        }
        let format = table.format
        // Days and the price per day by the summary's own formulas (an empty trip list: only the dates and the price count).
        let days = SavingsCalculator.summary(ticket: ticket.period, trips: [], now: now, calendar: calendar)
        let isOver = now > ticket.end
        let notYet = now < ticket.start
        let amortized = ticket.price > 0 ? min(1, max(0, ticket.totalValue / ticket.price)) : 1
        let label = "\(question.title) · Ticketjahr \(ticketYear(ticket, calendar: calendar))"
        let note = asked != .ticketYear && !question.ignoresPeriod ? "Das gibt es nur fürs ganze Ticketjahr. " : ""
        let endDate = KpiSpoken.date(ticket.end, now: now, calendar: calendar)
        var value: String
        var sentence: String
        var progress: Double? = amortized
        switch question {
        case .net:
            value = KpiSpoken.writtenEuro(ticket.net, format: format)
            let cents = (ticket.net * 100).rounded()
            if cents > 0 {
                sentence = isOver ? "Dein Ticket hat sich rentiert: Du warst \(KpiSpoken.euro(ticket.net)) im Plus."
                    : "Dein Ticket hat sich rentiert: Du bist \(KpiSpoken.euro(ticket.net)) im Plus."
            } else if cents == 0 {
                sentence = "Du bist genau beim Break-even: Deine Fahrten waren so viel wert wie dein Ticket."
            } else {
                sentence = isOver ? "Dein Ticket ist abgelaufen: Du warst \(KpiSpoken.euro(-ticket.net)) im Minus."
                    : "Du bist noch \(KpiSpoken.euro(-ticket.net)) im Minus. So viel fehlt bis zum Break-even."
            }
        case .breakEven:
            value = KpiSpoken.writtenEuro(ticket.remainingToBreakEven, format: format)
            if ticket.isPaidOff {
                sentence = ticket.paidOffDate.map { "Nichts mehr: Dein Ticket hat sich am \(KpiSpoken.date($0, now: now, calendar: calendar)) rentiert." }
                    ?? "Nichts mehr: Dein Ticket hat sich schon rentiert."
            } else if isOver {
                sentence = "Dein Ticket ist abgelaufen. Bis zum Break-even haben \(KpiSpoken.euro(ticket.remainingToBreakEven)) gefehlt."
            } else {
                sentence = "Bis zum Break-even fehlen noch \(KpiSpoken.euro(ticket.remainingToBreakEven))."
                if ticket.tripCount > 0, !notYet {
                    if ticket.forecastReachesBreakEven, let date = ticket.forecastBreakEvenDate {
                        sentence += " Prognose bei deinem Tempo: am \(KpiSpoken.date(date, now: now, calendar: calendar))."
                    } else {
                        sentence += " Bei deinem bisherigen Tempo reicht es laut Prognose nicht bis zum Ablauf."
                    }
                }
            }
        case .daysLeft:
            progress = notYet ? 0 : Double(days.daysElapsed) / Double(max(1, days.daysTotal))
            if isOver {
                value = "abgelaufen"
                progress = 1
                sentence = "Dein Ticket ist am \(endDate) abgelaufen."
            } else if notYet {
                // MARK: review-siri – the days until it runs out, counted like „noch … Tage“ (it said the period's length, 365)
                let today = calendar.startOfDay(for: now), endDay = calendar.startOfDay(for: ticket.end)
                value = KpiSpoken.days(max(0, calendar.dateComponents([.day], from: today, to: endDay).day ?? days.daysTotal))
                sentence = "Dein Ticket beginnt am \(KpiSpoken.date(ticket.start, now: now, calendar: calendar)) und gilt bis \(endDate)."
            } else if days.daysRemaining == 0 {
                value = KpiSpoken.days(0)
                sentence = "Heute ist der letzte Tag deines Tickets."
            } else {
                value = KpiSpoken.days(days.daysRemaining)
                sentence = "Dein Ticket gilt noch \(KpiSpoken.days(days.daysRemaining)), bis \(endDate)."
            }
        default:   // .costPerDay
            value = KpiSpoken.writtenEuro(days.costPerDay, format: FormatPrefs(amounts: format.amounts == .whole ? .whole : .cents,
                                                                                weekStart: format.weekStart, co2: format.co2))
            progress = nil
            sentence = ticket.price > 0
                ? "Dein Ticket kostet dich \(KpiSpoken.euro(days.costPerDay)) pro Tag: \(KpiSpoken.euro(ticket.price)) für \(KpiSpoken.days(days.daysTotal))."
                : "Dein Ticket kostet dich nichts: Dein Anteil am Ticketpreis ist 0 Euro."
        }
        return KpiAnswer(question: question, period: .ticketYear, status: .figure, sentence: note + sentence, value: value, label: label,
                         bars: [], progress: progress, isStale: false)
    }

    // MARK: Bars

    private static func metric(_ question: KpiQuestion, _ day: KpiDailyTable.Day) -> Double {
        switch question {
        case .trips: Double(day.journeys)
        case .value: day.value
        case .distance: day.km
        default: day.co2
        }
    }

    private static func dayBars(_ question: KpiQuestion, period: KpiPeriod, range: KpiPeriodRange, table: KpiDailyTable, now: Date,
                                calendar: Calendar) -> [KpiBar] {
        switch period {
        case .calendarYear:
            guard let parsed = KpiDailyTable.parse(dayKey: range.first),
                  let start = calendar.date(from: DateComponents(year: parsed.year, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: parsed.year, month: 12, day: 31)) else { return [] }
            return monthBars(question, from: start, to: end, days: nil, table: table, now: now, calendar: calendar)
        default:
            guard let parsed = KpiDailyTable.parse(dayKey: range.first),
                  var day = calendar.date(from: DateComponents(year: parsed.year, month: parsed.month, day: parsed.day)) else { return [] }
            let byDay = Dictionary(table.days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
            let today = KpiDailyTable.dayKey(now, calendar: calendar)
            var bars: [KpiBar] = []
            while bars.count < 31 {
                let key = KpiDailyTable.dayKey(day, calendar: calendar)
                guard key <= range.last, KpiDailyTable.parse(dayKey: key)?.month == parsed.month || period == .thisWeek else { break }
                let c = calendar.dateComponents([.day, .weekday], from: day)
                let label = period == .thisWeek ? AppearanceFormat.weekdayShort[((c.weekday ?? 2) + 5) % 7] : "\(c.day ?? 1)"
                bars.append(KpiBar(id: key, label: label, value: byDay[key].map { metric(question, $0) } ?? 0, isCurrent: key == today))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return bars
        }
    }

    /// One bar per calendar month from `start` through `end`, summing only the day keys in `days` (inclusive) when given.
    private static func monthBars(_ question: KpiQuestion, from start: Date, to end: Date, days: (first: String, last: String)?,
                                  table: KpiDailyTable, now: Date, calendar: Calendar) -> [KpiBar] {
        let first = calendar.dateComponents([.year, .month], from: start)
        let last = calendar.dateComponents([.year, .month], from: end)
        let current = calendar.dateComponents([.year, .month], from: now)
        guard var year = first.year, var month = first.month, let lastYear = last.year, let lastMonth = last.month else { return [] }
        var totals: [String: Double] = [:]
        for day in table.days where days.map({ day.day >= $0.first && day.day <= $0.last }) ?? true {
            totals[String(day.day.prefix(7)), default: 0] += metric(question, day)
        }
        var bars: [KpiBar] = []
        while (year, month) <= (lastYear, lastMonth), bars.count < 14 {
            let key = String(KpiDailyTable.dayKey(year: year, month: month, day: 1).prefix(7))
            bars.append(KpiBar(id: key, label: String(KpiSpoken.monthNames[month - 1].prefix(1)), value: totals[key] ?? 0,
                               isCurrent: year == current.year && month == current.month))
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return bars
    }

    /// „2026/27“, or „2026“ for a period inside one calendar year.
    static func ticketYear(_ ticket: KpiDailyTable.Ticket, calendar: Calendar) -> String {
        let a = calendar.component(.year, from: ticket.start), b = calendar.component(.year, from: ticket.end)
        return a == b ? "\(a)" : "\(a)/\(String(b % 100).count < 2 ? "0\(b % 100)" : String(b % 100))"
    }
}
