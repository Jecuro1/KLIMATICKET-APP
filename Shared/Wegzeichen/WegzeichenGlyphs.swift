import SwiftUI

// Wegzeichen glyphs and the Schneehaube (BADGE_SPEC §2.1, §2.3). Own drawings, 24-pt grid, even-odd fill.

// MARK: - Snow cap ("Schneehaube") for mode tiles and map pins

struct SnowcapShape: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0, 0))
        path.addLine(to: p(1, 0))
        path.addLine(to: p(1, 0.175))
        path.addQuadCurve(to: p(0.855, 0.195), control: p(0.93, 0.245))
        path.addQuadCurve(to: p(0.67, 0.215), control: p(0.77, 0.305))
        path.addQuadCurve(to: p(0.505, 0.205), control: p(0.585, 0.265))
        path.addQuadCurve(to: p(0.315, 0.215), control: p(0.405, 0.315))
        path.addQuadCurve(to: p(0.155, 0.195), control: p(0.225, 0.275))
        path.addQuadCurve(to: p(0, 0.18), control: p(0.075, 0.255))
        path.closeSubpath()
        return path
    }
}

struct SnowcapModifier: ViewModifier {
    var cornerRadius: CGFloat
    var size: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(y: size * 0.06)
            .overlay(alignment: .top) {
                SnowcapShape()
                    .fill(Theme.snow)
                    .shadow(color: Color(light: "#1E3C6E47", dark: "#00000059"), radius: 0.6, y: 0.8)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// White scalloped cap on top of a mode tile = "stop lies in a ski area".
    @ViewBuilder
    func snowcap(_ on: Bool, size: CGFloat, cornerRadius: CGFloat) -> some View {
        if on { modifier(SnowcapModifier(cornerRadius: cornerRadius, size: size)) } else { self }
    }
}

// MARK: - Custom glyphs (generated from enrich/design/src/glyphs.py, 24-pt grid, even-odd)

struct Peaks3Glyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(1.7, 18.9))
        path.addLine(to: p(6.75, 11.15))
        path.addQuadCurve(to: p(8.25, 11.15), control: p(7.5, 10.05))
        path.addLine(to: p(9.75, 13.25))
        path.addLine(to: p(12.75, 6.25))
        path.addQuadCurve(to: p(14.25, 6.25), control: p(13.5, 4.95))
        path.addLine(to: p(16.55, 10.75))
        path.addLine(to: p(17.85, 9.35))
        path.addQuadCurve(to: p(19.3, 9.55), control: p(18.6, 8.6))
        path.addLine(to: p(22.3, 18.9))
        path.addQuadCurve(to: p(21.6, 20), control: p(22.65, 20))
        path.addLine(to: p(2.4, 20))
        path.addQuadCurve(to: p(1.7, 18.9), control: p(1.3, 20))
        path.closeSubpath()
        path.move(to: p(12.05, 9.1))
        path.addLine(to: p(13.05, 6.95))
        path.addQuadCurve(to: p(13.95, 6.95), control: p(13.5, 6.15))
        path.addLine(to: p(15.05, 9))
        path.addLine(to: p(14.3, 8.55))
        path.addLine(to: p(13.5, 9.55))
        path.addLine(to: p(12.75, 8.6))
        path.closeSubpath()
        path.move(to: p(6.15, 12.95))
        path.addLine(to: p(7.05, 11.6))
        path.addQuadCurve(to: p(7.95, 11.6), control: p(7.5, 11))
        path.addLine(to: p(8.75, 12.7))
        path.addLine(to: p(8.15, 12.45))
        path.addLine(to: p(7.5, 13.15))
        path.addLine(to: p(6.85, 12.5))
        path.closeSubpath()
        path.move(to: p(17.75, 11.25))
        path.addLine(to: p(18.25, 10.4))
        path.addQuadCurve(to: p(18.95, 10.45), control: p(18.6, 9.95))
        path.addLine(to: p(19.55, 11.45))
        path.addLine(to: p(19, 11.2))
        path.addLine(to: p(18.55, 11.75))
        path.addLine(to: p(18.15, 11.15))
        path.closeSubpath()
        return path
    }
}
// Render: Peaks3Glyph().fill(style: FillStyle(eoFill: true))

