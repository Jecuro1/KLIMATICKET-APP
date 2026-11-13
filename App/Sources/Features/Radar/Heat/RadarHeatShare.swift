import SwiftUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers
import KlimaCore

// MARK: radarheat – "Pünktlichkeitskarte teilen" (docs/RADAR_HEATMAP.md §6). The map of the delay as an image: the heat cells on a dark
// night-blue ground (the base map is Apple's and is not part of an image), the headline figure, the bar and the honest note. Rendered
// lazily with `ImageRenderer` when the share sheet exports it (the pattern of `TktSharePass`). No personal data: the image holds the
// aggregated numbers and cells of the radar's current answer, no train, no name, no place of the person, no account.

struct RadarHeatShare: Transferable {
    var cells: [HeatDrawCell]
    var summary: HeatSummary
    var date: Date

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { share in
            try await share.renderPNG()
        }
        .suggestedFileName("KlimaBilanz-Puenktlichkeit.png")
    }

    /// 360 × 500 points at 3×: 1080 × 1500 pixels.
    @MainActor
    func renderPNG() throws -> Data {
        let renderer = ImageRenderer(content: RadarHeatShareCard(cells: cells, summary: summary, date: date))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: 500)
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else { throw RadarHeatShareError.renderFailed }
        return data
    }
}

enum RadarHeatShareError: Error {
    case renderFailed
}

/// The card. Always dark (the dark variants of the tokens), so it looks the same wherever it is shared.
struct RadarHeatShareCard: View {
    var cells: [HeatDrawCell]
    var summary: HeatSummary
    var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(text: "KlimaBilanz · Pünktlichkeit", color: Color.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.punctualPercent.map { "\($0) %" } ?? "–")
                    .font(.system(size: 72, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(RadarHeatText.punctualLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(RadarHeatText.realtimeLine(summary))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            HeatShareField(cells: cells)
                .frame(height: 150)
                .accessibilityHidden(true)
            HeatStackedBar(summary: summary)
            Text(legendLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text("Stand \(Format.date(date)), \(Format.time(date)) Uhr")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Radar-Bereich Österreich und Grenzgebiete. Verspätung am nächsten Halt laut ÖBB-Echtzeit, Positionen berechnet. Züge ohne Echtzeit-Daten zählen nie als pünktlich. Graue Umrisse: zu wenige Züge für eine Farbe. KlimaBilanz ist eine unabhängige App.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 360, height: 500, alignment: .topLeading)
        .clipped()
        .background(LinearGradient(colors: [Theme.background, Theme.sheetBackground], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }

    private var legendLine: String {
        [HeatBucket.onTime, .delayed, .severe, .cancelled].map { bucket -> String in
            let count: Int
            switch bucket {
            case .onTime: count = summary.onTime
            case .delayed: count = summary.delayed
            case .severe: count = summary.severe
            default: count = summary.cancelled
            }
            return "\(RadarHeatText.legend(bucket)) \(count)"
        }.joined(separator: " · ")
    }
}

/// The cells of the heat layer on a flat plane: longitude scaled by the cosine of Austria's latitude, no base map. A glow under crisp
/// hexagons; a cell without a colour is a faint outline.
struct HeatShareField: View {
    var cells: [HeatDrawCell]

    var body: some View {
        Canvas { context, size in
            let palette = HeatPalette(scheme: .dark)
            let area = RadarTileGrid.coverage
            let cosLatitude = cos(HeatGrid.originLatitude * Double.pi / 180)
            let width = (area.east - area.west) * cosLatitude, height = area.north - area.south
            let scale = min(size.width / width, size.height / height)
            let originX = (size.width - width * scale) / 2, originY = (size.height - height * scale) / 2
            func point(_ geo: GeoPoint) -> CGPoint {
                CGPoint(x: originX + (geo.longitude - area.west) * cosLatitude * scale, y: originY + (area.north - geo.latitude) * scale)
            }
            func hexagon(_ id: HeatCellID, _ factor: Double) -> Path {
                var path = Path()
                for (index, corner) in HeatGrid.vertices(of: id, scale: factor).enumerated() {
                    if index == 0 { path.move(to: point(corner)) } else { path.addLine(to: point(corner)) }
                }
                path.closeSubpath()
                return path
            }
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 5))
                for cell in cells where !cell.isNeutral {
                    glow.fill(hexagon(cell.id, 1.9), with: .color(palette.color(cell.blend).opacity(0.5 * cell.strength)))
                }
            }
            for cell in cells {
                if cell.isNeutral {
                    context.stroke(hexagon(cell.id, 0.85), with: .color(Color.white.opacity(0.16)), lineWidth: 0.5)
                } else {
                    context.fill(hexagon(cell.id, 0.95), with: .color(palette.color(cell.blend).opacity(0.55 + 0.45 * cell.strength)))
                }
            }
        }
    }
}
