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
