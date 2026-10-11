import SwiftUI
import KlimaCore

/// The journey at a glance (UX §4.2): one capsule per ride in the family colour with its plate, a thin line with a
/// walking figure for walks and a dot for waiting. Widths follow the minutes, with a floor so a plate always fits.
struct JourneyBar: View {
    var segments: [JourneyBarSegment]
    /// The plates of the ride legs, in order (family colour and text colour of the Wegzeichen); a ride without one falls
    /// back to the mode colour.
    var badges: [LineBadge] = []
    var height: CGFloat = 24

    private static let walkWidth: CGFloat = 34
    private static let waitWidth: CGFloat = 12
    private static let rideFloor: CGFloat = 52
    private static let gap: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let widths = Self.widths(for: segments, total: proxy.size.width)
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    segmentView(segment, index: index)
                        .frame(width: widths.indices.contains(index) ? widths[index] : 0, height: height)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segmentView(_ segment: JourneyBarSegment, index: Int) -> some View {
        switch segment.kind {
        case .ride:
            let mode = segment.mode ?? .train
            let badge = rideBadge(at: index)
            let fill = badge.map { $0.kind.fill(for: $0.text) } ?? Theme.modeColor(mode)
            let ink = badge?.kind.textColor ?? Color.white
            HStack(spacing: 4) {
                Image(systemName: mode.symbolName).font(.system(size: 11, weight: .bold))
                Text(badge?.text.nilIfEmptyPlate ?? segment.plate ?? "")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(fill, in: .capsule)
            .overlay { if let ring = badge?.kind.ring { Capsule().strokeBorder(ring, lineWidth: 1) } }
        case .walk:
            ZStack {
                Capsule().fill(Theme.textTertiary.opacity(0.55)).frame(height: 1.5)
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 3)
                    .background(Theme.sheetBackground.opacity(0.0))
            }
        case .wait:
            Circle().fill(Theme.textTertiary).frame(width: 4, height: 4)
        }
    }

    /// The plate of the n-th ride of the bar.
    private func rideBadge(at index: Int) -> LineBadge? {
        let rideNumber = segments.prefix(index).filter { $0.kind == .ride }.count
        return badges.indices.contains(rideNumber) ? badges[rideNumber] : nil
    }

    /// Pixel widths: walks and waits are fixed, rides share the rest by minutes (never below the floor).
    static func widths(for segments: [JourneyBarSegment], total: CGFloat) -> [CGFloat] {
        guard !segments.isEmpty else { return [] }
        let gaps = gap * CGFloat(segments.count - 1)
        var fixed: CGFloat = 0
        var rideMinutes = 0
        var rideCount = 0
        for s in segments {
            switch s.kind {
            case .walk: fixed += walkWidth
            case .wait: fixed += waitWidth
            case .ride: rideMinutes += max(1, s.minutes); rideCount += 1
            }
        }
        let available = max(0, total - gaps - fixed)
        var result: [CGFloat] = []
        var rideWidths: [CGFloat] = []
        for s in segments where s.kind == .ride {
            rideWidths.append(available * CGFloat(max(1, s.minutes)) / CGFloat(max(1, rideMinutes)))
        }
        // Raise short rides to the floor and take the difference from the long ones.
        let floors = rideWidths.map { max($0, min(rideFloor, available / CGFloat(max(1, rideCount)))) }
        let surplus = floors.reduce(0, +) - available
        if surplus > 0 {
            let shrinkable = zip(rideWidths, floors).filter { $0.0 > rideFloor }.map { $0.1 }.reduce(0, +)
            rideWidths = floors.map { w in
                w > rideFloor && shrinkable > 0 ? max(rideFloor, w - surplus * (w / shrinkable)) : w
            }
        } else {
            rideWidths = floors
        }
        var rideIndex = 0
        for s in segments {
            switch s.kind {
            case .walk: result.append(walkWidth)
            case .wait: result.append(waitWidth)
            case .ride:
                result.append(rideWidths[rideIndex])
                rideIndex += 1
            }
        }
        return result
    }
}

private extension String {
    /// A glyph-only plate has no text: the bar then falls back to the segment's plate text.
    var nilIfEmptyPlate: String? { isEmpty ? nil : self }
}
