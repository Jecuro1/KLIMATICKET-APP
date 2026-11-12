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

    @ObservationIgnored private var target: [HeatDrawCell] = []
    @ObservationIgnored private var fade: Task<Void, Never>?
    @ObservationIgnored private var lastCompute = Date.distantPast
    @ObservationIgnored private var answerPending = false

    /// A new answer from the server arrived: the next update recomputes at once instead of waiting.
    func noteAnswer() { answerPending = true }

    /// Positions and next stops move a little between two answers; the numbers are recomputed at most this often otherwise.
    static let refreshInterval: TimeInterval = 10
    /// The cross-fade: this many steps, this far apart (about a third of a second). MapKit overlays are not animatable from SwiftUI, so
    /// the colours move in steps; under Reduce Motion and in screenshots the new state is shown at once.
    static let fadeSteps = 4
    static let fadeStep: Duration = .milliseconds(90)

    func needsUpdate(at now: Date) -> Bool {
        isEnabled && (answerPending || now.timeIntervalSince(lastCompute) >= Self.refreshInterval || now < lastCompute)
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if !on {
            fade?.cancel()
            fade = nil
            snapshot = .empty
            shown = []
            target = []
            history.reset()
            selectedCell = nil
            trainSheet = nil
            answerPending = false
            lastCompute = .distantPast
        }
    }

    /// Takes the trains of one moment: new numbers for the panel, new cells for the map.
    func update(_ samples: [HeatSample], at now: Date) {
        guard isEnabled else { return }
        lastCompute = now
        answerPending = false
        let next = RadarHeat.snapshot(samples)
        if next != snapshot { snapshot = next }
        history.record(next.summary, at: now)
        let cells = HeatLayer.drawCells(from: next)
        if cells != target { crossfade(to: cells) }
        if opensFirstHotspot, selectedCell == nil, let first = next.hotspots.first {
            opensFirstHotspot = false
            selectedCell = first.cellID
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
