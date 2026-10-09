import SwiftUI
import KlimaCore

// Via stops ("Über …", Zwischenhalte) in the trip editor – docs/VIA.md §4. The route card shows them between "Von" and the
// route meta: a smaller dot on the route line, "Über" + station, ✕ / swipe / VoiceOver action to remove, at most
// `TripVia.maxCount` (then the add affordance disappears). The swap button turns the whole route incl. the vias.

// MARK: - Model

/// One via in the editor: a station (priced, drawn on the map) or – from a CSV import – just a name.
struct TripEdViaStop: Identifiable, Hashable {
    /// Stable identity for the row animations (survives a swap and a re-pick).
    let id: UUID
    var station: Station?
    var name: String

    init(id: UUID = UUID(), station: Station) {
        self.id = id
        self.station = station
        self.name = station.name
    }

    init(id: UUID = UUID(), via: TripVia, stations: StationIndex) {
        self.id = id
        self.station = via.stationID.flatMap(stations.station(id:)) ?? stations.station(named: via.name)
        self.name = station?.name ?? via.name
    }

    var record: TripVia { TripVia(name: station?.name ?? name, stationID: station?.id) }

    static func stops(for vias: [TripVia], stations: StationIndex) -> [TripEdViaStop] {
        TripViaCodec.sanitized(vias).map { TripEdViaStop(via: $0, stations: stations) }
    }
}

extension TripEditorModel {
    /// Stations of the vias that can be priced, in travel order.
    var viaStations: [Station] { vias.compactMap(\.station) }

    /// What is saved: the vias in travel order, without one that is the start or the destination itself.
    var viaRecords: [TripVia] {
        let endpoints = [fromStation?.id, toStation?.id].compactMap { $0 }
        let names = [resolvedFromName, resolvedToName].filter { !$0.isEmpty }
        return TripViaCodec.sanitized(vias.map(\.record).filter { via in
            if let id = via.stationID, endpoints.contains(id) { return false }
            return !names.contains(via.name)
        })
    }

    var canAddVia: Bool { vias.count < TripVia.maxCount }

    /// Applies a station picked for a via slot. False when `pick` is not a via (the caller sets start / destination).
    func tripEdSetVia(_ station: Station, for pick: TripEdPick) -> Bool {
        switch pick {
        case .from, .to:
            return false
        case .via1, .via2:
            let index = pick == .via1 ? 0 : 1
            if vias.indices.contains(index) {
                vias[index].station = station
                vias[index].name = station.name
            } else if canAddVia {
                vias.append(TripEdViaStop(station: station))
            }
        case .viaNew:
            guard canAddVia else { return true }
            vias.append(TripEdViaStop(station: station))
        }
        viaDidChange()
        return true
    }

    func removeVia(_ id: UUID) {
        guard vias.contains(where: { $0.id == id }) else { return }
        vias.removeAll { $0.id == id }
        viaDidChange()
    }

    /// Whether `favorite` has the same vias as the form (a favourite with other vias is another route).
    func tripEdViaMatches(_ favorite: FavoriteRouteEntity) -> Bool {
        TripVia.sameStops(viaRecords, favorite.via)
    }
}

extension TripEdPick {
    /// Vias are stations only: a free-text place could be neither priced nor drawn.
    var tripEdAllowsCustomName: Bool { self == .from || self == .to }
}

// MARK: - Rows

/// The via rows + "Zwischenhalt hinzufügen", placed inside the route card's stop column (text column = x 0; the route line
/// runs `lineOffset` to the left of it, in the card's leading padding).
struct TripEdViaRows: View {
    let model: TripEditorModel
    var onPick: (TripEdPick) -> Void
    /// Centre of the route line relative to the text column (TripEdRouteCard: glyph at x 1…16, text at x 26).
    var lineOffset: CGFloat = -17.5
    /// Leading padding of the route card's stop column (where the route line runs).
    var leadingInset: CGFloat = 26

    /// Width of a column centred on the route line, starting at the card's inset edge.
    private var markColumn: CGFloat { 2 * (leadingInset + lineOffset) }

