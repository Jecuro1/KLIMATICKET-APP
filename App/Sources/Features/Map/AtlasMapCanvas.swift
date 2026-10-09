import SwiftUI
import MapKit
import KlimaCore

/// What the camera should frame. Bump `revision` to re-frame the same target (e.g. after a filter change).
struct AtlasFraming: Equatable {
    enum Target: Equatable {
        case overview
        case route(String)
        case place(String)
    }

    var target: Target = .overview
    var revision = 0
    /// Share of the map height covered by something outside the map's safe area (e.g. a medium-height sheet).
    var coveredBottomFraction: CGFloat = 0
}

/// Size and safe area of the map view.
struct AtlasViewport: Equatable, Sendable {
    var size: CGSize = .zero
    var insets = EdgeInsets()
}

/// Where a station's name sits relative to its dot (chosen per frame to avoid collisions).
enum AtlasLabelSide: CaseIterable {
    case below, above, trailing, leading
}

/// The interactive MapKit canvas: frequency-weighted route arcs (glow on the top/selected route), glass station dots
/// sized by visits, collision-free labels for the five most visited stations, tap-to-select routes.
struct AtlasMapCanvas: View {
    let summary: AtlasSummary
    let look: AtlasMapLook
    let selectedRouteID: String?
    let highlightedPlaceID: String?
    let framing: AtlasFraming
    var onSelectRoute: (String?) -> Void

