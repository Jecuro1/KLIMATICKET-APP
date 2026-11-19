import SwiftUI
import KlimaCore

// MARK: radar2-radarmine – „Wo bleibt mein Bus?“ (docs/RADAR_MINE.md §4): the next departures from one stop, every 60 s as a side job of the radar's
// one loop and budget, each with its ETA, delay, Steig or Gleis and where its vehicle is now (the radar's newer marker of the same trip, else the
// board's position, else „Position unbekannt“). The first five with a position get a number here and on the map. Honest about every pause.

struct RadarMineStopPage: View {
    var mine: RadarMineModel
    var context: RadarMineContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let stop = mine.stop {
                header(stop)
                // The idle pause after 30 minutes appears without a tap (the clock is not observed).
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) { states }
                }
                rows
                RadarMineFooter(lines: [RadarMineText.stopFooter, RadarMineText.maybeTwice])
                Button {
                    context.allDepartures(stop)
                } label: {
                    Label(RadarMineText.allDepartures, systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            } else {
                RadarMineStopPicker(mine: mine, context: context)
            }
        }
    }

    // MARK: Header

    private func header(_ stop: RadarMineStop) -> some View {
        RadarMineAdaptiveRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(RadarMineText.from(stop.name))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = mine.boardFetchedAt {
                    TimelineView(.periodic(from: .now, by: 5)) { timeline in
                        Text("\(RadarMineText.stand(at)) · \(RadarStatusText.age(timeline.date.timeIntervalSince(at)))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } trailing: {
            Button {
                withMotion(Motion.smooth) { mine.clearStop() }
            } label: {
                Label(RadarMineText.otherStop, systemImage: "arrow.triangle.swap")
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentText)
        }
    }

    // MARK: States

    @ViewBuilder private var states: some View {
        if mine.unknownStop {
            RadarMineNote(symbol: "questionmark.circle", text: RadarMineText.unknownStop)
        } else if let text = RadarMineText.pause(mine.pause, idle: mine.isIdle) {
            pauseNote(text)
        } else if let error = mine.boardError {
            RadarMineNote(symbol: "wifi.exclamationmark", text: error)
        } else if mine.isLoadingBoard {
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                Text(RadarMineText.loadingBoard).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
        }
        let hidden = RadarStopArrivals.hiddenModes(mine.arrivals, shownModes: context.shownModes)
        if !hidden.isEmpty {
            let modes = RadarMode.allCases.filter(hidden.contains)
            RadarMineNote(symbol: "eye.slash", text: RadarMineText.modesOffMap(modes),
                          actionTitle: modes.contains(where: { !context.radar.modes.contains($0) }) ? RadarMineText.switchOn : nil) {
                context.switchOn(Set(modes))
            }
        }
    }

    @ViewBuilder private func pauseNote(_ text: String) -> some View {
        switch mine.pause {
        case .lowPower?:
            RadarMineNote(symbol: "battery.25percent", text: text, actionTitle: RadarMineText.refreshNow) {
                mine.refreshNow()
                context.radar.refreshNow()
            }
        case .trainsOff?:
            RadarMineNote(symbol: "train.side.front.car", text: text, actionTitle: RadarMineText.switchOn) { context.trainsOn() }
        case .accessClosed?:
            RadarMineNote(symbol: "antenna.radiowaves.left.and.right.slash", text: text, actionTitle: RadarMineText.settings) { context.openSettings() }
        case .offline?:
            RadarMineNote(symbol: "wifi.slash", text: text)
        case .timeAway?, .cockpit?:
            RadarMineNote(symbol: "pause.circle", text: text)
        default:   // idle
            RadarMineNote(symbol: "pause.circle", text: text, actionTitle: RadarMineText.refreshNow) { mine.interact() }
        }
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        let offline = mine.pause == .offline || mine.pause == .accessClosed
        if !offline, mine.board != nil {
            if mine.arrivals.isEmpty {
                RadarMineNote(symbol: "clock", text: RadarMineText.stopEmpty)
            } else {
                ForEach(mine.arrivals) { arrival in
                    RadarMineArrivalRow(arrival: arrival, number: mine.numbers[arrival.id]) {
                        if let point = arrival.point, let stop = mine.stop {
                            if arrival.source == .radar, let pin = context.radar.pinsByID[arrival.tripID] { context.radar.selectedTripID = pin.id }
                            context.focusPair(point, stop.coordinate)
                        }
                    }
                    if arrival.id != mine.arrivals.last?.id { Divider().overlay(Theme.separator) }
                }
            }
        }
    }
}

/// One departure: number, plate, „→ Hauptbahnhof“, „in 4 Min“ with the delay, „ab 14:36 · Steig 2“, and where the vehicle is. At accessibility sizes
/// number and plate sit on their own line and everything below takes the full width (nothing is pushed past the screen's edge).
private struct RadarMineArrivalRow: View {
    var arrival: RadarStopArrival
    var number: Int?
    var onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onSelect) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Spacing.xs) {
                            badge
                            PlannerLinePlate(row: arrival.row, size: .m)
                        }
                        texts
                    }
                } else {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        badge.frame(width: 22)
                        PlannerLinePlate(row: arrival.row, size: .m)
                        texts
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RadarMineText.arrivalSpoken(arrival, number: number, now: Date()))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var badge: some View {
        if let number {
            RadarMineNumberBadge(number: number, mode: arrival.row.mode, fromBoard: arrival.source == .board)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            RadarMineAdaptiveRow {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(arrival.isCancelled)
                    .fixedSize(horizontal: false, vertical: true)
            } trailing: {
                eta
            }
            Text(RadarMineText.departure(arrival))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !arrival.isCancelled { position }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The plate names the line; the row names where it goes (a plate „13A“ next to „13A → …“ said it twice, CI screenshots run 1).
    private var title: String {
        let destination = arrival.row.destination.name
        return destination.isEmpty ? arrival.row.lineTitle : "→ \(destination)"
    }

    private var eta: some View {
        HStack(spacing: 6) {
            if !arrival.isCancelled, let eta = arrival.eta {
                Text(RadarMineText.minutesText(eta.minutes(from: Date())))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .motionAnimation(Motion.number, value: eta.minutes(from: Date()))
            }
            Text(RadarMineText.delayChip(arrival.eta))
                .font(.caption.weight(.bold))
                .foregroundStyle(delayColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(delayColor.opacity(0.14), in: .capsule)
        }
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }

    private var delayColor: Color {
        guard let eta = arrival.eta else { return Theme.textSecondary }
        if eta.isCancelled { return Theme.negativeText }
        guard eta.isRealtime, let minutes = eta.delayMinutes else { return Theme.textSecondary }
        return minutes > 0 ? Theme.summitText : Theme.positiveText
    }

    @ViewBuilder private var position: some View {
        let stale = RadarStopArrivals.isStale(arrival.positionAt, now: Date())
        Label {
            Text(stale ? "\(RadarMineText.position(arrival.position)) · \(RadarMineText.positionAge(Date().timeIntervalSince(arrival.positionAt ?? Date())))"
                       : RadarMineText.position(arrival.position))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: positionSymbol).font(.caption2.weight(.bold))
        }
        .font(.caption)
        .foregroundStyle(stale || arrival.position == .unknown ? Theme.textTertiary : Theme.textSecondary)
    }

    private var positionSymbol: String {
        switch arrival.position {
        case .atStop: "mappin.circle.fill"
        case .away: arrival.source == .radar ? "dot.radiowaves.left.and.right" : "list.bullet.rectangle"
        case .unknown: "questionmark.circle"
        }
    }
}
