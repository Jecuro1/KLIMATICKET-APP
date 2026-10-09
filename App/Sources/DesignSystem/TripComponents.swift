import SwiftUI
import KlimaCore

/// Vertical route glyph: hollow origin dot, dotted line, filled destination dot.
struct RouteGlyph: View {
    var color: Color = Theme.accent
    var endColor: Color = Theme.summit
    var height: CGFloat = 40

    var body: some View {
        VStack(spacing: 3) {
            Circle().strokeBorder(color, lineWidth: 2.5).frame(width: 11, height: 11)
            Line()
                .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
                .frame(width: 2, height: max(4, height - 28))
            Circle().fill(endColor).frame(width: 11, height: 11)
                .overlay(Circle().stroke(endColor.opacity(0.25), lineWidth: 4))
        }
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return p
        }
    }
}

/// Standard trip row: mode icon · "A → B" · "Heute, 07:42 · Zug · 101 km" · value.
struct TripRow: View {
    var fromName: String
    var toName: String
    var date: Date
    var mode: TransportMode
    var distanceKm: Double
    var value: Double
    var isRoundTrip: Bool = false
    var showsDate: Bool = true

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: mode, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(TripRow.short(fromName))
                    Image(systemName: isRoundTrip ? "arrow.left.arrow.right" : "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                    Text(TripRow.short(toName))
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euroPrecise(value))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fromName) nach \(toName), \(mode.displayName)\(isRoundTrip ? ", hin und retour" : "")")
        .accessibilityValue("\(Format.euroPrecise(value)), \(Format.relativeDay(date)) \(Format.time(date))")
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsDate { parts.append("\(Format.relativeDay(date)), \(Format.time(date))") }
        parts.append(mode.displayName)
        if distanceKm > 0 { parts.append(Format.km(distanceKm * (isRoundTrip ? 2 : 1))) }
        return parts.joined(separator: " · ")
    }

    /// Shortens long station names for rows ("Innsbruck Hauptbahnhof" → "Innsbruck Hbf", "St. Anton am Arlberg" → "St. Anton").
    static func short(_ name: String) -> String {
        var n = name.replacingOccurrences(of: "Hauptbahnhof", with: "Hbf")
        for suffix in [" am Arlberg", " im Pongau", " an der Donau", " in Tirol"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
        }
        return n
    }
}

extension TripRow {
    init(trip: TripEntity, showsDate: Bool = true) {
        self.init(fromName: trip.fromName, toName: trip.toName, date: trip.date, mode: trip.mode,
                  distanceKm: trip.distanceKm, value: trip.totalValue, isRoundTrip: trip.isRoundTrip, showsDate: showsDate)
    }
}

/// Horizontal progress rail with start/end labels and an optional "today" marker
/// (ticket validity, amortisation impact preview).
struct ProgressRail: View {
    /// 0…1
    var progress: Double
    /// Optional second segment (e.g. the value a new trip adds), 0…1 absolute end.
    var preview: Double? = nil
    var leadingLabel: String? = nil
    var trailingLabel: String? = nil
    var height: CGFloat = 10
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.progressGradient)

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textTertiary.opacity(0.18))
                    if let preview, preview > progress {
                        Capsule().fill(Theme.summit.opacity(0.85))
                            .frame(width: max(height, w * min(preview, 1)))
                    }
                    Capsule().fill(fill)
                        .frame(width: max(height, w * min(max(progress, 0), 1)))
                }
            }
            .frame(height: height)
            if leadingLabel != nil || trailingLabel != nil {
                HStack {
                    Text(leadingLabel ?? "")
                    Spacer()
                    Text(trailingLabel ?? "")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .animation(.spring(duration: 0.6), value: progress)
        .animation(.spring(duration: 0.6), value: preview)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Format.percent(preview ?? progress))
    }
}