    /// Whether `Map` already frames a `.region` inside its safe area (bars, `safeAreaInset` content).
    /// When true we hand MapKit a region for the safe rectangle; otherwise we compensate for the insets ourselves.
    static let mapFramesInsideSafeArea = true

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position: MapCameraPosition = .region(Atlas.region(fitting: .austria, width: 390, height: 600).mkRegion)
    @State private var viewport = AtlasViewport()
    @State private var labels: [String: AtlasLabelSide] = [:]
    @State private var hasFramed = false
    @State private var debugText = ""

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                AtlasRouteLayers(routes: summary.routes, selectedID: selectedRouteID, palette: palette, scale: 1)
                ForEach(summary.places) { place in
                    Annotation(place.name, coordinate: place.location.coordinate, anchor: .center) {
                        AtlasStationDot(place: place,
                                        diameter: dotDiameter(place),
                                        color: palette.color(place.dominantMode),
                                        label: labels[place.id].map { (TripRow.short(place.name), $0) },
                                        isDimmed: isDimmed(place),
                                        isHighlighted: place.id == highlightedPlaceID)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(look.mapStyle)
            .mapControls {
                MapScaleView()
            }
            .onTapGesture { location in
                onSelectRoute(hitRoute(at: location, proxy: proxy))
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                placeLabels(proxy: proxy)
                if LaunchMode.isScreenshot {
                    let r = context.region
                    debugText += String(format: " | cam %.3f %.3f d%.3f/%.3f", r.center.latitude, r.center.longitude,
                                        r.span.latitudeDelta, r.span.longitudeDelta)
                    if let b = summary.bounds, let p = proxy.convert(b.center.coordinate, to: .local),
                       let q = proxy.convert(CLLocationCoordinate2D(latitude: b.maxLatitude, longitude: b.minLongitude), to: .local),
                       let z = proxy.convert(CLLocationCoordinate2D(latitude: b.minLatitude, longitude: b.maxLongitude), to: .local) {
                        debugText += String(format: " | bc %.0f,%.0f nw %.0f,%.0f se %.0f,%.0f", p.x, p.y, q.x, q.y, z.x, z.y)
                    }
                }
            }
            .onChange(of: labelKey) {
                placeLabels(proxy: proxy)
            }
        }
        .onGeometryChange(for: AtlasViewport.self) { geometry in
            AtlasViewport(size: geometry.size, insets: geometry.safeAreaInsets)
        } action: { newValue in
            viewport = newValue
            reframe(animated: hasFramed && !LaunchMode.isScreenshot)
            hasFramed = true
        }
        .onChange(of: framing) {
            reframe(animated: !reduceMotion && !LaunchMode.isScreenshot)
        }
        .overlay(alignment: .center) {
            if LaunchMode.isScreenshot {
                Image(systemName: "plus").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.red)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if LaunchMode.isScreenshot && !debugText.isEmpty {
                Text(debugText)
                    .font(.system(size: 9, design: .monospaced))
                    .padding(4)
                    .background(.yellow.opacity(0.8))
                    .foregroundStyle(.black)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Karte deiner Strecken")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Styling

    private var palette: AtlasPalette {
        AtlasPalette(environment: environment, look: look, scheme: colorScheme)
    }

    private var maxVisits: Int { summary.places.first?.visits ?? 1 }

    private func dotDiameter(_ place: AtlasPlace) -> CGFloat {
        let ratio = Double(place.visits) / Double(max(maxVisits, 1))
        return 7 + 9 * CGFloat(ratio.squareRoot())
    }

    private func isDimmed(_ place: AtlasPlace) -> Bool {
        guard let selectedRouteID, let route = summary.route(id: selectedRouteID) else { return false }
        return !route.touches(place.id)
    }

    private var labelKey: String {
        "\(summary.places.prefix(6).map(\.id).joined(separator: ";"))|\(highlightedPlaceID ?? "")|\(selectedRouteID ?? "")"
    }

    // MARK: Camera

    private var fullHeight: CGFloat { viewport.size.height + viewport.insets.top + viewport.insets.bottom }

    private func reframe(animated: Bool) {
        guard viewport.size.width > 1, viewport.size.height > 1 else { return }
        let bounds: AtlasBounds
        var pad = 0.08
        switch framing.target {
        case .overview:
            bounds = summary.bounds ?? .austria
        case .route(let id):
            guard let route = summary.route(id: id) else { return }
            bounds = AtlasBounds(points: route.path) ?? .austria
            pad = 0.16
        case .place(let id):
            guard let place = summary.place(id: id) else { return }
            bounds = AtlasBounds(points: [place.location]) ?? .austria
        }
        let region = Self.region(fitting: bounds, viewport: viewport,
                                 coveredBottom: framing.coveredBottomFraction * fullHeight, padding: pad,
                                 minimumSpanKm: framing.target == .overview ? 30 : 14)
        if LaunchMode.isScreenshot {
            debugText = String(format: "vp %.0fx%.0f t%.0f b%.0f | req %.3f %.3f d%.3f/%.3f", viewport.size.width,
                               viewport.size.height, viewport.insets.top, viewport.insets.bottom, region.centerLatitude,
                               region.centerLongitude, region.latitudeDelta, region.longitudeDelta)
        }
        if animated {
            withAnimation(.smooth(duration: 0.9)) { position = .region(region.mkRegion) }
        } else {
            position = .region(region.mkRegion)
        }
    }

    /// Region that shows `bounds` in the visible part of the map – the safe rectangle minus anything else covering it.
    /// `viewport.size` is the safe rectangle; the map itself extends under `viewport.insets` (bars, panel).
    static func region(fitting bounds: AtlasBounds, viewport: AtlasViewport, coveredBottom: CGFloat, padding: Double,
                       minimumSpanKm: Double) -> AtlasRegion {
        let safe = viewport.insets
        let safeW = Double(max(viewport.size.width, 1)), safeH = Double(max(viewport.size.height, 1))
        if mapFramesInsideSafeArea {
            let extraBottom = Double(max(0, coveredBottom - safe.bottom))
            return Atlas.region(fitting: bounds, width: safeW, height: safeH, insets: AtlasInsets(bottom: extraBottom),
                                padding: padding, minimumSpanKm: minimumSpanKm)
        }
        let fullW = safeW + Double(safe.leading + safe.trailing), fullH = safeH + Double(safe.top + safe.bottom)
        let insets = AtlasInsets(top: Double(safe.top), leading: Double(safe.leading),
                                 bottom: Double(max(safe.bottom, coveredBottom)), trailing: Double(safe.trailing))
        return Atlas.region(fitting: bounds, width: fullW, height: fullH, insets: insets,
                            padding: padding, minimumSpanKm: minimumSpanKm)
    }

    // MARK: Hit testing

    /// The route closest to the tap (within a finger's width), preferring more travelled routes on ties.
    private func hitRoute(at location: CGPoint, proxy: MapProxy) -> String? {
        var best: (id: String, distance: CGFloat)?
        for route in summary.routes {
            let points = route.path.compactMap { proxy.convert($0.coordinate, to: .local) }
            guard points.count > 1 else { continue }
            var d = CGFloat.greatestFiniteMagnitude
            for i in 1..<points.count {
                d = min(d, Self.distance(from: location, toSegment: points[i - 1], points[i]))
            }
            let tolerance = max(22, AtlasLineStyle.width(route) / 2 + 14)
            if d <= tolerance, d < (best?.distance ?? .greatestFiniteMagnitude) - 0.5 {
                best = (route.id, d)
            }
        }
        return best?.id
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: Labels

    /// Greedy cartographic placement: the most visited stations first, each tries below → above → right → left
    /// and skips positions that would collide with another label or dot.
    private func placeLabels(proxy: MapProxy) {
        var candidates = Array(summary.places.prefix(5))
        if let highlightedPlaceID, let place = summary.place(id: highlightedPlaceID), !candidates.contains(place) {
            candidates.insert(place, at: 0)
        }
        if let selectedRouteID, let route = summary.route(id: selectedRouteID) {
            for place in [route.to, route.from] where !candidates.contains(where: { $0.id == place.id }) {
                candidates.insert(place, at: 0)
            }
        }
        var dots: [String: CGRect] = [:]
        for place in summary.places {
            guard let p = proxy.convert(place.location.coordinate, to: .local) else { continue }
            let d = dotDiameter(place) + 6
            dots[place.id] = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
        }
        var taken: [CGRect] = []
        var result: [String: AtlasLabelSide] = [:]
        for place in candidates {
            guard let dot = dots[place.id] else { continue }
            let size = CGSize(width: CGFloat(TripRow.short(place.name).count) * 6.4 + 18, height: 22)
            for side in AtlasLabelSide.allCases {
                let rect = Self.labelRect(side: side, dot: dot, size: size)
                let hitsDot = dots.contains { $0.key != place.id && $0.value.insetBy(dx: 2, dy: 2).intersects(rect) }
                if !hitsDot, !taken.contains(where: { $0.intersects(rect) }) {
                    taken.append(rect)
                    taken.append(dot)
                    result[place.id] = side
                    break
                }
            }
        }
        if result != labels {
            withAnimation(.easeInOut(duration: 0.2)) { labels = result }
        }
    }

    static func labelRect(side: AtlasLabelSide, dot: CGRect, size: CGSize) -> CGRect {
        let gap: CGFloat = 4
        switch side {
        case .below: return CGRect(x: dot.midX - size.width / 2, y: dot.maxY + gap, width: size.width, height: size.height)
        case .above: return CGRect(x: dot.midX - size.width / 2, y: dot.minY - gap - size.height, width: size.width, height: size.height)
        case .trailing: return CGRect(x: dot.maxX + gap, y: dot.midY - size.height / 2, width: size.width, height: size.height)
        case .leading: return CGRect(x: dot.minX - gap - size.width, y: dot.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        guard let top = summary.topRoute else {
            return summary.places.isEmpty ? "Noch keine Strecken mit Kartenposition" : AtlasFormat.stations(summary.places.count)
        }
        return "\(summary.routes.count) Strecken, \(AtlasFormat.stations(summary.places.count)). "
            + "Meistgefahren: \(top.from.name) und \(top.to.name), \(AtlasFormat.legs(top.legs))."
    }
}

// MARK: - Palette

/// Mode colours resolved for the map: satellite imagery uses the brighter dark-mode palette so lines pop on the photo.
struct AtlasPalette {
    let environment: EnvironmentValues
    let look: AtlasMapLook
    let scheme: ColorScheme

    func color(_ mode: TransportMode) -> Color {
        var env = environment
        if look == .satellite { env.colorScheme = .dark }
        return Color(Theme.modeColor(mode).resolve(in: env))
    }

    var casing: Color { AtlasLineStyle.casing(look: look, scheme: scheme) }
}

// MARK: - Route layers

/// All route arcs: casing under everything, glow under the hero route, the coloured lines, and a bright core on the hero.
/// The hero is the selected route or – without a selection – the most travelled one.
struct AtlasRouteLayers: MapContent {
    let routes: [AtlasRoute]
    let selectedID: String?
    let palette: AtlasPalette
    var scale: CGFloat = 1
    var showsGlow = true

    var body: some MapContent {
        ForEach(drawOrder) { route in
            MapPolyline(coordinates: route.coordinates)
                .stroke(palette.casing.opacity(isDimmed(route) ? 0.35 : 1),
                        style: AtlasLineStyle.round(width(route) + 3 * scale))
        }
        ForEach(heroRoutes) { route in
            MapPolyline(coordinates: route.coordinates)
                .stroke(palette.color(route.dominantMode).opacity(0.16), style: AtlasLineStyle.round(width(route) + 16 * scale))
            MapPolyline(coordinates: route.coordinates)
                .stroke(palette.color(route.dominantMode).opacity(0.30), style: AtlasLineStyle.round(width(route) + 8 * scale))
        }
        ForEach(drawOrder) { route in
            MapPolyline(coordinates: route.coordinates)
                .stroke(palette.color(route.dominantMode).opacity(lineOpacity(route)), style: AtlasLineStyle.round(width(route)))
        }
        ForEach(heroRoutes) { route in
            MapPolyline(coordinates: route.coordinates)
                .stroke(Color.white.opacity(0.75), style: AtlasLineStyle.round(max(1, width(route) * 0.3)))
        }
    }

    /// Least travelled first so the important routes sit on top; the selected route always on top.
    private var drawOrder: [AtlasRoute] {
        var ordered = Array(routes.reversed())
        if let selectedID, let index = ordered.firstIndex(where: { $0.id == selectedID }) {
            ordered.append(ordered.remove(at: index))
        }
        return ordered
    }

    private var heroRoutes: [AtlasRoute] {
        guard showsGlow else { return [] }
        if let selectedID { return routes.filter { $0.id == selectedID } }
        return Array(routes.prefix(1))
    }

    private func width(_ route: AtlasRoute) -> CGFloat {
        AtlasLineStyle.width(route, scale: scale) * (route.id == selectedID ? 1.25 : 1)
    }

    private func isDimmed(_ route: AtlasRoute) -> Bool { selectedID != nil && route.id != selectedID }

    private func lineOpacity(_ route: AtlasRoute) -> Double {
        isDimmed(route) ? 0.22 : AtlasLineStyle.opacity(route)
    }
}

// MARK: - Station dot

/// Small glass dot sized by visits, coloured by the station's main mode; optional name label beside it.
struct AtlasStationDot: View {
    let place: AtlasPlace
    let diameter: CGFloat
    let color: Color
    let label: (String, AtlasLabelSide)?
    var isDimmed = false
    var isHighlighted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let outer = diameter + 6
        Circle()
            .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.15), color], startPoint: .top, endPoint: .bottom))
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1.5))
            .padding(3)
            .glassEffect(.regular, in: .circle)
            .background { if isHighlighted { highlightRing(size: outer) } }
            .overlay(alignment: labelAlignment) {
                if let label {
                    AtlasMapLabel(text: label.0, isEmphasized: isHighlighted)
                        .fixedSize()
                        .offset(labelOffset(side: label.1, outer: outer))
                        .transition(.opacity)
                }
            }
            .opacity(isDimmed ? 0.35 : 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(place.name)
            .accessibilityValue("\(AtlasFormat.visits(place.visits)), \(AtlasFormat.stateSubtitle(place))")
    }

