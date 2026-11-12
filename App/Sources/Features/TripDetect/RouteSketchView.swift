import SwiftUI
import KlimaCore

// MARK: tripdetect – the mini route of a proposal. Relative points only (`RouteSketch`), so nothing of where anybody was is
// on the card: the line draws itself once when the card first scrolls into view (docs/MOTION.md §15), a dashed line says
// "only the two stations are known".

struct RouteSketchView: View {
    let sketch: RouteSketch
    var lineWidth: CGFloat = 3

    var body: some View {
        DrawInReader(threshold: 0.3, animation: Motion.gentle) { isDrawn in
            GeometryReader { proxy in
                let points = scaled(in: proxy.size)
                ZStack {
                    SketchLine(points: points)
                        .trim(from: 0, to: isDrawn ? 1 : 0.001)
                        .stroke(Theme.routeGradient,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: sketch.isStraight ? [0.5, 7] : []))
                    if let first = points.first {
                        Circle().fill(Theme.glacier).frame(width: 9, height: 9).position(first)
                    }
                    if let last = points.last {
                        Circle().fill(Theme.dawn).frame(width: 11, height: 11).position(last)
                            .scaleEffect(isDrawn ? 1 : 0.2)
                            .opacity(isDrawn ? 1 : 0)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func scaled(in size: CGSize) -> [CGPoint] {
        let inset: CGFloat = 8
        let side = max(1, min(size.width, size.height) - inset * 2)
        let offsetX = (size.width - side) / 2, offsetY = (size.height - side) / 2
        return sketch.points.map { CGPoint(x: offsetX + CGFloat($0.x) * side, y: offsetY + CGFloat($0.y) * side) }
    }
}

struct SketchLine: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

/// The sketch on a small rounded tile (the inbox card's left side).
struct RouteSketchTile: View {
    let sketch: RouteSketch?
    var mode: TransportMode = .train
    var size = CGSize(width: 84, height: 72)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.modeTile + 2, style: .continuous)
                .fill(Theme.surfaceSecondary)
            if let sketch {
                RouteSketchView(sketch: sketch)
                    .padding(4)
            } else {
                Image(systemName: mode.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.modeColor(mode))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
