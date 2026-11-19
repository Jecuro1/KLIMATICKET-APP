import SwiftUI
import MapKit
import KlimaCore

// MARK: radar2-radartrail – „Spuren“ on the radar view (docs/RADAR_TRAILS.md). Through the radar2 seam only: `trailMapContent` (drawn before the
// vehicle markers, so under them) and `trailStatusNote` (the line under the status card). A trail is drawn behind single markers the policy names
// (`RadarTrailPolicy`), only with the train layer on and the live data open (offline draws no markers, so no trail) and only at „Jetzt“ (away from now
// the Zeitreise draws its own computed trail). It ends exactly at the drawn marker: the samples newer than the marker's moment are left out.

/// What the trail layer draws now.
struct RadarTrailDrawing {
    struct Trail {
        var tripID: String
        var mode: TransportMode
        var isSelected: Bool
        var lines: [RadarTrailLine]
    }

    var choice = RadarTrailPolicy.Choice()
    var trails: [Trail] = []

    static let empty = RadarTrailDrawing()
}

/// One polyline overlay of a trail: its light casing, the pale older half (or an older piece before a gap) or the strong newer half.
struct RadarTrailStroke: Identifiable {
    var id: String
    var coordinates: [CLLocationCoordinate2D]
    var color: Color
    var width: CGFloat
}

extension RadarView {
    /// The trails of the vehicles the policy names, each ending at its marker.
    var trailDrawing: RadarTrailDrawing {
        let trail = model.radar2.trail
        let mode = trail.setting.mode
        guard RadarTrailPolicy.isDrawn(trainsOn: trainsOn, timeAway: travel.isAway, mode: mode) else { return .empty }
        let singles = model.clusters.compactMap { $0.isSingle ? $0.tripIDs.first : nil }
        let selected = model.selectedTripID
        let remembered = singles.filter { id in model.pinsByID[id].map { model.radar2.mine.remembers($0.vehicle) } ?? false }
        let choice = RadarTrailPolicy.trips(mode: mode, selected: selected, followed: LiveFollowTracker.shared.target?.tripID,
                                            remembered: remembered, singles: singles, span: model.spanDegrees)
        var drawing = RadarTrailDrawing(choice: choice)
        for id in choice.tripIDs {
            guard let pin = model.pinsByID[id], let entry = model.store.entries[id] else { continue }
            // The marker's moment: between the last two answers while it glides (only answers before the newest count), at the newest answer
            // once it holds there (`RadarEstimate.shown`).
            let until = pin.isEstimate ? entry.seenAt.addingTimeInterval(-0.001) : entry.seenAt
            let lines = trail.lines(for: id, until: until, drawnPoint: pin.coordinate, spanDegrees: model.spanDegrees,
                                    heightPoints: Double(model.mapSize.height)).filter(\.isVisible)
            guard !lines.isEmpty else { continue }
            drawing.trails.append(.init(tripID: id, mode: pin.vehicle.line?.mode ?? .train, isSelected: id == selected, lines: lines))
        }
        trail.keepCache(for: Set(choice.tripIDs))
        return drawing
    }

    /// Casings first, then the pale halves, then the strong ones: a crossing trail never covers another's colour with its casing.
    func trailStrokes(_ drawing: RadarTrailDrawing) -> [RadarTrailStroke] {
        let dark = mapStyle == .dark || colorScheme == .dark
        var casings: [RadarTrailStroke] = [], pale: [RadarTrailStroke] = [], strong: [RadarTrailStroke] = []
        for trail in drawing.trails {
            let width: CGFloat = trail.isSelected ? 5 : 4
            let colour = Theme.modeColor(trail.mode)
            for (index, line) in trail.lines.enumerated() {
                let key = "\(trail.tripID)|\(index)"
                casings.append(RadarTrailStroke(id: key + "|casing", coordinates: line.coordinates.map(\.clCoordinate),
                                                color: .white.opacity(dark ? 0.30 : 0.85), width: width + 5))
                guard line.isNewest else {
                    pale.append(RadarTrailStroke(id: key + "|older", coordinates: line.coordinates.map(\.clCoordinate),
                                                 color: colour.opacity(0.45), width: width))
                    continue
                }
                let halves = line.halves
                if halves.older.count > 1 {
                    pale.append(RadarTrailStroke(id: key + "|older", coordinates: halves.older.map(\.coordinate.clCoordinate),
                                                 color: colour.opacity(0.45), width: width))
                }
                let newer = halves.newer.count > 1 ? halves.newer : line.points
                strong.append(RadarTrailStroke(id: key + "|newer", coordinates: newer.map(\.coordinate.clCoordinate), color: colour, width: width))
            }
        }
        return casings + pale + strong
    }

