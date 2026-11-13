import Foundation
import Observation
import KlimaCore

// MARK: automation – Einstellungen › Automatik (docs/AUTOMATION.md): what the rules keep on this device. Three versioned JSON
// values in UserDefaults – `rules.v1` (master switch, „Wochenende ruhig“, the rules), `rules.log.v1` („Zuletzt ausgelöst“, 30
// entries) and `rules.ledger.v1` (milestones per ticket, the reported follow, cooldowns, the newest trip seen). Nothing is
// synced or sent. Garbage reads as „no rules“. Screenshot and perf runs keep everything in memory (`install(demo:)`).

@MainActor
@Observable
final class AutoStore {
    static let shared = AutoStore()

    static let bookKey = "rules.v1"
    static let logKey = "rules.log.v1"
    static let ledgerKey = "rules.ledger.v1"

    private(set) var book: AutoRuleBook
    private(set) var log: AutoLog
    private(set) var ledger: AutoLedger
    /// A demo scene's clock (screenshots): every text of the screens is relative to it. nil = the real clock.
    private(set) var pinnedNow: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var persists: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        persists = !LaunchMode.isSandboxed
        if persists {
            book = AutoRuleBook.decode(defaults.data(forKey: Self.bookKey))
            log = AutoLog.decode(defaults.data(forKey: Self.logKey))
            ledger = AutoLedger.decode(defaults.data(forKey: Self.ledgerKey))
        } else {
            book = AutoRuleBook()
            log = AutoLog()
            ledger = AutoLedger()
        }
    }

    /// The clock of the screens: the demo's pinned moment or now.
    func now() -> Date { pinnedNow ?? Date() }

    var isDemo: Bool { pinnedNow != nil }

    // MARK: Book

    func setMaster(_ on: Bool) {
        mutateBook { $0.isEnabled = on }
    }

    func setQuietWeekend(_ on: Bool) {
        mutateBook { $0.quietWeekend = on }
    }

    /// Adds or replaces a rule (by id). A milestone rule that is switched on remembers what is reached already.
    func save(_ rule: AutoRule, ticket: AutoTicketFact?) {
        let rule = rule.normalized
        let previous = book.rules.first { $0.id == rule.id }
        mutateBook { book in
            if let index = book.rules.firstIndex(where: { $0.id == rule.id }) {
                book.rules[index] = rule
            } else if book.rules.count < AutoRuleBook.maxRules {
                book.rules.append(rule)
            }
        }
        let switchedOn = rule.isEnabled && (previous == nil || previous?.isEnabled == false || previous?.trigger != rule.trigger)
        guard switchedOn else { return }
        // What happened before the rule was on is not news: reached milestones are remembered, earlier trips are checked.
        let moment = self.now()
        mutateLedger { ledger in
            ledger.seedMilestones(rule: rule, ticket: ticket)
            if rule.trigger.kind == .tripLogged { ledger.tripWatermark = max(ledger.tripWatermark ?? moment, moment) }
        }
    }

    func setEnabled(_ id: UUID, _ on: Bool, ticket: AutoTicketFact?) {
        guard var rule = book.rules.first(where: { $0.id == id }) else { return }
        rule.isEnabled = on
        save(rule, ticket: ticket)
    }

    func delete(_ id: UUID) {
        mutateBook { $0.rules.removeAll { $0.id == id } }
        mutateLedger { $0.prune(keeping: Set(book.rules.map(\.id))) }
    }

    func rule(_ id: UUID) -> AutoRule? { book.rules.first { $0.id == id } }

    /// The rule a template made, if it is still there.
    func rule(template id: String) -> AutoRule? { book.rules.first { $0.templateID == id } }

    // MARK: Log and ledger

    func record(_ entry: AutoLogEntry) {
        var copy = log
        guard copy.record(entry) else { return }
        log = copy
        persist(log.entries.isEmpty ? nil : try? JSONEncoder().encode(log), key: Self.logKey)
    }

    func clearLog() {
        log = AutoLog()
        persist(nil, key: Self.logKey)
    }

    func mutateLedger(_ change: (inout AutoLedger) -> Void) {
        var copy = ledger
        change(&copy)
        guard copy != ledger else { return }
        ledger = copy
        persist(try? JSONEncoder().encode(ledger), key: Self.ledgerKey)
    }

    /// „Alle Daten löschen“: the rules, their log and ledger go.
    func deleteAll() {
        book = AutoRuleBook()
        log = AutoLog()
        ledger = AutoLedger()
        for key in [Self.bookKey, Self.logKey, Self.ledgerKey] { persist(nil, key: key) }
    }

    // MARK: Demo

    /// Screenshot scenes: fixed rules, log and clock, never written to UserDefaults.
    func install(demo book: AutoRuleBook, log: AutoLog, ledger: AutoLedger, now: Date) {
        persists = false
        self.book = book
        self.log = log
        self.ledger = ledger
        pinnedNow = now
    }

    // MARK: Storage

    private func mutateBook(_ change: (inout AutoRuleBook) -> Void) {
        var copy = book
        change(&copy)
        guard copy != book else { return }
        book = copy
        persist(book.encoded(), key: Self.bookKey)
    }

    private func persist(_ data: Data?, key: String) {
        guard persists else { return }
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
