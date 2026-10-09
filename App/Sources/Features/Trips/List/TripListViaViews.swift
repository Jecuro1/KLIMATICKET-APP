import SwiftUI
import KlimaCore

// Via stops in the trip list module (docs/VIA.md §5): the detail timeline rows between "Von" and "Nach" and the map dot.
// Same rail as TripListDetailStop (dotted line, ring/dot lined up with the name at any text size), with a smaller dot.

/// "Über / Feldkirch / Bahnhof · Vorarlberg" rows on the detail route rail – nothing without vias.
struct TripListViaDetailStops: View {
    let vias: [TripVia]
    /// Resolved stations in the same order (nil = name only, e.g. from a CSV import).
    let stations: [Station?]

    var body: some View {
        ForEach(Array(vias.enumerated()), id: \.offset) { index, via in
            let station = index < stations.count ? stations[index] : nil
            TripListViaDetailStop(name: station?.name ?? via.name, subtitle: TripListFormat.stationSubtitle(station),
                                  index: index, count: vias.count)
        }
    }
}

private struct TripListViaDetailStop: View {
    let name: String
    let subtitle: String?
    let index: Int
    let count: Int

    /// Caption line + half the name line (body) − the dot radius: the dot sits on the name.
    @ScaledMetric(relativeTo: .body) private var dotTop: CGFloat = 29
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 3) {
                rail.frame(height: max(0, dotTop - 3))
                Circle()
                    .fill(Theme.accent.mix(with: Theme.summit, by: count > 1 ? 0.3 + 0.4 * Double(index) / Double(count - 1) : 0.5))
                    .frame(width: dotSize, height: dotSize)
                rail.frame(maxHeight: .infinity)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(count > 1 ? "Über · Zwischenhalt \(index + 1)" : "Über")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, Theme.Spacing.m)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count > 1 ? "Über \(name), Zwischenhalt \(index + 1) von \(count)" : "Über \(name), Zwischenhalt")
    }

    private var rail: some View {
        TripListViaRail()
            .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
            .frame(width: 2)
    }
}

private struct TripListViaRail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// A via on the detail map: small white-ringed dot (the endpoints keep their balloons).
struct TripListViaMapDot: View {
    var body: some View {
        Circle()
            .fill(Theme.accent.mix(with: Theme.summit, by: 0.5))
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