struct Peaks2Glyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(2.2, 18.9))
        path.addLine(to: p(8.25, 8.85))
        path.addQuadCurve(to: p(9.75, 8.85), control: p(9, 7.6))
        path.addLine(to: p(12.6, 13.6))
        path.addLine(to: p(14.55, 11))
        path.addQuadCurve(to: p(16.05, 11), control: p(15.3, 10.05))
        path.addLine(to: p(21.8, 18.9))
        path.addQuadCurve(to: p(21.1, 20), control: p(22.25, 20))
        path.addLine(to: p(2.9, 20))
        path.addQuadCurve(to: p(2.2, 18.9), control: p(1.75, 20))
        path.closeSubpath()
        path.move(to: p(7.4, 11.75))
        path.addLine(to: p(8.55, 9.65))
        path.addQuadCurve(to: p(9.45, 9.65), control: p(9, 8.85))
        path.addLine(to: p(10.6, 11.6))
        path.addLine(to: p(9.85, 11.2))
        path.addLine(to: p(9, 12.2))
        path.addLine(to: p(8.2, 11.25))
        path.closeSubpath()
        path.move(to: p(14.25, 12.85))
        path.addLine(to: p(14.95, 11.75))
        path.addQuadCurve(to: p(15.65, 11.75), control: p(15.3, 11.25))
        path.addLine(to: p(16.4, 12.85))
        path.addLine(to: p(15.85, 12.6))
        path.addLine(to: p(15.3, 13.25))
        path.addLine(to: p(14.8, 12.6))
        path.closeSubpath()
        return path
    }
}
// Render: Peaks2Glyph().fill(style: FillStyle(eoFill: true))

struct Peaks1Glyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(3, 18.9))
        path.addLine(to: p(11.2, 6.35))
        path.addQuadCurve(to: p(12.8, 6.35), control: p(12, 5.1))
        path.addLine(to: p(21, 18.9))
        path.addQuadCurve(to: p(20.3, 20), control: p(21.55, 20))
        path.addLine(to: p(3.7, 20))
        path.addQuadCurve(to: p(3, 18.9), control: p(2.45, 20))
        path.closeSubpath()
        path.move(to: p(9.55, 10.2))
        path.addLine(to: p(11.55, 7.15))
        path.addQuadCurve(to: p(12.45, 7.15), control: p(12, 6.45))
        path.addLine(to: p(14.45, 10.15))
        path.addLine(to: p(13.5, 9.65))
        path.addLine(to: p(12.6, 10.75))
        path.addLine(to: p(11.7, 9.75))
        path.addLine(to: p(10.6, 10.65))
        path.closeSubpath()
        return path
    }
}
// Render: Peaks1Glyph().fill(style: FillStyle(eoFill: true))

struct GlacierGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(2.6, 18.9))
        path.addLine(to: p(9.95, 7.35))
        path.addQuadCurve(to: p(11.55, 7.35), control: p(10.75, 6.1))
        path.addLine(to: p(14.1, 11.4))
        path.addLine(to: p(15.4, 9.9))
        path.addQuadCurve(to: p(16.8, 10), control: p(16.1, 9.1))
        path.addLine(to: p(21.4, 18.9))
        path.addQuadCurve(to: p(20.7, 20), control: p(21.95, 20))
        path.addLine(to: p(3.3, 20))
        path.addQuadCurve(to: p(2.6, 18.9), control: p(2.05, 20))
        path.closeSubpath()
        path.move(to: p(7.75, 11.9))
        path.addLine(to: p(10.35, 7.95))
        path.addQuadCurve(to: p(11.15, 7.95), control: p(10.75, 7.3))
        path.addLine(to: p(13.9, 12.25))
        path.addQuadCurve(to: p(12.1, 12.55), control: p(12.9, 11.6))
        path.addQuadCurve(to: p(10.4, 12.35), control: p(11.3, 13.4))
        path.addQuadCurve(to: p(7.75, 11.9), control: p(9.4, 11.3))
        path.closeSubpath()
        path.move(to: p(19, 2.6))
        path.addQuadCurve(to: p(21.4, 5), control: p(19.35, 4.65))
        path.addQuadCurve(to: p(19, 7.4), control: p(19.35, 5.35))
        path.addQuadCurve(to: p(16.6, 5), control: p(18.65, 5.35))
        path.addQuadCurve(to: p(19, 2.6), control: p(18.65, 4.65))
        path.closeSubpath()
        return path
    }
}
// Render: GlacierGlyph().fill(style: FillStyle(eoFill: true))

