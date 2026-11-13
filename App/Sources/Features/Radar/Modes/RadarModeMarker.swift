import SwiftUI
import KlimaCore

// MARK: radarmodes – a vehicle's marker is the Wegzeichen plate of its line (docs/RADAR_MODES.md §5): shape per family (Fern/Nacht wedge, Regio
// rectangle, S-Bahn and Bim soft, U-Bahn square, Bus capsule), the plate's own fill and text colour (≥ 4.5 : 1 in light and dark), and on the
// radar the Bim plate also carries the tram symbol, so shape, glyph and text tell the five modes apart without the colour. Around it the delay
// ring in the plate's shape, outside the plate with a 1-pt gap (an orange „verspätet“ ring on an orange bus plate would vanish otherwise).

extension LineBadge {
    /// The plate of a vehicle on the radar. Bim plates get the tram symbol (main's Wegzeichen draws them with the number only, like the
    /// S-Bahn's soft shape); a vehicle without a line gets a neutral dot plate.
    static func radar(_ line: Line?, size: PlateSize) -> LineBadge {
        guard let line else { return LineBadge(kind: .sonst, text: "•", spoken: "Fahrzeug") }
        var badge = LineBadge(line: line, size: size)
        if badge.kind == .tram, badge.glyph == nil { badge.glyph = .symbol("tram.fill") }
        if badge.text.isEmpty, badge.glyph == nil { badge.text = "•" }
        return badge
    }
}

/// The ring around a plate: the plate's own shape, `outset` points outside its edge.
struct RadarPlateRing: Shape {
    var kind: LineKind
    var outset: CGFloat

    func path(in rect: CGRect) -> Path {
        let ring = rect.insetBy(dx: -outset, dy: -outset)
        return kind.plateShape(height: ring.height).path(in: ring)
    }
}

/// A plate with its delay ring: green on time, orange from five minutes, red cancelled, grey without realtime; dashed while the position is our
/// own estimate between two answers.
struct RadarModePlate: View {
    var badge: LineBadge
    var delay: RadarDelayState
    var isEstimate: Bool
    var size: PlateSize = .s

    var body: some View {
        LinePlate(badge, size: size)
            .overlay { RadarPlateRing(kind: badge.kind, outset: 0.5).stroke(Self.gap, lineWidth: 1) }
            .overlay {
                RadarPlateRing(kind: badge.kind, outset: 2)
                    .stroke(delay.tint, style: StrokeStyle(lineWidth: 2, dash: isEstimate ? [3, 2] : []))
            }
    }

    /// White in light mode, black in dark: the gap between plate and ring.
    static let gap = Color(light: .white, dark: .black)
}

/// How the markers look (`RadarDisplay`): plate size, dots, destination, arrow. `.standard` is the radar's own look (Normal, with arrow).
struct RadarMarkerStyle: Equatable {
    var size: RadarDisplay.Size = .normal
    var dots = false
    var arrows = true
    var destination: String?

    static let standard = RadarMarkerStyle()

    /// Klein / Normal / Groß: 10 / 11 / 13 pt plate text.
    var plateSize: PlateSize {
        switch size {
        case .small: .xs
        case .normal: .s
        case .large: .m
        }
    }

    /// „Nur Punkte“: 9 / 10.5 / 12 pt tall.
    var dotHeight: CGFloat {
        switch size {
        case .small: 9
        case .normal: 10.5
        case .large: 12
        }
    }
}

/// „Nur Punkte“: the plate's shape in its fill, without text, with the same delay ring.
struct RadarModeDot: View {
    var badge: LineBadge
    var delay: RadarDelayState
    var isEstimate: Bool
    var height: CGFloat

    var body: some View {
        let width = badge.kind.shape == .square ? height : height * 1.35
        badge.kind.plateShape(height: height)
            .fill(badge.kind.fill(for: badge.text))
            .frame(width: width, height: height)
            .overlay { RadarPlateRing(kind: badge.kind, outset: 0.5).stroke(RadarModePlate.gap, lineWidth: 1) }
            .overlay {
                RadarPlateRing(kind: badge.kind, outset: 1.8)
                    .stroke(delay.tint, style: StrokeStyle(lineWidth: 1.6, dash: isEstimate ? [2, 1.5] : []))
            }
    }
}

/// „Linie und Ziel“: the destination under the plate, on an opaque capsule so it stays legible between markers.
struct RadarDestinationLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: 120)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Theme.sheetBackground.opacity(0.92), in: .capsule)
    }
}

extension RadarView {
    /// The marker style of „Darstellung“; the destination only close up and with at most 80 single markers.
    func markerStyle(for pin: RadarPin) -> RadarMarkerStyle {
        let display = model.display
        let destination = display.showsDestination(latitudeSpan: model.spanDegrees, singles: model.singleCount) ? pin.vehicle.direction : nil
        return RadarMarkerStyle(size: display.size, dots: display.label == .dots, arrows: display.arrows, destination: destination)
    }
}
