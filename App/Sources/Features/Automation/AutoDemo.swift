import SwiftUI
import UserNotifications
import KlimaCore

// MARK: automation – CI scenes of Einstellungen › Automatik (`-KBScreenshot <screen> -KBDemo YES`): a pinned clock (Thursday
// 12 Nov 2026, 17:42 Vienna), synthetic rules, facts and log. No system notification is read, asked or planned, no network.
// - `automationList`: the screen with five rules, the 16 places and the templates
// - `automationEditor`: the editor of „Abendcheck“ (the sentence, its tokens, the trigger's values)
// - `automationTest`: the editor of „Verspätung melden“ with the Testlauf run (RJ 66, 12 Min late at Innsbruck Hbf)
// - `automationLog`: „Zuletzt ausgelöst“ with in-app, notice, delivered and cancelled entries
// - `automationBudget`: more planned moments than places – the full bar and the warning
// - `automationAX5`: the screen at the largest text size, `automationAX5Rows` scrolled to the rules
// - `automationListBottom`: the lower part (templates, „Zuletzt ausgelöst“)
// - `automationEditorBottom`: the editor of „Große Fahrt“ scrolled down (filter, conditions, „Dann“, name)

enum AutoDemo {
    static let now: Date = {
        Calendar.vienna.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 17, minute: 42)) ?? Date()
    }()

    static let eveningID = UUID(uuidString: "A0D0C0DE-0000-4000-8000-000000000001") ?? UUID()
    static let delayID = UUID(uuidString: "A0D0C0DE-0000-4000-8000-000000000002") ?? UUID()
    static let milestoneID = UUID(uuidString: "A0D0C0DE-0000-4000-8000-000000000003") ?? UUID()
    static let deadlineID = UUID(uuidString: "A0D0C0DE-0000-4000-8000-000000000004") ?? UUID()
    static let bigTripID = UUID(uuidString: "A0D0C0DE-0000-4000-8000-000000000005") ?? UUID()

    private static func at(_ days: Int, _ hour: Int, _ minute: Int) -> Date {
        let day = Calendar.vienna.date(byAdding: .day, value: days, to: Calendar.vienna.startOfDay(for: now)) ?? now
        return AutoClock.moment(on: day, minuteOfDay: hour * 60 + minute, calendar: .vienna) ?? now
    }

    static var rules: [AutoRule] {
        [
            AutoRule(id: eveningID, name: "Abendcheck", trigger: .dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 19 * 60),
                     actions: [.notify(title: "", body: ""), .openAddTrip(fromStationID: nil, toStationID: nil)],
                     createdAt: at(-20, 9, 0), templateID: AutoTemplates.eveningID),
            AutoRule(id: delayID, name: "Verspätung melden", trigger: .followDelay(minutes: 10), conditions: [.weekdays(AutoClock.workdays)],
                     cooldownMinutes: 30, createdAt: at(-18, 9, 0), templateID: AutoTemplates.delayID),
            AutoRule(id: milestoneID, name: "Meilensteine feiern", trigger: .milestone(percents: [50, 75, 100]),
                     createdAt: at(-40, 9, 0), templateID: AutoTemplates.milestonesID),
            AutoRule(id: deadlineID, name: "30 Tage vor Ablauf", trigger: .ticketDeadline(daysBefore: 30),
                     createdAt: at(-60, 9, 0), templateID: AutoTemplates.deadlineID),
            AutoRule(id: bigTripID, name: "Große Fahrt", isEnabled: false, trigger: .tripLogged(AutoTripFilter(minValueEUR: 20)),
                     conditions: [.timeWindow(startMinute: 6 * 60, endMinute: 22 * 60)], createdAt: at(-5, 9, 0)),
        ]
    }

    /// `automationBudget`: two daily rules and a working-day one want 38 moments in 14 days – more than the 16 places.
    static var busyRules: [AutoRule] {
        let all = Set(RouteWeekday.allCases)
        return rules.filter { $0.id != eveningID } + [
            AutoRule(id: eveningID, name: "Abendcheck", trigger: .dayWithoutTrip(weekdays: all, minuteOfDay: 19 * 60), createdAt: at(-20, 9, 0)),
            AutoRule(name: "Morgengruß", trigger: .dayWithoutTrip(weekdays: all, minuteOfDay: 7 * 60 + 30), createdAt: at(-3, 9, 0)),
            AutoRule(name: "Mittags nachtragen", trigger: .dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 12 * 60 + 15), createdAt: at(-2, 9, 0)),
        ]
    }

    static var ledger: AutoLedger {
        var ledger = AutoLedger(tripWatermark: at(0, 17, 0))
        ledger.apply([.milestones(ruleID: milestoneID, ticketID: ticketID, percents: [50]), .fired(ruleID: delayID, at: at(-1, 7, 31))])
        return ledger
    }

    private static let ticketID = "DEMO-TICKET"

    /// KlimaTicket Ö Klassik, 61 % amortised, valid until 28 Feb 2027; no trip today; RJ 66 followed, 12 Min late at Innsbruck Hbf.
    static var state: AutoState {
        AutoState(ticket: AutoTicketFact(id: ticketID, name: "KlimaTicket Ö Klassik", start: at(-256, 0, 0),
                                         end: Calendar.vienna.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 23, minute: 59, second: 59)) ?? now,
                                         amortizedFraction: 0.614, price: 1400, value: 859.6),
                  tripDays: [AutoClock.dayKey(at(1, 7, 20), calendar: .vienna)],
                  lastTrip: AutoTripFact(id: UUID(), date: at(-1, 17, 12), createdAt: at(-1, 17, 40), fromName: "Innsbruck Hbf",
                                         toName: "St. Anton am Arlberg", fromStationID: nil, toStationID: nil, modes: [.train], value: 23.5),
                  follow: AutoFollowFact(tripID: "demo|RJ66", lineName: "RJ 66", stopName: "Innsbruck Hbf", delayMinutes: 12,
                                         isFinished: false, updatedAt: at(0, 17, 41)))
    }

    static var log: AutoLog {
        func entry(_ id: String, _ rule: UUID, _ name: String, _ date: Date, _ title: String, _ detail: String,
                   _ channel: AutoLogEntry.Channel) -> AutoLogEntry {
            AutoLogEntry(id: id, ruleID: rule, ruleName: name, at: date, title: title, detail: detail, channel: channel)
        }
        return AutoLog(entries: [
            entry("d1", delayID, "Verspätung melden", at(0, 7, 31), "Verspätung 12 Min",
                  "Ausgelöst: Verspätung 12 Min ist mindestens 10 Min (RJ 66, Ausstieg Innsbruck Hbf), Bedingungen erfüllt, kein Cooldown",
                  .inApp),
            entry("d2", eveningID, "Abendcheck", at(-1, 19, 0), "Heute noch keine Fahrt erfasst",
                  "Warst du heute mit den Öffis unterwegs? Tippe hier und trag die Fahrt nach.", .delivered),
            entry("d3", eveningID, "Abendcheck", at(-2, 17, 48), "Heute noch keine Fahrt erfasst",
                  "Abgesagt: an diesem Tag ist schon eine Fahrt erfasst.", .cancelled),
            entry("d4", milestoneID, "Meilensteine feiern", at(-4, 8, 5), "50 % geschafft",
                  "Ausgelöst: 50 % amortisiert – 50 % ist erreicht und für dieses Ticket noch nicht gefeiert", .inApp),
            entry("d5", delayID, "Verspätung melden", at(-6, 18, 12), "Verspätung 15 Min",
                  "Ausgelöst: Verspätung 15 Min ist mindestens 10 Min (REX 5, Ausstieg Landeck-Zams), Bedingungen erfüllt, kein Cooldown",
                  .notification),
        ])
    }

    /// Installs a scene: the rules, the log, the ledger and the facts, with the clock pinned.
    @MainActor
    static func install(_ screen: String) {
        let book = AutoRuleBook(isEnabled: true, quietWeekend: false, rules: screen == "automationBudget" ? busyRules : rules)
        AutoStore.shared.install(demo: book, log: log, ledger: ledger, now: now)
        AutoRunner.shared.install(demoState: state, authorization: .authorized)
    }
}

