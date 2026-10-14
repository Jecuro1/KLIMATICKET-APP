import SwiftUI
import KlimaCore

// MARK: follow – "Live verfolgen" Live Activity: Lock Screen, Dynamic Island (compact, minimal, expanded). Compiled into the
// app (previews, screenshots) and the widget extension (Widgets/Sources/FollowLiveActivity.swift). Every value that reaches
// the screen has an accessibility label; the Dynamic Island keeps the line and the delay visible at every size.

/// The German one-liners of each stage. Shared by the Live Activity, the planner's follow card and the notifications.
enum FollowStageCopy {
    static func headline(_ state: FollowLiveState) -> String {
        switch state.stage {
        case .beforeDeparture:
            "Abfahrt \(time(state.nextStopTime))" + suffix(platform: state.platform)
        case .boarding:
            "Jetzt einsteigen" + suffix(platform: state.platform)
        case .riding:
            if let next = state.nextStopName {
                "Nächster Halt \(next)" + (state.nextStopTime.map { " \(time($0))" } ?? "")
            } else {
                "Unterwegs"
            }
        case .transfer:
            "Umstieg in \(state.transferStation ?? "")" + (state.transferDeparture.map { " · \(time($0))" } ?? "")
        case .arrived:
            "Angekommen"
        case .cancelled:
            "Fällt aus"
        }
    }

    /// "+6 Min", "pünktlich", "2 Min früher". Nil when HAFAS reports no delay.
    static func delay(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        if minutes > 0 { return "+\(minutes) Min" }
        if minutes == 0 { return "pünktlich" }
        return "\(-minutes) Min früher"
    }

    /// Spoken delay for accessibility: "6 Minuten später", "pünktlich".
    static func spokenDelay(_ minutes: Int?) -> String {
        guard let minutes else { return "Verspätung unbekannt" }
        if minutes > 0 { return "\(minutes) Minuten später" }
        if minutes == 0 { return "pünktlich" }
        return "\(-minutes) Minuten früher"
    }

    static func platform(_ platform: String?) -> String? {
        platform.map { "Gleis \($0)" }
    }

    static func time(_ date: Date?) -> String {
        date.map { RealtimePresentation.time($0) } ?? "–"
    }

    private static func suffix(platform: String?) -> String {
        platform.map { " · Gleis \($0)" } ?? ""
    }
}

/// The delay as a capsule: green when on time, orange from five minutes on.
struct FollowDelayChip: View {
    let minutes: Int?
    var compact = false

    var body: some View {
        if let text = FollowStageCopy.delay(minutes) {
            let late = (minutes ?? 0) >= 5
            Text(text)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(late ? Theme.summitText : Theme.positiveText)
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, compact ? 2 : 3)
                .background((late ? Theme.summit : Theme.positive).opacity(0.16), in: .capsule)
                .accessibilityLabel(FollowStageCopy.spokenDelay(minutes))
        }
    }
}

/// Progress across the stops between boarding and alighting, as a capsule bar.
struct FollowProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textPrimary.opacity(0.12))
                Capsule()
                    .fill(Theme.routeGradient)
                    .frame(width: max(6, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) Prozent")
    }
}

/// Lock Screen and banner layout of a followed ride.
struct FollowLockScreenView: View {
    let attributes: FollowActivityAttributes
    let state: FollowLiveState
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(attributes.lineName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if state.stage != .arrived && state.stage != .cancelled {
                    FollowDelayChip(minutes: state.delayMinutes)
                }
            }
            Text(attributes.routeTitle)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(FollowStageCopy.headline(state))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
            FollowProgressBar(progress: state.progress)
            HStack(alignment: .firstTextBaseline) {
                if let platform = FollowStageCopy.platform(state.platform) {
                    Text(platform).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if isStale {
                    Text("Keine aktuellen Daten").font(.caption).foregroundStyle(Theme.textTertiary)
                } else if let updated = state.updatedAt {
                    Text("Stand \(RealtimePresentation.time(updated))").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lockScreenLabel)
    }

    private var lockScreenLabel: String {
        var parts = ["\(attributes.lineName), \(attributes.routeTitle)", FollowStageCopy.headline(state)]
        if state.stage != .arrived, state.stage != .cancelled { parts.append(FollowStageCopy.spokenDelay(state.delayMinutes)) }
        if let platform = FollowStageCopy.platform(state.platform) { parts.append(platform) }
        parts.append("Fortschritt \(Int((state.progress * 100).rounded())) Prozent")
        if isStale { parts.append("keine aktuellen Daten") }
        return parts.joined(separator: ", ")
    }
}

/// Dynamic Island, compact leading: the line.
struct FollowIslandCompactLeading: View {
    let attributes: FollowActivityAttributes

    var body: some View {
        Text(attributes.lineName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.glacier)
            .lineLimit(1)
            .accessibilityLabel("Linie \(attributes.lineName)")
    }
}

/// Dynamic Island, compact trailing: the delay, or the next stop's time.
struct FollowIslandCompactTrailing: View {
    let state: FollowLiveState

    var body: some View {
        if state.stage == .arrived || state.stage == .cancelled {
            Image(systemName: state.stage == .cancelled ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(state.stage == .cancelled ? Theme.negative : Theme.positive)
                .accessibilityLabel(FollowStageCopy.headline(state))
        } else {
            FollowDelayChip(minutes: state.delayMinutes, compact: true)
        }
    }
}

/// Dynamic Island, minimal: a single train symbol that reports the delay with its colour.
struct FollowIslandMinimal: View {
    let state: FollowLiveState

    var body: some View {
        let late = (state.delayMinutes ?? 0) >= 5
        Image(systemName: "train.side.front.car")
            .font(.caption.weight(.bold))
            .foregroundStyle(late ? Theme.summit : Theme.glacier)
            .accessibilityLabel(FollowStageCopy.spokenDelay(state.delayMinutes))
    }
}

/// Dynamic Island, expanded: centre shows the stage, the bottom the progress and the platform.
struct FollowIslandExpandedCenter: View {
    let attributes: FollowActivityAttributes
    let state: FollowLiveState

    var body: some View {
        VStack(spacing: 2) {
            Text(attributes.routeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(FollowStageCopy.headline(state))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FollowIslandExpandedBottom: View {
    let state: FollowLiveState

    var body: some View {
        VStack(spacing: 6) {
            FollowProgressBar(progress: state.progress)
            HStack {
                if let platform = FollowStageCopy.platform(state.platform) {
                    Text(platform).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                Text(FollowStageCopy.delay(state.delayMinutes) ?? "")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
