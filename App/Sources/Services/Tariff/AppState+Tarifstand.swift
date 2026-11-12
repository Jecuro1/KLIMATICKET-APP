import Foundation
import KlimaCore
import Observation

// MARK: tarifstand – "Jetzt prüfen" and the automatic refresh of the relation pack (docs/TARIFF_FRESHNESS.md).
// The refresh talks only to the owner's repository host (the tariffs document and the pack next to it), at most once per
// 24 hours for the pack, with a plain GET and no personal data. No ÖBB request is made here.

/// What "Jetzt prüfen" found – the four words the row can show.
enum TarifCheckResult: Equatable {
    /// The server answered and nothing newer exists.
    case current
    /// A newer tariffs document and/or relation pack was installed. `startsOn` is the day (ISO) a downloaded relation table
    /// takes over when that day lies ahead – it is held back until then, the old table stays right until the timetable change.
    case updated(startsOn: String?)
    /// No connection.
    case offline
    /// The server answered with something unusable (HTTP error, damaged or rejected file); the data in use is untouched.
    case failed

    var title: String {
        switch self {
        case .current: "Aktuell"
        case .updated: "Aktualisiert"
        case .offline: "Kein Netz"
        case .failed: "Fehlgeschlagen"
        }
    }

    var symbol: String {
        switch self {
        case .current: "checkmark.circle.fill"
        case .updated: "arrow.down.circle.fill"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// A short second line under the result.
    var detail: String {
        switch self {
        case .current: "Auf dem Server liegen keine neueren Preise."
        case .updated(let startsOn):
            if let startsOn, TariffFreshness.isISODay(startsOn) {
                "Neue Fahrpreise sind geladen und gelten ab \(TariffFreshness.germanDate(iso: startsOn))."
            } else {
                "Neue Preisdaten sind geladen."
            }
        case .offline: "Deine Preise bleiben unverändert."
        case .failed: "Deine Preise bleiben unverändert. Versuch es später noch einmal."
        }
    }

    var isSuccess: Bool {
        switch self {
        case .current, .updated: true
        case .offline, .failed: false
        }
    }
}

/// The state of one "Jetzt prüfen" button (the Settings row and the details sheet each own one).
@MainActor
@Observable
final class TarifCheck {
    enum Phase: Equatable {
        case idle, checking, finished(TarifCheckResult)

        var result: TarifCheckResult? {
            if case .finished(let result) = self { return result }
            return nil
        }
    }

    private(set) var phase: Phase

    /// Counts finished checks – the trigger of the result haptic.
    private(set) var finishedCount = 0

    /// `phase` is preset only by the CI screenshot hosts.
    init(phase: Phase = .idle) {
        self.phase = phase
    }

    /// Screenshot hosts show a finished check without running one (no network in CI).
    func preset(_ phase: Phase) {
        self.phase = phase
    }

    var isChecking: Bool { phase == .checking }

    func run(app: AppState) async {
        guard !isChecking else { return }
        phase = .checking
        let result = await app.checkTariffs(force: true)
        phase = .finished(result)
        finishedCount += 1
    }
}

extension AppState {
    /// Looks for a newer tariffs document, then for a newer relation pack. `force` is the button: it ignores the 12-hour and
    /// 24-hour limits, never the rule that only a newer version is installed.
    func checkTariffs(force: Bool) async -> TarifCheckResult {
        let outcome = await tariffs.refresh(manifestHint: updates.manifest, force: force)
        if outcome == .installed { reloadCatalog() }
        let pack = await refreshRelationPack(force: force)

        // A pack valid from a day that lies ahead is installed but not used yet: say from when it counts.
        if case .installed = pack.outcome { return .updated(startsOn: pack.startsOn) }
        if outcome == .installed { return .updated(startsOn: nil) }
        switch outcome {
        case .offline: return .offline
        case .failed, .notConfigured: return .failed
        case .installed, .upToDate, .throttled: break
        }
        switch pack.outcome {
        case .unreachable: return .offline
        case .rejected, .blockedURL: return .failed
        default: return .current
        }
    }

    /// The relation pack of the current catalogue: downloaded at most once per 24 hours (and only when its version is newer
    /// than the table in use), validated, installed atomically, then used with the next estimate – from its `validFrom` day
    /// on (`startsOn` is that day when it still lies ahead).
    @discardableResult
    func refreshRelationPack(force: Bool) async -> (outcome: RelationPackUpdater.Outcome, startsOn: String?) {
        let (bundled, versionInUse) = await relationsHolder.snapshot()
        let result = await relationPacks.refresh(catalog: catalog, tariffsURL: tariffs.tariffsURL(manifestHint: updates.manifest),
                                                 bundled: bundled, versionInUse: versionInUse, force: force)
        var startsOn: String?
        if let table = result.table {
            relationsHolder.install(table)
            if table.validFrom > TariffFreshness.isoDay(Date()) { startsOn = table.validFrom }
            reloadCatalog()   // estimates and the live price chain pick the new table up
        }
        return (result.outcome, startsOn)
    }
}
