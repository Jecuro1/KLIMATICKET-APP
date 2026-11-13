import AppIntents
import Foundation
import KlimaCore

// Pendel-Modus (docs/COMMUTE.md §6): two Siri and Shortcuts actions. Neither makes a network request – nothing runs in the
// background but „Live verfolgen“ (docs/OEBB_LIVE.md §2). „Wann fährt mein nächster Zug?“ reads the connections the card
// fetched while the app was open (at most 15 minutes old) and otherwise answers from the plan, saying so.

/// „Wann fährt mein nächster Zug?“ – time, delay and platform of the next connection on the Stammstrecke.
struct CommuteNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächster Pendelzug"
    static let description = IntentDescription(
        "Sagt dir, wann dein nächster Zug auf deiner Stammstrecke fährt – mit Verspätung und Gleis, wenn KlimaBilanz sie gerade geladen hat.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(CommuteAnswer.next(now: Date()))")
    }
}

/// „Pendelfahrt erfassen“ – logs the Stammstrecke for now: as a round trip when that is the remembered choice, else in the
/// direction of the time of day.
struct CommuteLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Pendelfahrt erfassen"
    static let description = IntentDescription(
        "Erfasst deine Stammstrecke für heute – hin und retour, oder in der Richtung, die zur Tageszeit passt.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = CommuteSettingsStore.shared.settings
        guard settings.isActive, let origin = settings.origin, let destination = settings.destination else {
            return .result(dialog: "\(CommuteSpeech.notSetUp)")
        }
        let now = Date()
        let direction: CommuteDirection = settings.logsRoundTrip
            ? .outbound : CommuteWindow.direction(at: now, plan: settings.plan, calendar: .vienna)
        CommuteLogQueue.enqueue(PendingCommuteLog(date: now, direction: direction, isRoundTrip: settings.logsRoundTrip))
        let from = direction == .outbound ? origin.name : destination.name
        let to = direction == .outbound ? destination.name : origin.name
        let route = "\(TripRow.short(from)) – \(TripRow.short(to))\(settings.logsRoundTrip ? ", hin und retour" : "")"
        // The app is running with its store open: save now. Otherwise RootView saves it at the next activation.
        if let app = AppDelegate.appState, let container = AppDelegate.container {
            let added = await CommuteLogQueue.ingest(context: container.mainContext, app: app)
            if !added.isEmpty { return .result(dialog: "Erfasst: \(route).") }
        }
        return .result(dialog: "Vorgemerkt: \(route). KlimaBilanz speichert die Fahrt, sobald du die App öffnest.")
    }
}

/// The sentence for „Wann fährt mein nächster Zug?“.
@MainActor
enum CommuteAnswer {
    static func next(now: Date) -> String {
        let settings = CommuteSettingsStore.shared.settings
        guard settings.isActive, let origin = settings.origin, let destination = settings.destination else { return CommuteSpeech.notSetUp }
        let state = CommuteWindow.state(at: now, plan: settings.plan, calendar: .vienna)
        // The card's last search, when it is fresh and still has a connection ahead.
        if let snapshot = CommuteSnapshotStore.load(), now.timeIntervalSince(snapshot.fetchedAt) <= CommuteSnapshot.maxAge {
            let ahead = snapshot.rows.filter {
                ($0.isCancelled ? $0.plannedDeparture : $0.effectiveDeparture) >= now.addingTimeInterval(-CommuteStatus.graceSeconds)
            }
            if let text = CommuteSpeech.next(rows: ahead, destination: TripRow.short(snapshot.destinationName),
                                             fetchedAt: snapshot.fetchedAt, now: now) {
                return text
            }
        }
        let slot: CommuteSlot
        switch state {
        case .live(let s), .upcoming(let s): slot = s
        case .inactive: return CommuteSpeech.noWeekday
        }
        let consent = UserDefaults.standard.string(forKey: "liveConsent") ?? "undecided"
        let timetableOn = UserDefaults.standard.object(forKey: "liveTimetableEnabled") as? Bool ?? true
        // The Offline-Modus (Einstellungen › Funktionen) switches every live request off: opening the app would not help.
        let liveOn = consent == "granted" && timetableOn && !FeatureCenter.shared.offlineMode
        return CommuteSpeech.planned(slot: slot, origin: TripRow.short(origin.name), destination: TripRow.short(destination.name),
                                     now: now, calendar: .vienna, hint: liveOn ? .openApp : .liveOff)
    }
}
