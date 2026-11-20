import SwiftUI
import UIKit
import KlimaCore

// MARK: radar2-radarmine – „In der Nähe“ (docs/RADAR_MINE.md §3): only after a tap on „In meiner Nähe zeigen“ the app asks for one location fix
// (when-in-use, `LocationService`; the system prompt appears only if it was never answered), moves the map to 3 km around it and lists the vehicles
// the radar holds within 1.5 km, nearest first, with the minutes to their next stop. The fix stays in memory while the panel is open; it is never
// stored, logged or sent. The radar then asks the tiles of that view as if you had moved the map there – the copy says so.

struct RadarMineNearPage: View {
    var mine: RadarMineModel
    var context: RadarMineContext

    @State private var rows: [RadarNearbyRow] = []
    /// MARK: radar2-review-radarmine – what the rows cover (`RadarNearby.coverage`): only the whole, loaded circle may be called empty.
    @State private var coverage: RadarNearby.Coverage = .loading
    /// MARK: radar2-review-radarmine – the list's loop rests while the app is not active.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            switch mine.nearState {
            case .before:
                RadarMineNote(symbol: "location", text: RadarMineText.nearIntro, tint: Theme.accentText)
                locateButton(RadarMineText.nearButton, symbol: "location.fill", prominent: true)
            case .locating:
                progress(RadarMineText.locating)
            case .denied:
                RadarMineNote(symbol: "location.slash", text: RadarMineText.denied, actionTitle: RadarMineText.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .noFix:
                RadarMineNote(symbol: "location.slash", text: RadarMineText.noFix)
                locateButton(RadarMineText.retry, symbol: "arrow.clockwise", prominent: false)
            case .ready:
                ready
            }
            RadarMineFooter(lines: [RadarMineText.nearFooter])
        }
        .task(id: RadarMineLoopID(value: mine.fix, active: scenePhase == .active)) {
            while !Task.isCancelled, scenePhase == .active, let fix = mine.fix {
                let radar = context.radar
                let sightings = radar.pins.map { RadarMineSighting(vehicle: $0.vehicle, coordinate: $0.coordinate, isEstimate: $0.isEstimate) }
                let next = RadarNearby.rows(sightings, from: fix, now: Date())
                if next.map(\.id) != rows.map(\.id) {
                    withMotion(Motion.smooth) { rows = next }
                } else {
                    rows = next
                }
                // MARK: radar2-review-radarmine – the gate is read from the model (the context is a copy of the moment the page was built)
                let gate = mine.gate
                let paused: Bool = { if case .failed = radar.load { return true } else { return false } }()
                let loads = gate.liveLoopRuns && gate.trainsOn && !radar.lowPower && !paused
                let current = RadarNearby.coverage(fix: fix, box: radar.box, loads: loads, pending: radar.status.anyPending,
                                                   cityModesOn: radar.modes.hasCity, cityOutOfZoom: radar.cityOutOfZoom)
                if current != coverage { withMotion(Motion.smooth) { coverage = current } }
                try? await Task.sleep(for: .seconds(coverage == .complete ? 5 : 1))   // a note goes as soon as the map is back on the circle
            }
        }
    }

    @ViewBuilder private var ready: some View {
        if !cityModesOn {
            RadarMineNote(symbol: "bus", text: RadarMineText.cityOff, actionTitle: RadarMineText.switchOn) {
                context.switchOn([.bus, .tram, .subway])
            }
        }
        coverageNote
        if rows.isEmpty {
            if coverage == .loading {
                progress(RadarMineText.loadingNear)
            } else if coverage == .complete {
                RadarMineNote(symbol: "dot.radiowaves.left.and.right",
                              text: context.radar.filter.isActive ? RadarMineText.nearEmptyFiltered : RadarMineText.nearEmpty)
            }
        } else {
            ForEach(rows) { row in
                RadarMineNearRow(row: row) {
                    if let pin = context.radar.pinsByID[row.tripID] { context.select(pin) }
                }
                if row.id != rows.last?.id { Divider().overlay(Theme.separator) }
            }
        }
        locateButton(RadarMineText.relocate, symbol: "location", prominent: false)
    }

    private var cityModesOn: Bool { context.radar.modes.hasCity }

    /// MARK: radar2-review-radarmine – why the list may miss vehicles of the circle: the map left it, the city lane is out of zoom, the radar does not
    /// load. Each with the way back to the circle where that helps.
    @ViewBuilder private var coverageNote: some View {
        switch coverage {
        case .offMap:
            RadarMineNote(symbol: "scope", text: RadarMineText.nearOffMap, actionTitle: RadarMineText.toCircle) { backToCircle() }
        case .cityOutOfZoom:
            RadarMineNote(symbol: "plus.magnifyingglass", text: RadarModesText.zoomHint(context.radar.modes.ordered.filter(\.isCity)),
                          actionTitle: RadarMineText.toCircle) { backToCircle() }
        case .notLoading:
            RadarMineNote(symbol: "pause.circle", text: RadarMineText.nearNotLoading)
        case .complete, .loading:
            EmptyView()
        }
    }

    private func backToCircle() {
        guard let fix = mine.fix else { return }
        context.focus(fix, RadarNearby.viewSpanKm / RadarLanePlan.kmPerDegreeLatitude)
    }

    private func locateButton(_ title: String, symbol: String, prominent: Bool) -> some View {
        Button {
            Task {
                guard let fix = await mine.locate() else { return }
                context.focus(fix, RadarNearby.viewSpanKm / RadarLanePlan.kmPerDegreeLatitude)
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: prominent ? .infinity : nil, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? Theme.accent : Theme.surfaceSecondary)
        .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(minHeight: 44)
    }
}

/// „Bus 13A → Hauptbahnhof“ / „240 m · nächster Halt Neubaugasse in 2 Min (+1)“.
private struct RadarMineNearRow: View {
    var row: RadarNearbyRow
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                if let line = row.line { PlannerLinePlate(line: line, size: .m) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(RadarMineText.vehicleTitle(row.title, direction: row.direction))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(RadarMineText.nearDetail(row, now: Date()))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(row.eta.isCancelled ? Theme.negativeText : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RadarMineText.nearSpoken(row, now: Date()))
        .accessibilityHint(RadarMineText.showOnMap)
        .accessibilityAddTraits(.isButton)
    }
}
