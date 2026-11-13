import SwiftUI
import MapKit
import KlimaCore

// MARK: radarcockpit – the map of the Cockpit-Ansicht (docs/RADAR_COCKPIT.md §4): the base map in 3D, the route tinted by delay, the stops as flags,
// and the followed train as a glowing plate. Nothing else moves: the other trains are not drawn. A view of its own: the camera and the marker change
// about 20 times a second, and only this view is re-evaluated for it, not the HUD.

struct CockpitMap: View {
    var model: CockpitModel
    var style: RadarMapStyle
    /// The map's own palette: "Dunkel" forces the dark one.
    var scheme: ColorScheme

    @State private var position: MapCameraPosition
    /// The map's own heading while the camera is the user's: a two-finger turn in "Frei" turns the map, not the planner's camera, and the
    /// chevron on the train has to point against what is on screen. nil while the planner drives the camera.
    @State private var userHeading: Double?

    init(model: CockpitModel, style: RadarMapStyle, scheme: ColorScheme, start: CockpitCamera?) {
        self.model = model
        self.style = style
        self.scheme = scheme
        let initial = start ?? model.camera
        _position = State(initialValue: initial.map { .camera($0.mapCamera) } ?? .automatic)
    }

    var body: some View {
        let lines = model.lines
        Map(position: $position, interactionModes: .all) {
            routeLayer(lines)
            stopLayer(lines)
            trainLayer
        }
        .mapStyle(style.cockpitStyle)
        .environment(\.colorScheme, scheme)
        .mapControlVisibility(.hidden)   // the top bar sits where the compass would; the train's chevron says which way it points
        // The planner's camera, applied without animation: the steps are small (a few metres, a degree), the map renders each one.
        .onChange(of: model.camera) { _, camera in
            guard let camera, model.session.mode != .free else { return }
            position = .camera(camera.mapCamera)
        }
        // The map flies the opening flight and "Zurück zum Zug" itself.
        .onChange(of: model.flight) { _, flight in
            guard let flight else { return }
            if flight.duration > 0 {
                withAnimation(.smooth(duration: flight.duration)) { position = .camera(flight.target.mapCamera) }
            } else {
                position = .camera(flight.target.mapCamera)
            }
        }
        // A finger on the map (pan, pinch, rotate, tilt) makes the camera the user's.
        .onChange(of: position.positionedByUser) { _, byUser in
            if byUser { model.userMovedMap() }
        }
        // Only in "Frei" and only on a turn of more than two degrees: the driven camera does not write state here 20 times a second.
        .onMapCameraChange(frequency: .continuous) { context in
            guard model.hud.mode == .free else { return }
            let heading = context.camera.heading
            if userHeading.map({ abs(CockpitAngle.delta(from: $0, to: heading)) > 2 }) ?? true { userHeading = heading }
        }
        .onChange(of: model.hud.mode) { _, mode in
            if mode != .free { userHeading = nil }
        }
        .accessibilityHidden(true)
    }

    // MARK: Route

