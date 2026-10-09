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

/// Standard trip row (rail-editorial layout): mode icon · stacked "von / nach" with a mini route glyph ·
/// value and day/time on the trailing side. Station names never truncate mid-word (they scale slightly).
struct TripRow: View {
    var fromName: String
    var toName: String
    var date: Date
    var mode: TransportMode
    var distanceKm: Double
    var value: Double
    var isRoundTrip: Bool = false
    var showsDate: Bool = true
    /// Via stations ("über Feldkirch" under the names; docs/VIA.md).  // MARK: via
    var via: [TripVia] = []

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ModeIcon(mode: mode, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.s) {
                    MiniRouteGlyph(isRoundTrip: isRoundTrip, color: Theme.modeColor(mode))
                        .frame(width: 10, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TripRow.short(fromName))
                        Text(TripRow.short(toName))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                if !via.isEmpty { ViaCaption(vias: via).padding(.leading, 10 + Theme.Spacing.s) }
            }
            .layoutPriority(1)
            Spacer(minLength: Theme.Spacing.xs)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.euroPrecise(value))
                    .font(Theme.Typography.numberSmall)
                    .foregroundStyle(Theme.textPrimary)
                Text(trailingCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ViaText.spoken(from: fromName, via: via, to: toName)), \(mode.displayName)\(isRoundTrip ? ", hin und retour" : "")")
        .accessibilityValue("\(Format.euroPrecise(value)), \(Format.relativeDay(date)) \(Format.time(date)), \(Format.km(distanceKm * (isRoundTrip ? 2 : 1)))")
    }

    private var trailingCaption: String {
        if showsDate { return "\(Format.relativeDay(date)) · \(Format.time(date))" }
        var parts = [Format.time(date)]
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

/// Two-stop vertical glyph used inside rows (hollow origin, filled destination; arrows for round trips).
struct MiniRouteGlyph: View {
    var isRoundTrip: Bool
    var color: Color

    var body: some View {
        VStack(spacing: 2) {
            Circle().strokeBorder(color, lineWidth: 2).frame(width: 8, height: 8)
            Capsule().fill(color.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
            if isRoundTrip {
                Circle().strokeBorder(color, lineWidth: 2).background(Circle().fill(color.opacity(0.5))).frame(width: 8, height: 8)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

extension TripRow {
    init(trip: TripEntity, showsDate: Bool = true) {
        self.init(fromName: trip.fromName, toName: trip.toName, date: trip.date, mode: trip.mode,
                  distanceKm: trip.distanceKm, value: trip.totalValue, isRoundTrip: trip.isRoundTrip, showsDate: showsDate,
                  via: trip.via)   // MARK: via
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