    @ViewBuilder
    private func highlightRing(size: CGFloat) -> some View {
        if reduceMotion || LaunchMode.isScreenshot {
            Circle().stroke(Theme.summit, lineWidth: 2.5).frame(width: size + 10, height: size + 10)
        } else {
            PhaseAnimator([false, true]) { expanded in
                Circle()
                    .stroke(Theme.summit, lineWidth: 2.5)
                    .frame(width: size + 10, height: size + 10)
                    .scaleEffect(expanded ? 1.9 : 1)
                    .opacity(expanded ? 0 : 0.95)
            } animation: { expanded in
                expanded ? .easeOut(duration: 1.4) : .linear(duration: 0.01)
            }
        }
    }

    private var labelAlignment: Alignment {
        switch label?.1 {
        case .some(.above): .bottom
        case .some(.trailing): .leading
        case .some(.leading): .trailing
        default: .top
        }
    }

    private func labelOffset(side: AtlasLabelSide, outer: CGFloat) -> CGSize {
        switch side {
        case .below: CGSize(width: 0, height: outer + 4)
        case .above: CGSize(width: 0, height: -(outer + 4))
        case .trailing: CGSize(width: outer + 4, height: 0)
        case .leading: CGSize(width: -(outer + 4), height: 0)
        }
    }
}

/// Station name on the map: small frosted capsule that stays legible on the muted map and on satellite imagery.
struct AtlasMapLabel: View {
    let text: String
    var isEmphasized = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(isEmphasized ? Theme.summit.opacity(0.8) : Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
