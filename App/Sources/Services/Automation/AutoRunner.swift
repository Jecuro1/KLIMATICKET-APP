import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications
import KlimaCore

// MARK: automation – runs the rules of Einstellungen › Automatik (docs/AUTOMATION.md). The honest promise of the feature: a rule
// can only fire when the app is open, when a „Live verfolgen“ answer arrives (also in the background refresh the follow asks
// for anyway), after a save, or as a local notification planned in advance. The runner never writes a trip and never makes a
// request: it reads the store (AutoSnapshot), the follow's last answer, and asks AutoRuleEngine.
//
// Hooks (one marked line each): RootView scene active → `sceneBecameActive`, CommitEffects after a save → `didCommit`,
// LiveFollowTracker after an answer → `followUpdated`, AppDelegate → `presentInApp` / `handleResponse`.

@MainActor
@Observable
final class AutoRunner {
    static let shared = AutoRunner()

    /// The notices planned for the next 14 days (and the deadlines), with what did not fit.
    private(set) var plan = AutoPlan()
    /// The facts of the last check (rows, Testlauf).
    private(set) var state = AutoState()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Notices iOS refused at the last reconcile (its own limit of pending notifications).
    private(set) var refusedCount = 0
    /// „Regel ansehen“ from a notice: RootView presents the rule list.
    var showsRulesSheet = false
    /// A plan was made at least once (before that, a row says nothing rather than something wrong).
    private(set) var isPlanned = false

    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var demoState: AutoState?

    private var store: AutoStore { .shared }
    private var calendar: Calendar { .vienna }

    /// Screenshot and perf runs, and demo scenes: nothing is asked, planned or posted.
    private var isInert: Bool { LaunchMode.isSandboxed || store.isDemo }

    // MARK: Hooks

    /// Launch and every return to the foreground: what iOS delivered goes into the log, then the plan is made again (a day
    /// that got a trip loses its evening notice).
    func sceneBecameActive(context: ModelContext, app: AppState) {
        guard !isInert else { return }
        enqueue { [weak self] in
            guard let self else { return }
            await self.harvestDelivered()
            await self.replan(context: context, app: app)
        }
    }

