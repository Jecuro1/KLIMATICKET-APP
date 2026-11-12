import SwiftUI
import KlimaCore

// The scrubber of the Zeitreise (docs/RADAR_TIMETRAVEL.md §5): a track from half an hour back to three hours ahead, ticks at every hour, a
// thumb that snaps to five-minute steps. VoiceOver adjusts it step by step and speaks the time. While the time-lapse plays the thumb follows
// it continuously.

struct RadarTimeScrubber: View {
    var travel: RadarTimeModel
    @State private var isDragging = false

    private let thumb: CGFloat = 30
    private let trackHeight: CGFloat = 8

    /// Where "Jetzt" sits on the track (0 ... 1): a seventh from the left.
    private var nowFraction: Double { RadarTimeAxis.fraction(of: 0) }

    var body: some View {
        let fraction = RadarTimeAxis.fraction(of: travel.offset)
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - thumb, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceSecondary)
                        .frame(height: trackHeight)
                        .padding(.horizontal, thumb / 2)
                    fill(width: width, fraction: fraction)
                    ticks(width: width)
                    thumbView
                        .offset(x: width * fraction)
                        .motionAnimation(Motion.snappy, value: isDragging)
                }
                .frame(height: proxy.size.height)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let place = min(max((value.location.x - thumb / 2) / width, 0), 1)
                            travel.scrub(to: RadarTimeAxis.offset(atFraction: place))
                        }
                        .onEnded { _ in
                            isDragging = false
                            travel.scrubEnded()
                        }
                )
            }
            .frame(height: 40)
            labels
        }
        .haptic(.selection, trigger: hapticStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeitreise")
        .accessibilityValue(travel.spokenValue)
        .accessibilityHint("Wische nach oben oder unten, um die Zeit in Fünf-Minuten-Schritten zu ändern.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: travel.nudge(steps: 1)
            case .decrement: travel.nudge(steps: -1)
            @unknown default: break
            }
        }
    }

    /// The step the thumb is on, except while the time-lapse plays (one tick a second would be a buzz, not a hint).
    private var hapticStep: Int? { travel.isPlaying ? nil : travel.step }

    // MARK: Parts

    /// From "Jetzt" to the thumb: the future in the accent, the past dimmer.
    private func fill(width: CGFloat, fraction: Double) -> some View {
        let from = min(nowFraction, fraction), to = max(nowFraction, fraction)
        return Capsule()
            .fill(fraction >= nowFraction ? AnyShapeStyle(Theme.routeGradient) : AnyShapeStyle(Theme.textTertiary))
            .frame(width: max(width * (to - from), 0), height: trackHeight)
            .offset(x: thumb / 2 + width * from)
    }

    /// A tick every 15 minutes, taller at the full hours and at "Jetzt".
    private func ticks(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(stride(from: Int(RadarTimeAxis.minOffset), through: Int(RadarTimeAxis.maxOffset), by: 900)), id: \.self) { seconds in
                let strong = seconds % 3600 == 0
                Capsule()
                    .fill(strong || seconds == 0 ? Theme.textSecondary : Theme.textTertiary)
                    .frame(width: 2, height: strong || seconds == 0 ? 16 : 9)
                    .offset(x: thumb / 2 - 1 + width * RadarTimeAxis.fraction(of: TimeInterval(seconds)))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thumbView: some View {
        Circle()
            .fill(Theme.snow)
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 3))
            .overlay(Circle().fill(Theme.accent).frame(width: 8, height: 8))
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(isDragging ? 0.30 : 0.2), radius: isDragging ? 7 : 4, y: 2)
            .scaleEffect(isDragging ? 1.14 : 1)
    }

    /// "-30", "Jetzt", "+1 Std" ...: where the ticks are.
    private var labels: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - thumb, 1)
            ZStack(alignment: .topLeading) {
                label("−30", at: -1800, width: width)
                label("Jetzt", at: 0, width: width)
                label("+1", at: 3600, width: width)
                label("+2", at: 7200, width: width)
                label("+3 Std", at: 10_800, width: width)
            }
        }
        .frame(height: 18)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // tick labels are decoration: VoiceOver speaks the value, the big time says it
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func label(_ text: String, at seconds: TimeInterval, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.weight(seconds == 0 ? .bold : .regular))
            .foregroundStyle(seconds == 0 ? Theme.textPrimary : Theme.textSecondary)
            .fixedSize()
            .position(x: thumb / 2 + width * RadarTimeAxis.fraction(of: seconds), y: 8)
    }
}