struct StationClockGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(12, 2))
        path.addCurve(to: p(18.6, 8.6), control1: p(15.65, 2), control2: p(18.6, 4.95))
        path.addCurve(to: p(12, 15.2), control1: p(18.6, 12.25), control2: p(15.65, 15.2))
        path.addCurve(to: p(5.4, 8.6), control1: p(8.35, 15.2), control2: p(5.4, 12.25))
        path.addCurve(to: p(12, 2), control1: p(5.4, 4.95), control2: p(8.35, 2))
        path.closeSubpath()
        path.move(to: p(12, 3.6))
        path.addCurve(to: p(7, 8.6), control1: p(9.24, 3.6), control2: p(7, 5.84))
        path.addCurve(to: p(12, 13.6), control1: p(7, 11.36), control2: p(9.24, 13.6))
        path.addCurve(to: p(17, 8.6), control1: p(14.76, 13.6), control2: p(17, 11.36))
        path.addCurve(to: p(12, 3.6), control1: p(17, 5.84), control2: p(14.76, 3.6))
        path.closeSubpath()
        path.move(to: p(12, 4.9))
        path.addLine(to: p(12, 4.9))
        path.addQuadCurve(to: p(12.7, 5.6), control: p(12.7, 4.9))
        path.addLine(to: p(12.7, 8.6))
        path.addQuadCurve(to: p(12, 9.3), control: p(12.7, 9.3))
        path.addLine(to: p(12, 9.3))
        path.addQuadCurve(to: p(11.3, 8.6), control: p(11.3, 9.3))
        path.addLine(to: p(11.3, 5.6))
        path.addQuadCurve(to: p(12, 4.9), control: p(11.3, 4.9))
        path.closeSubpath()
        path.move(to: p(11.55, 9.4))
        path.addLine(to: p(14.45, 10.95))
        path.addQuadCurve(to: p(14.75, 11.85), control: p(15.05, 11.3))
        path.addQuadCurve(to: p(13.85, 12), control: p(14.45, 12.35))
        path.addLine(to: p(11, 10.45))
        path.addQuadCurve(to: p(10.75, 9.55), control: p(10.45, 10.1))
        path.addQuadCurve(to: p(11.55, 9.4), control: p(11.05, 9.05))
        path.closeSubpath()
        path.move(to: p(11.75, 14.9))
        path.addLine(to: p(12.25, 14.9))
        path.addQuadCurve(to: p(12.85, 15.5), control: p(12.85, 14.9))
        path.addLine(to: p(12.85, 19.7))
        path.addQuadCurve(to: p(12.25, 20.3), control: p(12.85, 20.3))
        path.addLine(to: p(11.75, 20.3))
        path.addQuadCurve(to: p(11.15, 19.7), control: p(11.15, 20.3))
        path.addLine(to: p(11.15, 15.5))
        path.addQuadCurve(to: p(11.75, 14.9), control: p(11.15, 14.9))
        path.closeSubpath()
        path.move(to: p(8.6, 19.6))
        path.addLine(to: p(15.4, 19.6))
        path.addQuadCurve(to: p(16.4, 20.6), control: p(16.4, 19.6))
        path.addLine(to: p(16.4, 20.6))
        path.addQuadCurve(to: p(15.4, 21.6), control: p(16.4, 21.6))
        path.addLine(to: p(8.6, 21.6))
        path.addQuadCurve(to: p(7.6, 20.6), control: p(7.6, 21.6))
        path.addLine(to: p(7.6, 20.6))
        path.addQuadCurve(to: p(8.6, 19.6), control: p(7.6, 19.6))
        path.closeSubpath()
        return path
    }
}
// Render: StationClockGlyph().fill(style: FillStyle(eoFill: true))

