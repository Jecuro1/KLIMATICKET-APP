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
    /// A newer tariffs document and/or relation pack was installed.
    case updated
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
        case .current: "Es liegen keine neueren Preise vor."
        case .updated: "Die neuen Preise gelten ab sofort."
        case .offline: "Deine Preise bleiben unverändert."
        case .failed: "Deine Preise bleiben unverändert. Versuch es später noch einmal."
        }
    }

    var isSuccess: Bool { self == .current || self == .updated }
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
    /// The freshness of the prices in the app today (Vienna time), from the catalogue in use and the last check.
    func tarifFreshness(now: Date = Date()) -> TariffFreshness.State {
        TariffFreshness.state(catalog: catalog, now: now, lastCheck: tariffs.lastRefresh)
    }

    /// Looks for a newer tariffs document, then for a newer relation pack. `force` is the button: it ignores the 12-hour and
    /// 24-hour limits, never the rule that only a newer version is installed.
    func checkTariffs(force: Bool) async -> TarifCheckResult {
        let outcome = await tariffs.refresh(manifestHint: updates.manifest, force: force)
        if outcome == .installed { reloadCatalog() }
        let pack = await refreshRelationPack(force: force)

        if outcome == .installed { return .updated }
        if case .installed = pack { return .updated }
        switch outcome {
        case .offline: return .offline
        case .failed, .notConfigured: return .failed
        case .installed, .upToDate, .throttled: break
        }
        switch pack {
        case .unreachable: return .offline
        case .rejected, .blockedURL: return .failed
        default: return .current
        }
    }

    /// The relation pack of the current catalogue: downloaded at most once per 24 hours (and only when its version is newer
    /// than the table in use), validated, installed atomically, then used with the next estimate.
    @discardableResult
    func refreshRelationPack(force: Bool) async -> RelationPackUpdater.Outcome {
        let result = await relationPacks.refresh(catalog: catalog, tariffsURL: tariffs.tariffsURL(manifestHint: updates.manifest),
                                                 bundled: relationsHolder.bundledTable, versionInUse: relationsHolder.versionInUse,
                                                 force: force)
        if let table = result.table {
            relationsHolder.install(table)
            reloadCatalog()   // estimates and the live price chain pick the new table up
        }
        return result.outcome
    }
}
