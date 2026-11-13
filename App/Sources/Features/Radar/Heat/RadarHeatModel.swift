import SwiftUI
import KlimaCore

// MARK: radarheat – the state of the Pünktlichkeit layer (docs/RADAR_HEATMAP.md). The numbers come from `KlimaCore` (`RadarHeat`);
// this class holds the latest snapshot, the cells the map draws (with the cross-fade between two answers), the panel's open state,
// the selected cell and the trend of this session. It does not load anything: the radar model sends the requests and hands over
// the trains.

@MainActor
@Observable
final class RadarHeatModel {
    /// The layer is on. Everything below is empty while it is off.
    private(set) var isEnabled = false
    private(set) var snapshot = HeatSnapshot.empty
    /// The cells the map draws right now: between two answers they run from the old state to the new one (`HeatLayer.interpolate`).
    private(set) var shown: [HeatDrawCell] = []
    /// National punctuality at the moments of this session, for the sparkline. In memory only.
    private(set) var history = HeatHistory()
    /// The latest numbers rest on every tile of the country, each with a fresh answer (`RadarModel.refreshHeat`). Only then the share
    /// image is offered: an image of half the country would travel without the note that says so.
    private(set) var isComplete = false
    /// The time the latest numbers belong to: the request time of the oldest answer behind them. The share image prints it.
    private(set) var dataTime: Date?
    /// The panel shows the details (legend, largest delays, hot spots) or only the headline.
    var isExpanded = false
    /// The cell whose trains are listed in the sheet.
    var selectedCell: HeatCellID?
    /// A train opened from the cell sheet or from the map while the sheet is up: its trip sheet is shown on top of the cell sheet.
    var trainSheet: RadarVehicle?
    /// Screenshot scene: opens the sheet of the first hot spot as soon as there is one.
    var opensFirstHotspot = false
    /// Screenshot scene: the open panel scrolls to the lists of the largest delays and the hot spots.
    var scrollsToLists = false
    /// Screenshot scene: the open panel scrolls to the trend line.
    var scrollsToTrend = false

    @ObservationIgnored private var target: [HeatDrawCell] = []
    @ObservationIgnored private var fade: Task<Void, Never>?
    @ObservationIgnored private var lastCompute = Date.distantPast
    @ObservationIgnored private var answerPending = false
    @ObservationIgnored private var pendingTap: Task<Void, Never>?

    /// The cells of the latest snapshot as the map settles on them (without the cross-fade): what the share image draws. Computed once
    /// per snapshot in `update`, not again in the panel's body.
    var drawnCells: [HeatDrawCell] { target }

    /// A new answer from the server arrived: the next update recomputes at once instead of waiting.
    func noteAnswer() { answerPending = true }

    /// Positions and next stops move a little between two answers; the numbers are recomputed at most this often otherwise.
    static let refreshInterval: TimeInterval = 10
    /// The cross-fade: this many steps over `Motion.Duration.standard` (0.35 s, the token of a content change). MapKit overlays are not
    /// animatable from SwiftUI, so the colours move in steps; under Reduce Motion and in screenshots the new state is shown at once.
    static let fadeSteps = 4
    static let fadeStep: Duration = .seconds(Motion.Duration.standard / Double(fadeSteps))

    func needsUpdate(at now: Date) -> Bool {
        isEnabled && (answerPending || now.timeIntervalSince(lastCompute) >= Self.refreshInterval || now < lastCompute)
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if !on {
            fade?.cancel()
            fade = nil
            pendingTap?.cancel()
            pendingTap = nil
            snapshot = .empty
            shown = []
            target = []
            history.reset()
            selectedCell = nil
            trainSheet = nil
            answerPending = false
            lastCompute = .distantPast
            isComplete = false
            dataTime = nil
        }
    }

    /// Takes the trains of one moment: new numbers for the panel, new cells for the map. `isComplete` is true when every tile of the
    /// country has answered: only then the moment goes into the trend of this session.
    func update(_ samples: [HeatSample], at now: Date, isComplete: Bool = true, dataTime: Date? = nil) {
        guard isEnabled else { return }
        lastCompute = now
        answerPending = false
        let next = RadarHeat.snapshot(samples)
        if next != snapshot { snapshot = next }
        if self.isComplete != isComplete { self.isComplete = isComplete }
        let time = dataTime ?? now
        if self.dataTime != time { self.dataTime = time }
        if isComplete { history.record(next.summary, at: now) }
        let cells = HeatLayer.drawCells(from: next)
        if cells != target { crossfade(to: cells) }
        if opensFirstHotspot, selectedCell == nil, let first = next.hotspots.first {
            opensFirstHotspot = false
            selectedCell = first.cellID
        }
    }

    /// How long a tap on the map waits for a second tap before it selects: the map zooms in on a double tap, and that should not open
    /// (and close again) a sheet on its way.
    static let doubleTapWindow: Duration = .milliseconds(280)

    /// A tap on the map (`id` is nil for a tap on nothing): selects the cell after `doubleTapWindow`, unless a second tap follows within
    /// it (a double-tap zoom), which cancels the selection and selects nothing, wherever that second tap lands.
    func selectAfterTap(_ id: HeatCellID?) {
        if pendingTap != nil {
            pendingTap?.cancel()
            pendingTap = nil
            return
        }
        pendingTap = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.doubleTapWindow)
            guard let self, !Task.isCancelled else { return }
            self.pendingTap = nil
            // A tap on nothing closes an open sheet; with none open it changes nothing.
            if id != nil || self.selectedCell != nil { self.select(id) }
        }
    }

    /// Screenshot scene `radarHeatTrend` only: a trend of the last six and a half minutes made up for the scene (a real one needs that
    /// long an open radar; nothing like it is stored or shown for real).
    func seedDemoTrend(endingAt end: Date) {
        for index in 0..<13 {
            var summary = HeatSummary()
            let share = 0.74 + 0.065 * Double(index) / 12 + (index % 3 == 1 ? -0.012 : 0.008)
            summary.total = 950
            summary.noRealtime = 30
            summary.onTime = Int(920 * share)
            summary.delayed = (920 - summary.onTime) * 6 / 10
            summary.severe = 920 - summary.onTime - summary.delayed
            history.record(summary, at: end.addingTimeInterval(-30 * Double(13 - index)))
        }
    }

    func select(_ id: HeatCellID?) {
        selectedCell = id
        if id == nil { trainSheet = nil }
    }

    private func crossfade(to cells: [HeatDrawCell]) {
        fade?.cancel()
        let from = shown
        target = cells
        if MotionPolicy.isStatic || MotionPolicy.prefersReducedMotion {
            shown = cells
            return
        }
        fade = Task { @MainActor [weak self] in
            for step in 1...Self.fadeSteps {
                guard let self, !Task.isCancelled else { return }
                self.shown = HeatLayer.interpolate(from: from, to: cells, progress: Double(step) / Double(Self.fadeSteps))
                if step < Self.fadeSteps { try? await Task.sleep(for: Self.fadeStep) }
            }
        }
    }
}