    /// After every successful save (CommitEffects): milestones and „Fahrt erfasst“ are checked, then the plan follows.
    /// Coalesced like the widget refresh, so a burst of saves is one check.
    func didCommit(context: ModelContext, app: AppState) {
        guard !isInert else { return }
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.enqueue { await self.runCommit(context: context, app: app) }
        }
    }

    /// After every answer of „Live verfolgen“ (foreground polling and the background refresh). Uses that answer only.
    func followUpdated(target: LiveFollowTarget, snapshot: LiveFollowSnapshot) {
        guard !isInert else { return }
        let rules = store.book.activeRules.filter { $0.trigger.kind == .followDelay }
        guard !rules.isEmpty else { return }
        let fact = Self.followFact(target: target, snapshot: snapshot, updatedAt: Date())
        enqueue { [weak self] in
            guard let self else { return }
            let now = Date()
            for rule in rules {
                let state = AutoState(follow: fact, ledger: self.store.ledger, quietWeekend: self.store.book.quietWeekend)
                let verdict = AutoRuleEngine.evaluate(rule, event: .followUpdated, state: state, now: now, calendar: self.calendar)
                await self.handle(verdict, rule: rule, app: AppDelegate.appState)
            }
        }
    }

    /// The rules changed (editor, switch, template, master switch). `asksPermission`: a rule was switched on – the system
    /// asks once, as for the route reminders.
    func rulesChanged(asksPermission: Bool) {
        guard !isInert else {
            refreshDemoPlan()
            return
        }
        enqueue { [weak self] in
            guard let self, let context = AppDelegate.container?.mainContext, let app = AppDelegate.appState else { return }
            if asksPermission, !self.store.book.activeRules.isEmpty {
                self.authorization = await AutoNotifications.requestIfUndetermined()
            }
            await self.replan(context: context, app: app)
        }
    }

    /// „Alle Daten löschen“: rules, log, ledger and every planned rule notice go.
    func deleteAll() {
        store.deleteAll()
        plan = AutoPlan()
        guard !isInert else { return }
        Task { await AutoNotifications.removeAllPending() }
    }

    // MARK: Screens

    /// The Testlauf: the engine's own verdict for `rule` now, from the current facts (the follow's last answer included),
    /// with those facts (the card names what it read).
    func probe(_ rule: AutoRule) -> AutoProbe {
        let now = store.now()
        let facts = freshState(now: now)
        return AutoProbe(verdict: AutoRuleEngine.evaluate(rule, event: .probe, state: facts, now: now, calendar: calendar), state: facts)
    }

    /// The line under a rule („nächste: Mo 19:00“).
    func nextLine(_ rule: AutoRule) -> String {
        guard isPlanned else { return "wird geplant …" }
        return AutoText.nextLine(rule: rule, plan: plan, state: state, now: store.now(), calendar: calendar)
    }

    var budgetWarning: String? {
        AutoText.budgetWarning(plan, ruleNames: Dictionary(store.book.rules.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }))
    }

    /// The active ticket's facts (a milestone rule that is switched on remembers what is reached already).
    var currentTicket: AutoTicketFact? { freshState(now: store.now()).ticket }

    /// Reads permission and plan again (the screen appears, the user returns from the iOS settings).
    func refreshForScreen() async {
        guard !isInert else {
            refreshDemoPlan()
            return
        }
        authorization = await AutoNotifications.authorization()
        if let context = AppDelegate.container?.mainContext, let app = AppDelegate.appState {
            enqueue { [weak self] in await self?.replan(context: context, app: app) }
        }
    }

    // MARK: Demo

    /// Demo scenes: fixed facts and the plan made from them; no system call.
    func install(demoState: AutoState, authorization: UNAuthorizationStatus) {
        self.demoState = demoState
        self.authorization = authorization
        refreshDemoPlan()
    }

    private func refreshDemoPlan() {
        let now = store.now()
        var facts = demoState ?? AutoState()
        facts.ledger = store.ledger
        facts.quietWeekend = store.book.quietWeekend
        state = facts
        plan = AutoRuleScheduler.plan(rules: store.book.activeRules, state: facts, now: now, calendar: calendar)
        isPlanned = true
    }

    // MARK: Notices in the app

    /// A rule notice arrives while the app is in front (AppDelegate.willPresent): a planned one is checked once more (a trip
    /// may have been logged since it was planned) and shown as a toast instead of a banner. It stays in the Notification
    /// Center list.
    func presentInApp(_ incoming: AutoIncoming) async -> UNNotificationPresentationOptions {
        guard let ruleID = incoming.ruleID, let rule = store.rule(ruleID) else { return [.banner, .sound, .list] }
        if AutoRuleScheduler.parse(incoming.identifier) != nil, let context = AppDelegate.container?.mainContext, let app = AppDelegate.appState {
            let now = Date()
            let facts = AutoSnapshot.state(context: context, catalog: app.catalog, selectedTicketID: app.settings.selectedTicketID,
                                           ledger: store.ledger, quietWeekend: store.book.quietWeekend, follow: Self.currentFollowFact(),
                                           now: now)
            let verdict = AutoRuleEngine.evaluate(rule, event: .slotDue(incoming.date), state: facts, now: now, calendar: calendar)
            guard verdict.fires else {
                record(id: incoming.identifier, rule: rule, at: now, title: incoming.title,
                       detail: AutoText.explanation(verdict, calendar: calendar), channel: .cancelled)
                return []
            }
        }
        if let app = AppDelegate.appState {
            showToast(title: incoming.title, body: incoming.body, kind: rule.trigger.kind, opensAddTrip: incoming.opensAddTrip,
                      from: incoming.from, to: incoming.to, shortcut: incoming.shortcut, app: app)
        }
        record(id: incoming.identifier, rule: rule, at: incoming.date, title: incoming.title, detail: incoming.body, channel: .inApp)
        NoticeHistoryStore.record(DeliveredNotice(id: incoming.identifier, kind: .automation, title: incoming.title,
                                                  body: incoming.body, deliveredAt: incoming.date))
        return [.list]
    }

    /// A tap on a rule notice or one of its buttons (AppDelegate.didReceive, the store is open).
    func handleResponse(_ incoming: AutoIncoming, action: String, app: AppState) {
        switch action {
        case AutoNotifications.viewAction:
            openRules(app: app)
        case AutoNotifications.shortcutAction:
            if let name = incoming.shortcut { Self.openShortcut(name) }
        default:
            if incoming.opensAddTrip {
                var draft = TripDraft()
                draft.fromStationID = incoming.from
                draft.toStationID = incoming.to
                app.presentAddTripFromOutside(draft)
                return
            }
            switch incoming.kind {
            case .ticketDeadline: app.selectedTab = .ticket
            case .followDelay: app.selectedTab = .planner
            case .tripLogged: app.selectedTab = .trips
            default: app.selectedTab = .overview
            }
        }
    }

    /// „Regel ansehen“: Einstellungen closes first (two sheets cannot be up at once), then the rule list opens.
    private func openRules(app: AppState) {
        guard app.isShowingSettings else {
            showsRulesSheet = true
            return
        }
        app.isShowingSettings = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.showsRulesSheet = true
        }
    }

    /// Opens the Kurzbefehle app with the shortcut. iOS shows that app – this is never silent.
    static func openShortcut(_ name: String) {
        var parts = URLComponents()
        parts.scheme = "shortcuts"
        parts.host = "run-shortcut"
        parts.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = parts.url else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Work

    /// Runs one piece of work after the previous one (a save and a return to the foreground never plan at the same time).
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func runCommit(context: ModelContext, app: AppState) async {
        let now = Date()
        let active = store.book.activeRules
        guard !active.isEmpty else { return }   // no rule, no work after a save
        let rules = active.filter { $0.trigger.kind == .milestone || $0.trigger.kind == .tripLogged }
        if !rules.isEmpty {
            let facts = AutoSnapshot.state(context: context, catalog: app.catalog, selectedTicketID: app.settings.selectedTicketID,
                                           ledger: store.ledger, quietWeekend: store.book.quietWeekend, follow: nil, now: now,
                                           includeNewTrips: true)
            for rule in rules {
                var ruleFacts = facts
                ruleFacts.ledger = store.ledger
                let verdict = AutoRuleEngine.evaluate(rule, event: .committed, state: ruleFacts, now: now, calendar: calendar)
                await handle(verdict, rule: rule, app: app)
            }
            // Trips saved up to now are checked.
            store.mutateLedger { $0.tripWatermark = now }
        }
        // A planned evening notice of a day that just got a trip is taken back.
        if active.contains(where: { $0.trigger.isScheduled }) || !plan.slots.isEmpty { await replan(context: context, app: app) }
    }

    /// Delivers the firings of a verdict; the ledger takes its marks once a firing reached the user (or when it only
    /// records a recovery).
    private func handle(_ verdict: AutoVerdict, rule: AutoRule, app: AppState?) async {
        guard !verdict.firings.isEmpty else {
            if !verdict.marks.isEmpty { store.mutateLedger { $0.apply(verdict.marks) } }
            return
        }
        var delivered = false
        for firing in verdict.firings {
            if await deliver(firing, kind: rule.trigger.kind, app: app) { delivered = true }
        }
        if delivered { store.mutateLedger { $0.apply(verdict.marks) } }
    }

    /// In the open app a toast with its haptic; otherwise a local notification right away (only with the permission).
    private func deliver(_ firing: AutoFiring, kind: AutoTriggerKind, app: AppState?) async -> Bool {
        let identifier = AutoRuleScheduler.immediateIdentifier(ruleID: firing.ruleID, at: firing.at, calendar: calendar)
        let rule = store.rule(firing.ruleID)
        if UIApplication.shared.applicationState == .active, let app {
            showToast(title: firing.title, body: firing.body, kind: kind, opensAddTrip: firing.opensAddTrip,
                      from: firing.addTripFrom, to: firing.addTripTo, shortcut: firing.shortcutName, app: app)
            if let rule { record(id: identifier, rule: rule, at: firing.at, title: firing.title, detail: firing.explanation, channel: .inApp) }
            NoticeHistoryStore.record(DeliveredNotice(id: identifier, kind: .automation, title: firing.title, body: firing.body,
                                                      deliveredAt: firing.at))
            return true
        }
        guard await AutoNotifications.post(firing, kind: kind, identifier: identifier) else { return false }
        if let rule { record(id: identifier, rule: rule, at: firing.at, title: firing.title, detail: firing.explanation, channel: .notification) }
        return true
    }

    private func showToast(title: String, body: String, kind: AutoTriggerKind, opensAddTrip: Bool, from: String?, to: String?,
                           shortcut: String?, app: AppState) {
        let haptic: Haptic = kind == .milestone ? .milestone : .tap
        if opensAddTrip {
            app.showToast(kind.autoSymbol, title, body, actionTitle: "Erfassen", haptic: haptic) {
                var draft = TripDraft()
                draft.fromStationID = from
                draft.toStationID = to
                app.presentAddTripFromOutside(draft)
            }
        } else if let shortcut {
            app.showToast(kind.autoSymbol, title, body, actionTitle: "Kurzbefehl", haptic: haptic) { Self.openShortcut(shortcut) }
        } else {
            app.showToast(kind.autoSymbol, title, body, haptic: haptic)
        }
    }

    private func record(id: String, rule: AutoRule, at: Date, title: String, detail: String, channel: AutoLogEntry.Channel) {
        store.record(AutoLogEntry(id: id, ruleID: rule.id, ruleName: rule.name, at: at, title: title, detail: detail, channel: channel))
    }

    /// Planned notices iOS delivered while the app was closed go into the log (once each).
    private func harvestDelivered() async {
        for notification in await AutoNotifications.delivered() {
            let request = notification.request
            guard let ruleID = AutoRuleScheduler.ruleID(of: request.identifier), !store.log.contains(id: request.identifier) else { continue }
            let name = store.rule(ruleID)?.name ?? request.content.subtitle.replacingOccurrences(of: "Automatik · ", with: "")
            store.record(AutoLogEntry(id: request.identifier, ruleID: ruleID, ruleName: name, at: notification.date,
                                      title: request.content.title, detail: request.content.body, channel: .delivered))
        }
    }

    /// Makes the plan from fresh facts and brings iOS's pending notices in line (only with the permission).
    private func replan(context: ModelContext, app: AppState) async {
        let now = Date()
        let facts: AutoState
        if store.book.rules.isEmpty {
            // Nothing to read from the store; only leftovers of deleted rules may still be pending.
            facts = AutoState(ledger: store.ledger, quietWeekend: store.book.quietWeekend)
        } else {
            facts = AutoSnapshot.state(context: context, catalog: app.catalog, selectedTicketID: app.settings.selectedTicketID,
                                       ledger: store.ledger, quietWeekend: store.book.quietWeekend, follow: Self.currentFollowFact(),
                                       now: now)
        }
        state = facts
        plan = AutoRuleScheduler.plan(rules: store.book.activeRules, state: facts, now: now, calendar: calendar)
        isPlanned = true
        authorization = await AutoNotifications.authorization()
        guard AutoNotifications.isAllowed(authorization) else { return }
        let pending = await AutoNotifications.pending()
        guard !pending.isEmpty || !plan.slots.isEmpty else { return }
        let changes = AutoRuleScheduler.reconcile(pending: pending, plan: plan, state: facts, calendar: calendar)
        for cancelled in changes.cancelledForTrip {
            guard let parsed = AutoRuleScheduler.parse(cancelled.id), let rule = store.rule(parsed.ruleID) else { continue }
            record(id: "cancel." + cancelled.id, rule: rule, at: now, title: cancelled.title,
                   detail: "Abgesagt: an diesem Tag ist schon eine Fahrt erfasst.", channel: .cancelled)
        }
        guard !changes.isEmpty else { return }
        let kinds = Dictionary(store.book.rules.map { ($0.id, $0.trigger.kind) }, uniquingKeysWith: { a, _ in a })
        refusedCount = await AutoNotifications.apply(changes, kinds: kinds)
    }

    private func freshState(now: Date) -> AutoState {
        guard !isInert else {
            var facts = demoState ?? AutoState()
            facts.ledger = store.ledger
            facts.quietWeekend = store.book.quietWeekend
            return facts
        }
        guard let context = AppDelegate.container?.mainContext, let app = AppDelegate.appState else { return state }
        return AutoSnapshot.state(context: context, catalog: app.catalog, selectedTicketID: app.settings.selectedTicketID,
                                  ledger: store.ledger, quietWeekend: store.book.quietWeekend, follow: Self.currentFollowFact(), now: now)
    }

    // MARK: Follow

    static func currentFollowFact() -> AutoFollowFact? {
        let tracker = LiveFollowTracker.shared
        guard let target = tracker.target, let snapshot = tracker.snapshot else { return nil }
        return followFact(target: target, snapshot: snapshot, updatedAt: tracker.updatedAt ?? Date())
    }

    /// The delay at the alighting stop (arrival, else departure) – not the run's latest delay elsewhere.
    static func followFact(target: LiveFollowTarget, snapshot: LiveFollowSnapshot, updatedAt: Date) -> AutoFollowFact {
        let stop = snapshot.alighting
        let seconds = stop?.arrival?.delaySeconds ?? stop?.departure?.delaySeconds
        return AutoFollowFact(tripID: target.tripID, lineName: target.lineName, stopName: stop?.location.name ?? target.alightStop.name,
                              delayMinutes: AutoFollowFact.minutes(fromDelaySeconds: seconds), isFinished: snapshot.stage.isFinished,
                              updatedAt: updatedAt)
    }
}