/// Routes the CI scenes (RootView's ScreenshotRouter, `// MARK: automation`).
struct AutoScreenshotHost: View {
    static let screens: Set<String> = [
        "automationList", "automationEditor", "automationTest", "automationLog", "automationBudget", "automationAX5",
        "automationAX5Rows", "automationListBottom", "automationEditorBottom",
    ]

    let screen: String
    @State private var isReady = false

    var body: some View {
        NavigationStack {
            if isReady { content }
        }
        .defaultScrollAnchor(anchor)
        .defaultScrollAnchor(anchor, for: .sizeChanges)   // the rows arrive after the first frame
        .dynamicTypeSize(screen.hasPrefix("automationAX5") ? .accessibility5 : .large)
        .onAppear {
            AutoDemo.install(screen)
            isReady = true
        }
    }

    private var anchor: UnitPoint? {
        switch screen {
        case "automationListBottom", "automationEditorBottom": .bottom
        case "automationAX5Rows": .center
        default: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "automationEditorBottom":
            AutoRuleEditorView(rule: AutoStore.shared.rule(AutoDemo.bigTripID) ?? AutoDemo.rules[4], isNew: false)
        case "automationEditor":
            AutoRuleEditorView(rule: AutoStore.shared.rule(AutoDemo.eveningID) ?? AutoDemo.rules[0], isNew: false)
        case "automationTest":
            AutoRuleEditorView(rule: AutoStore.shared.rule(AutoDemo.delayID) ?? AutoDemo.rules[1], isNew: false, runsTestOnAppear: true)
        case "automationLog":
            AutoLogView()
        default:
            AutoRulesView()
        }
    }
}

/// „Regel ansehen“ from a notice: the rule list as a sheet over the app (RootView, `// MARK: automation`).
struct AutoRulesSheetHost: ViewModifier {
    @Bindable private var runner = AutoRunner.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: $runner.showsRulesSheet) {
            NavigationStack { AutoRulesView(isSheet: true) }
        }
    }
}

extension View {
    func autoRulesSheetHost() -> some View { modifier(AutoRulesSheetHost()) }
}

/// Einstellungen › Automatik: the entry row with the state in its subtitle.
struct SetAutomationSection: View {
    private var store: AutoStore { .shared }
    private var runner: AutoRunner { .shared }

    var body: some View {
        Section {
            NavigationLink {
                AutoRulesView()
            } label: {
                SetRowLabel(title: "Automatik", subtitle: subtitle, symbol: "wand.and.sparkles", tint: Theme.dusk)
                    .setSymbolOnEnable(store.book.isEnabled && store.book.rules.contains(where: \.isEnabled))
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Automatik")
        }
    }

    private var subtitle: String {
        let active = store.book.rules.filter(\.isEnabled).count
        guard !store.book.rules.isEmpty else { return "Eigene Regeln: „Wenn … dann …“" }
        guard store.book.isEnabled else { return "Aus · \(store.book.rules.count) \(store.book.rules.count == 1 ? "Regel" : "Regeln") gespeichert" }
        var text = active == 1 ? "1 Regel aktiv" : "\(active) Regeln aktiv"
        if let next = runner.plan.slots.first { text += " · nächste \(AutoText.whenShort(next.fireAt, now: store.now(), calendar: .vienna))" }
        return text
    }
}
