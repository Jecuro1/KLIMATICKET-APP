import SwiftUI
import KlimaCore

// MARK: uebersicht – „Übersicht nach Maß“ (docs/DASHBOARD_LAYOUT.md). The app side of the layout, the picked figures and the goals:
// four small JSON values in UserDefaults (`dash.layout.v1`, `dash.kpis.v1`, `goals.v1`, `goals.ledger.v1`; not synced, the daily
// backup carries them through its `dash.` and `goals.` prefixes). Screenshot and perf runs start from the defaults and store nothing.

@Observable
@MainActor
final class DashLayoutStore {
    static let shared = DashLayoutStore()

    private(set) var layout: DashLayout {
        didSet { if layout != oldValue { write(layout.encoded(), DashLayout.storageKey) } }
    }

    private(set) var kpis: KpiSelection {
        didSet { if kpis != oldValue { write(kpis.encoded(), KpiSelection.storageKey) } }
    }

    private(set) var goals: GoalList {
        didSet { if goals != oldValue { write(goals.encoded(), GoalList.storageKey) } }
    }

    /// Which goal popped in which period – read and written by the goals card only.
    @ObservationIgnored private var ledger: GoalLedger

    /// The editor sheet over the Übersicht (the bottom button and „Bearbeiten“ on the cards open it).
    var isEditing = false
    /// The editor opens at this part (`DashEditorFocus`).
    var editorFocus: DashEditorFocus?
    /// A goal was saved / deleted – the editor plays .success / .warning once (its sheet has closed by then).
    private(set) var goalSaveTick = 0
    private(set) var goalDeleteTick = 0
    /// CI scenes: the editor opens at full height.
    @ObservationIgnored var editorStartsLarge = false

    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = LaunchMode.isSandboxed ? nil : .standard) {
        self.defaults = defaults
        layout = DashLayout.decode(defaults?.data(forKey: DashLayout.storageKey))
        kpis = KpiSelection.decode(defaults?.data(forKey: KpiSelection.storageKey))
        goals = GoalList.decode(defaults?.data(forKey: GoalList.storageKey))
        ledger = GoalLedger.decode(defaults?.data(forKey: GoalLedger.storageKey))
    }

    private func write(_ data: Data, _ key: String) {
        defaults?.set(data, forKey: key)
    }

    /// Something differs from a fresh install (the editor's „Zurücksetzen“ is enabled then).
    var isCustomized: Bool { !layout.isStandard }

    // MARK: Layout

    func setHidden(_ id: DashSectionID, _ hidden: Bool) {
        var next = layout
        next.setHidden(id, hidden)
        withMotion(Motion.smooth) { layout = next }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = layout
        next.move(fromOffsets: source, toOffset: destination)
        withMotion(Motion.smooth) { layout = next }
    }

    /// VoiceOver „Nach oben“ / „Nach unten“. False at the edge.
    @discardableResult
    func move(_ id: DashSectionID, up: Bool) -> Bool {
        var next = layout
        let moved = up ? next.moveUp(id) : next.moveDown(id)
        guard moved else { return false }
        withMotion(Motion.smooth) { layout = next }
        return true
    }

    /// A ready-made layout; „Zahlen“ and „Alles“ pick the four default figures when none is picked yet.
    func apply(_ preset: DashPreset) {
        withMotion(Motion.smooth) {
            layout = preset.layout
            if preset.fillsEmptyKpis, kpis.kinds.isEmpty { kpis = KpiSelection(KpiCatalog.defaultTiles) }
        }
    }

    /// Order and visibility as shipped; the figures and goals stay.
    func resetLayout() {
        withMotion(Motion.smooth) { layout = .standard }
    }

    // MARK: Figures

    /// Picks or drops a figure. Picking one also shows the Kennzahlen card if it was hidden. False when four are picked.
    @discardableResult
    func toggleKpi(_ kind: KpiKind) -> Bool {
        var next = kpis
        guard next.toggle(kind) else { return false }
        withMotion(Motion.smooth) {
            kpis = next
            if next.contains(kind), layout.isHidden(.kpis) {
                var shown = layout
                shown.setHidden(.kpis, false)
                layout = shown
            }
        }
        return true
    }

    func moveKpis(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = kpis
        next.move(fromOffsets: source, toOffset: destination)
        withMotion(Motion.smooth) { kpis = next }
    }

    // MARK: Goals

    /// Saves a new or edited goal. A goal that is already met when it is saved is recorded as seen, so it never pops for this period
    /// (the pop is for reaching it, not for creating it). Saving also shows the Ziele card if it was hidden.
    @discardableResult
    func save(_ goal: Goal, progress: GoalProgress?) -> Bool {
        var next = goals
        guard next.upsert(goal) else { return false }
        if let progress, progress.state == .reached {
            ledger.markSeen(progress)
            write(ledger.encoded(), GoalLedger.storageKey)
        }
        goalSaveTick += 1
        withMotion(Motion.smooth) {
            goals = next
            if layout.isHidden(.goals) {
                var shown = layout
                shown.setHidden(.goals, false)
                layout = shown
            }
        }
        return true
    }

    func removeGoal(id: UUID) {
        var next = goals
        next.remove(id: id)
        goalDeleteTick += 1
        withMotion(Motion.smooth) { goals = next }
    }

    /// True exactly once per goal and period when it is reached (one pop, one haptic). Never in screenshot or perf runs.
    func shouldCelebrate(_ progress: GoalProgress) -> Bool {
        guard !LaunchMode.isSandboxed, ledger.celebrate(progress) else { return false }
        write(ledger.encoded(), GoalLedger.storageKey)
        return true
    }

    // MARK: Editor

    func openEditor(at focus: DashEditorFocus? = nil) {
        editorFocus = focus
        isEditing = true
    }

    // MARK: Demo

    /// CI scenes: a layout, figures and goals in memory only (sandboxed runs store nothing).
    func installDemo(layout: DashLayout, kpis: [KpiKind], goals: [Goal]) {
        guard LaunchMode.isSandboxed else { return }
        self.layout = layout
        self.kpis = KpiSelection(kpis)
        self.goals = GoalList(goals)
    }

    /// „Alle Daten löschen“: the goals and their ledger go with the trips; the layout and the picked figures are display settings
    /// (like Look & Feel) and stay.
    func deleteGoals() {
        goals = .empty
        ledger = GoalLedger()
        defaults?.removeObject(forKey: GoalLedger.storageKey)
    }
}

/// Where the editor opens.
enum DashEditorFocus: String, Hashable {
    case sections, kpis, goals
}
