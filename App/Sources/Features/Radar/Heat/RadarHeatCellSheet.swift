import SwiftUI
import KlimaCore

// MARK: radarheat – the trains of one cell (docs/RADAR_HEATMAP.md §5). A tap on a cell of the heat layer, or on a hot spot, opens this
// sheet: what the cell says (its median delay, or why it has no colour), what it rests on, and every train in it. A train opens
// the trip sheet on top of this one. The sheet follows the radar's answers: when the cell changes, so does the list.

struct RadarHeatCellSheet<TripSheet: View>: View {
    var model: RadarModel
    var cellID: HeatCellID
    @ViewBuilder var tripSheet: (RadarVehicle) -> TripSheet

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    private var heat: RadarHeatModel { model.heat }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let cell = heat.snapshot.cell(cellID) {
                        header(cell)
                        trains(in: cell)
                        Text(RadarHeatText.methodNote)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("In diesem Gebiet ist gerade kein Zug mehr.")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, Theme.Spacing.m)
                    }
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Gebiet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Schließen") { dismiss() } } }
        }
        .sheet(item: Binding(get: { heat.trainSheet }, set: { heat.trainSheet = $0 })) { vehicle in
            tripSheet(vehicle)
        }
    }

    // MARK: Header

    private func header(_ cell: HeatCell) -> some View {
        let palette = HeatPalette(scheme: colorScheme)
        let blend = cell.medianDelaySeconds.map { HeatRamp.blend(medianSeconds: $0) }
        return HStack(alignment: .top, spacing: Theme.Spacing.s) {
            HeatCellSwatch(blend: blend.map { palette.color($0) }, isNeutral: cell.isNeutral)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(RadarHeatText.place(cell.placeName))
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RadarHeatText.cellTitle(cell))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(cell.bucket?.textTint ?? Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RadarHeatText.cellBase(cell))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Trains

    private func trains(in cell: HeatCell) -> some View {
        let samples = heat.snapshot.samples(in: cell)
        return VStack(alignment: .leading, spacing: 2) {
            Kicker(text: samples.count == 1 ? "1 Zug" : "\(samples.count) Züge")
                .accessibilityAddTraits(.isHeader)
            GlassCard(padding: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                        if index > 0 { Divider() }
                        HeatTrainRow(sample: sample, line: model.vehicle(id: sample.tripID)?.line,
                                     isEnabled: model.vehicle(id: sample.tripID) != nil) {
                            if let vehicle = model.vehicle(id: sample.tripID) { heat.trainSheet = vehicle }
                        }
                    }
                }
            }
        }
    }
}

/// The cell as a small hexagon in the colour it has on the map; grey and hatched when it has no colour.
struct HeatCellSwatch: View {
    var blend: Color?
    var isNeutral: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let hexagon = HexagonShape()
            ZStack {
                if let blend, !isNeutral {
                    hexagon.fill(blend.opacity(0.25)).scaleEffect(1.0)
                    hexagon.fill(blend.opacity(0.7)).scaleEffect(0.78)
                    hexagon.stroke(blend, lineWidth: 1.5).scaleEffect(0.78)
                } else {
                    hexagon.fill(Theme.surfaceSecondary).scaleEffect(0.78)
                    hexagon.stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).scaleEffect(0.78)
                    Path { path in
                        path.move(to: CGPoint(x: side * 0.3, y: side * 0.66))
                        path.addLine(to: CGPoint(x: side * 0.66, y: side * 0.3))
                        path.move(to: CGPoint(x: side * 0.38, y: side * 0.76))
                        path.addLine(to: CGPoint(x: side * 0.76, y: side * 0.38))
                    }
                    .stroke(Theme.textTertiary, lineWidth: 1.5)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

/// A pointy-top hexagon filling its rectangle.
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<6 {
            let angle = (Double(index) * 60 - 30) * .pi / 180
            let point = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