struct GondolaGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        path.move(to: p(2.4, 6.2))
        path.addLine(to: p(21.6, 2.6))
        path.addQuadCurve(to: p(22.55, 3.25), control: p(22.4, 2.45))
        path.addQuadCurve(to: p(21.9, 4.2), control: p(22.7, 4.05))
        path.addLine(to: p(2.7, 7.8))
        path.addQuadCurve(to: p(1.75, 7.15), control: p(1.9, 7.95))
        path.addQuadCurve(to: p(2.4, 6.2), control: p(1.6, 6.35))
        path.closeSubpath()
        path.move(to: p(11.75, 6.05))
        path.addLine(to: p(12.25, 6.05))
        path.addQuadCurve(to: p(12.75, 6.55), control: p(12.75, 6.05))
        path.addLine(to: p(12.75, 9.1))
        path.addQuadCurve(to: p(12.25, 9.6), control: p(12.75, 9.6))
        path.addLine(to: p(11.75, 9.6))
        path.addQuadCurve(to: p(11.25, 9.1), control: p(11.25, 9.6))
        path.addLine(to: p(11.25, 6.55))
        path.addQuadCurve(to: p(11.75, 6.05), control: p(11.25, 6.05))
        path.closeSubpath()
        path.move(to: p(9, 9.6))
        path.addLine(to: p(15, 9.6))
        path.addQuadCurve(to: p(18, 12.6), control: p(18, 9.6))
        path.addLine(to: p(18, 17.6))
        path.addQuadCurve(to: p(15, 20.6), control: p(18, 20.6))
        path.addLine(to: p(9, 20.6))
        path.addQuadCurve(to: p(6, 17.6), control: p(6, 20.6))
        path.addLine(to: p(6, 12.6))
        path.addQuadCurve(to: p(9, 9.6), control: p(6, 9.6))
        path.closeSubpath()
        path.move(to: p(8.8, 11.6))
        path.addLine(to: p(10.4, 11.6))
        path.addQuadCurve(to: p(11.3, 12.5), control: p(11.3, 11.6))
        path.addLine(to: p(11.3, 14.3))
        path.addQuadCurve(to: p(10.4, 15.2), control: p(11.3, 15.2))
        path.addLine(to: p(8.8, 15.2))
        path.addQuadCurve(to: p(7.9, 14.3), control: p(7.9, 15.2))
        path.addLine(to: p(7.9, 12.5))
        path.addQuadCurve(to: p(8.8, 11.6), control: p(7.9, 11.6))
        path.closeSubpath()
        path.move(to: p(13.6, 11.6))
        path.addLine(to: p(15.2, 11.6))
        path.addQuadCurve(to: p(16.1, 12.5), control: p(16.1, 11.6))
        path.addLine(to: p(16.1, 14.3))
        path.addQuadCurve(to: p(15.2, 15.2), control: p(16.1, 15.2))
        path.addLine(to: p(13.6, 15.2))
        path.addQuadCurve(to: p(12.7, 14.3), control: p(12.7, 15.2))
        path.addLine(to: p(12.7, 12.5))
        path.addQuadCurve(to: p(13.6, 11.6), control: p(12.7, 11.6))
        path.closeSubpath()
        return path
    }
}
// Render: GondolaGlyph().fill(style: FillStyle(eoFill: true))