    /// What lies behind the train is a thin grey line; what lies ahead is tinted by the delay at the end of each leg (green on time, orange
    /// five minutes or more late, red cancelled, grey unknown), on a light casing so it reads on every map.
    @MapContentBuilder private func routeLayer(_ lines: CockpitMapLines) -> some MapContent {
        if lines.passed.count > 1 {
            MapPolyline(coordinates: lines.passed)
                .stroke(Theme.textTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        ForEach(lines.ahead) { leg in
            MapPolyline(coordinates: leg.coordinates)
                .stroke(.white.opacity(scheme == .dark ? 0.28 : 0.85), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
        }
        ForEach(lines.ahead) { leg in
            MapPolyline(coordinates: leg.coordinates)
                .stroke(leg.state.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder private func stopLayer(_ lines: CockpitMapLines) -> some MapContent {
        ForEach(lines.stops) { stop in
            if let flag = stop.flag {
                Annotation(flag.name, coordinate: stop.coordinate, anchor: .bottom) {
                    CockpitFlagView(flag: flag, isNext: flag.id == lines.stops.first(where: { $0.flag != nil })?.id)
                }
                .annotationTitles(.hidden)
            } else {
                Annotation("", coordinate: stop.coordinate, anchor: .center) {
                    CockpitStopDot(isPassed: stop.isPassed)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    @MapContentBuilder private var trainLayer: some MapContent {
        if let marker = model.marker {
            Annotation(model.line.map { LinePresentation.title($0) } ?? "Zug", coordinate: marker.coordinate.clCoordinate, anchor: .center) {
                CockpitTrainMarker(line: model.line, state: model.hud.summary?.delayState ?? .unknown, heading: marker.heading,
                                   cameraHeading: userHeading ?? model.camera?.heading ?? 0, isHeld: model.hud.summary.map(isHeld) ?? false,
                                   isStale: model.hud.state == .lost)
            }
            .annotationTitles(.hidden)
        }
    }

    private func isHeld(_ summary: CockpitSummary) -> Bool {
        switch summary.phase {
        case .atStop, .beforeDeparture, .arrived: true
        default: false
        }
    }
}

extension RadarMapStyle {
    /// The cockpit's base map: the radar's style, with real elevation so the tilted camera shows the valleys and the mountains.
    var cockpitStyle: MapStyle {
        switch self {
        case .standard, .dark: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .realistic)
        }
    }
}

// MARK: - Markers

/// A stop the train has passed or has still to reach: a small dot, dimmed once passed.
struct CockpitStopDot: View {
    var isPassed: Bool

    var body: some View {
        Circle()
            .fill(isPassed ? Theme.textTertiary : Color.white)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(isPassed ? Theme.textTertiary.opacity(0.6) : Theme.accent, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// A flag for one of the next stops: its name and when the train gets there, tinted by the delay. The next one is bigger.
struct CockpitFlagView: View {
    var flag: CockpitStopFlag
    var isNext: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if isNext { Image(systemName: "flag.fill").font(.caption.weight(.bold)).foregroundStyle(flag.state.tint) }
                Text(flag.name)
                    .font(.system(size: isNext ? 13 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let eta = flag.eta {
                    Text(CockpitText.clock(eta))
                        .font(.system(size: isNext ? 13 : 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(flag.state.tint.opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            Rectangle()
                .fill(flag.state.tint)
                .frame(width: 2, height: isNext ? 14 : 8)
            Circle()
                .fill(flag.state.tint)
                .frame(width: 7, height: 7)
        }
        .frame(maxWidth: 200)
        .accessibilityHidden(true)
    }
}

/// The followed train: its line plate on a glowing glass capsule, the glow in the delay tint. The chevron under it points the way the train travels,
/// relative to the camera (in the follow view that is straight ahead). A train without a position for two minutes (`isStale`) keeps its place,
/// grey and without glow: the last place it was seen, not a live one.
struct CockpitTrainMarker: View {
    var line: Line?
    var state: RadarDelayState
    var heading: Double?
    var cameraHeading: Double
    var isHeld: Bool
    var isStale = false

    var body: some View {
        let tint = isStale ? RadarDelayState.unknown.tint : state.tint
        ZStack {
            // The glow: a soft disc and a ring that breathes while the train moves.
            if !isStale {
                Circle()
                    .fill(tint.opacity(0.42))
                    .frame(width: 92, height: 92)
                    .blur(radius: 16)
                let ring = Circle()
                    .strokeBorder(tint.opacity(0.55), lineWidth: 2)
                    .frame(width: 70, height: 70)
                // The ring breathes while the train moves; standing at a stop or at the end of its run it holds still.
                if isHeld { ring } else { ring.pulsingHalo(tint, scale: 1.5, period: 2.4) }
            }
            VStack(spacing: 3) {
                if let line {
                    PlannerLinePlate(line: line, size: .m)
                } else {
                    Image(systemName: "tram.fill").font(.title3).foregroundStyle(Theme.textPrimary)
                }
                Image(systemName: isHeld ? "pause.fill" : "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(isHeld ? 0 : CockpitAngle.delta(from: cameraHeading, to: heading ?? cameraHeading)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint, lineWidth: 2.5))
            .shadow(color: tint.opacity(isStale ? 0 : 0.7), radius: 12)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .opacity(isStale ? 0.8 : 1)
            .saturation(isStale ? 0 : 1)
        }
        .accessibilityHidden(true)
    }
}
