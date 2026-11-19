import SwiftUI
import KlimaCore

// MARK: radar2-radarmine – „Linien“ (docs/RADAR_MINE.md §2): the lines you remembered, each with what the radar holds of it right now (read from the
// radar's tiles, no request of its own), „Nur meine Linien hervorheben“ and the way back to where a line was remembered. The list is worked out every
// five seconds, not with every marker move.

struct RadarMineLinesPage: View {
    var mine: RadarMineModel
    var context: RadarMineContext

    /// One remembered line as the page shows it.
    struct Row: Identifiable, Equatable {
        enum State: Equatable {
            /// Vehicles in the loaded areas: how many, and the one nearest the map's centre.
            case running(count: Int, next: String?, nearest: RadarPin?)
            /// The line's chip is off: the radar does not ask for it.
            case modeOff
            /// Bus, Bim or U-Bahn while the map is too far out for them.
            case outOfZoom
            case none
        }

        var key: RadarLineKey
        var line: Line
        var state: State
        var id: String { key.id }
    }

    @State private var rows: [Row] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if mine.lines.isEmpty {
                RadarMineNote(symbol: "star", text: RadarMineText.linesEmpty, tint: Theme.gold)
            } else {
                highlightToggle
                ForEach(rows) { row in
                    RadarMineLineRow(row: row, mine: mine, context: context)
                    if row.id != rows.last?.id { Divider().overlay(Theme.separator) }
                }
            }
            RadarMineFooter(lines: [RadarMineText.linesFooter])
        }
        .task(id: mine.lines) {
            while !Task.isCancelled {
                let next = makeRows()
                if next != rows { withMotion(Motion.smooth) { rows = next } }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var highlightToggle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { mine.file.highlight }, set: { on in withMotion(Motion.smooth) { mine.setHighlight(on) } })) {
                Label(RadarMineText.highlight, systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.gold)
            Text(RadarMineText.highlightFooter)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the radar holds of each line now.
    private func makeRows() -> [Row] {
        let radar = context.radar
        let now = Date()
        let held = radar.knownVehicles
        let centre = radar.box.center
        return mine.lines.keys.map { key in
            let vehicles = mine.vehicles(of: key, in: held)
            let line = vehicles.first?.line ?? key.displayLine
            if !radar.modes.contains(key.mode) { return Row(key: key, line: line, state: .modeOff) }
            if key.mode.isCity && radar.cityOutOfZoom && vehicles.isEmpty { return Row(key: key, line: line, state: .outOfZoom) }
            guard !vehicles.isEmpty else { return Row(key: key, line: line, state: .none) }
            let shown = vehicles.compactMap { radar.pinsByID[$0.tripID] }
            let nearest = shown.min { $0.coordinate.distanceKm(to: centre) < $1.coordinate.distanceKm(to: centre) }
            let vehicle = nearest?.vehicle ?? vehicles[0]
            var next: String?
            if let stop = RadarRun.nextStop(of: vehicle, now: now), let eta = RadarMineETA(stop: stop, vehicleCancelled: vehicle.isCancelled) {
                next = RadarMineText.nextVehicle(direction: vehicle.direction, stop: stop.location.name, eta: eta, now: now)
            }
            return Row(key: key, line: line, state: .running(count: vehicles.count, next: next, nearest: nearest))
        }
    }
}

/// One remembered line: plate, title, what runs now, and what can be done.
private struct RadarMineLineRow: View {
    var row: RadarMineLinesPage.Row
    var mine: RadarMineModel
    var context: RadarMineContext

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            PlannerLinePlate(line: row.line, size: .m)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 14, height: 14)
                        .background(Theme.gold, in: .circle)
                        .overlay(Circle().strokeBorder(Theme.snow, lineWidth: 1))
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.key.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if case .running(_, _, let nearest?) = row.state {
                    Button(RadarMineText.showOnMap, systemImage: "scope") { context.select(nearest) }
                }
                Button(RadarMineText.forget, systemImage: "star.slash", role: .destructive) {
                    withMotion(Motion.smooth) { mine.forget(row.key) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .onTapGesture {
            if case .running(_, _, let nearest?) = row.state { context.select(nearest) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityAction(named: RadarMineText.showOnMap) {
            if case .running(_, _, let nearest?) = row.state { context.select(nearest) }
        }
        .accessibilityAction(named: RadarMineText.forget) { mine.forget(row.key) }
    }

    @ViewBuilder private var detail: some View {
        switch row.state {
        case .running(let count, let next, _):
            Text(RadarMineText.running(count))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positiveText)
                .contentTransition(.numericText())
            if let next {
                Text(next)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .modeOff:
            RadarMineNote(symbol: "eye.slash", text: RadarMineText.modeOff(row.key.mode), actionTitle: RadarMineText.switchOn) {
                context.switchOn([row.key.mode])
            }
        case .outOfZoom:
            RadarMineNote(symbol: "plus.magnifyingglass", text: RadarModesText.zoomHint([row.key.mode]),
                          actionTitle: row.key.area == nil ? nil : RadarMineText.toArea) {
                if let area = row.key.area { context.focus(area, 0.2) }
            }
        case .none:
            RadarMineNote(symbol: "dot.radiowaves.left.and.right", text: RadarMineText.noneLoaded,
                          actionTitle: row.key.area == nil ? nil : RadarMineText.toArea) {
                if let area = row.key.area { context.focus(area, row.key.mode.isCity ? 0.2 : 0.35) }
            }
        }
    }

    private var spoken: String {
        switch row.state {
        case .running(let count, let next, _):
            return RadarMineText.lineSpoken(title: row.key.title, running: count, next: next)
        case .modeOff:
            return "\(row.key.title). \(RadarMineText.modeOff(row.key.mode))"
        case .outOfZoom:
            return "\(row.key.title). \(RadarModesText.zoomHint([row.key.mode]))"
        case .none:
            return RadarMineText.lineSpoken(title: row.key.title, running: 0, next: nil)
        }
    }
}