/// A Testlauf: the verdict and the facts it was made from.
struct AutoProbe: Equatable {
    let verdict: AutoVerdict
    let state: AutoState
}

/// What the app needs of a rule notice, read before it crosses to the main actor.
struct AutoIncoming: Sendable {
    let identifier: String
    let title: String
    let body: String
    let date: Date
    let ruleID: UUID?
    let kind: AutoTriggerKind?
    let opensAddTrip: Bool
    let from: String?
    let to: String?
    let shortcut: String?

    /// nil for a notice that is not a rule's.
    init?(_ notification: UNNotification) {
        let request = notification.request
        guard request.identifier.hasPrefix(AutoRuleScheduler.identifierPrefix) else { return nil }
        let info = request.content.userInfo
        identifier = request.identifier
        title = request.content.title
        body = request.content.body
        date = notification.date
        ruleID = AutoRuleScheduler.ruleID(of: request.identifier)
        kind = (info[AutoNotifications.kindKey] as? String).flatMap(AutoTriggerKind.init(rawValue:))
        opensAddTrip = info[AutoNotifications.opensAddTripKey] as? Bool ?? false
        from = info[AutoNotifications.fromKey] as? String
        to = info[AutoNotifications.toKey] as? String
        shortcut = info[AutoNotifications.shortcutKey] as? String
    }
}