    @State private var removedTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.vias.enumerated()), id: \.element.id) { index, stop in
                TripEdViaRow(stop: stop, index: index, count: model.vias.count, lineOffset: lineOffset,
                             onTap: { onPick(index == 0 ? .via1 : .via2) },
                             onRemove: { remove(stop) })
                    .motionTransition(.rise)
            }
            if showsAddButton {
                addButton
                    .motionTransition(.rise)
            }
        }
        .motionAnimation(Motion.smooth, value: model.vias.map(\.id))
        .haptic(.decrease, trigger: removedTick)
    }

    /// Only once the route has a start or a destination – an empty form stays calm.
    private var showsAddButton: Bool {
        model.canAddVia && (!model.resolvedFromName.isEmpty || !model.resolvedToName.isEmpty)
    }

    private func remove(_ stop: TripEdViaStop) {
        withMotion(Motion.smooth) { model.removeVia(stop.id) }
        removedTick += 1
    }

    /// "⊕ Zwischenhalt hinzufügen": the ⊕ sits on the route line (a stop waiting to be placed), the label in the text
    /// column. The button reaches into the card's leading padding so the ⊕ is part of the tap target.
    private var addButton: some View {
        Button {
            onPick(.viaNew)
        } label: {
            HStack(spacing: 0) {
                // Column of the route line: centred on it, the rest of the card's leading inset as the gap.
                TripEdViaAddMark()
                    .frame(width: markColumn)
                Spacer().frame(width: leadingInset - markColumn)
                Text(model.vias.isEmpty ? "Zwischenhalt hinzufügen" : "Weiteren Zwischenhalt hinzufügen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .padding(.leading, -leadingInset)
        .padding(.top, 2)
        .accessibilityLabel(model.vias.isEmpty ? "Zwischenhalt hinzufügen" : "Weiteren Zwischenhalt hinzufügen")
        .accessibilityHint("Öffnet die Suche für einen Bahnhof, über den du fährst. Höchstens \(TripVia.maxCount) Zwischenhalte.")
    }
}

/// "• Über / Feldkirch / Bahnhof · Vorarlberg ✕" – a via on the route line.
private struct TripEdViaRow: View {
    let stop: TripEdViaStop
    let index: Int
    let count: Int
    let lineOffset: CGFloat
    var onTap: () -> Void
    var onRemove: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledDot: CGFloat = 9
    /// Grows a little with the text but stays below the start / destination dots (fixed 11 pt) – at AX5 an unbounded
    /// dot would outgrow them and spill out of the route column.
    private var dotSize: CGFloat { min(scaledDot, 10) }
    @State private var dragX: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Über")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(TripEdFormat.displayName(stop.name))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .overlay(alignment: .leading) { dot }
                    if let station = stop.station {
                        Text(TripEdFormat.stationSubtitle(station))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(TripEdPressStyle())
            .accessibilityLabel(spokenLabel)
            .accessibilityHint("Öffnet die Suche für diesen Zwischenhalt")
            .accessibilityAction(named: "Entfernen", onRemove)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.pressable(scale: 0.85))
            .accessibilityLabel("Zwischenhalt \(stop.name) entfernen")
        }
        .padding(.top, 6)
        .offset(x: dragX)
        .opacity(1 - min(abs(dragX) / 160, 0.6))
        .simultaneousGesture(swipeToRemove)
        .contextMenu {
            Button("Ändern", systemImage: "magnifyingglass", action: onTap)
            Button("Entfernen", systemImage: "xmark", role: .destructive, action: onRemove)
        }
    }

    /// Smaller than the start / destination dots, on the route line, in the start's colour.
    private var dot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: dotSize, height: dotSize)
            .padding(2.5)
            .background(TripEdViaAddMark.cardColor, in: .circle)   // cuts the dashed line around the dot
            .offset(x: lineOffset - dotSize / 2 - 2.5)
            .accessibilityHidden(true)
    }

    /// "Über Feldkirch, Zwischenhalt 1 von 2"
    private var spokenLabel: String {
        var text = "Über \(stop.name), Zwischenhalt"
        if count > 1 { text += " \(index + 1) von \(count)" }
        if let station = stop.station { text += ", " + TripEdFormat.stationSubtitle(station) }
        return text
    }

    /// Leftward swipe (≥ 80 pt) removes the via; anything shorter springs back.
    private var swipeToRemove: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                dragX = min(0, value.translation.width)
            }
            .onEnded { value in
                if value.translation.width < -80 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                    onRemove()
                    dragX = 0
                } else {
                    withMotion(Motion.snappy) { dragX = 0 }
                }
            }
    }
}

/// The ⊕ of "Zwischenhalt hinzufügen", sitting on the route line: a small ring in the card colour (it cuts the dashed
/// line), accent plus.
private struct TripEdViaAddMark: View {
    /// Opaque stand-in for the card surface over the sheet (Theme.surface is translucent) – only for tiny knock-outs.
    static let cardColor = Color(light: "#FCFDFE", dark: "#1D273C")

    @ScaledMetric(relativeTo: .footnote) private var scaledSize: CGFloat = 17
    /// Capped: the mark lives in the 17 pt route column – larger text sizes must not push it over the label.
    private var size: CGFloat { min(scaledSize, 21) }

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .frame(width: size, height: size)
            .background(Self.cardColor, in: .circle)
            .overlay(Circle().strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.25))
            .accessibilityHidden(true)
    }
}