    /// The trails, under the markers (overlays always are) and above the Pünktlichkeit's hexagons (same level, declared after them).
    @MapContentBuilder var trailMapContent: some MapContent {
        ForEach(trailStrokes(trailDrawing)) { stroke in
            MapPolyline(coordinates: stroke.coordinates)
                .stroke(stroke.color, style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                .mapOverlayLevel(level: .aboveRoads)
        }
    }

    /// The line under the status card: what a trail is and since when, the „zu viele“ note, or that trails exist only at „Jetzt“.
    var trailNote: RadarTrailPolicy.Note {
        let trail = model.radar2.trail
        let mode = trail.setting.mode
        guard mode != .off else { return .none }
        let drawing = trailDrawing
        let held = mode == .all ? trail.holdsAnything
            : trail.holds(model.selectedTripID) || trail.holds(LiveFollowTracker.shared.target?.tripID)
        return RadarTrailPolicy.note(mode: mode, trainsOn: trainsOn, timeAway: travel.isAway, choice: drawing.choice,
                                     drawn: drawing.trails.count, heldForReturn: held, firstRecordedAt: trail.firstRecordedAt, now: Date(),
                                     length: trail.setting.length)
    }

    @ViewBuilder var trailStatusNote: some View {
        let note = trailNote
        let scene = LaunchMode.isSandboxed ? RadarTrailDemo.scene : nil
        if note != .none || scene != nil {
            RadarTrailNoteView(note: note)
                .motionTransition(.drop)
                .task {
                    if let scene { await applyTrailScene(scene) }   // CI scenes only
                }
        }
    }

    /// The CI scenes (`RadarTrailScreenshotHost`): the Westbahn between Amstetten and Wien with RJX 66 selected (the host follows REX 92); the city
    /// scene comes from radarmodes' Wien preset as it is.
    func applyTrailScene(_ scene: RadarTrailScene) async {
        try? await Task.sleep(for: .milliseconds(250))   // after the preset `onAppear` applies
        switch scene {
        case .westbahn, .tooMany:
            layersRaw = MapLayerSelection(layers: [.trains]).storageValue   // only the trains: the scene is about their trails
            camera = .region(MKCoordinateRegion(center: RadarTrailDemo.westbahnCentre.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 1.6)))
            model.selectedTripID = RadarTrailDemo.selectedTrip
        case .city, .sheet, .ax5, .sheetAX5, .settings:
            break
        }
    }
}

/// The caption on a glass capsule like the radar's other hints; VoiceOver reads it as one sentence.
struct RadarTrailNoteView: View {
    let note: RadarTrailPolicy.Note

    var body: some View {
        switch note {
        case .none:
            Color.clear.frame(width: 0, height: 0)   // CI scenes: the scene's task needs a view before the first trail
        case .caption(let since):
            caption(since)
                .radarHint()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RadarTrailText.spokenCaption(since: since))
        case .tooMany(let since):
            VStack(spacing: 2) {
                Text(RadarTrailText.tooMany(hasMine: since != nil))
                if let since { caption(since) }
            }
            .radarHint()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RadarTrailText.tooMany(hasMine: since != nil) + (since.map { " " + RadarTrailText.spokenCaption(since: $0) } ?? ""))
        case .onlyNow:
            Text(RadarTrailText.onlyNow).radarHint()
        }
    }

    private func caption(_ since: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            Text(RadarTrailText.caption(since: since))
        }
    }
}
