import SwiftUI
import WidgetKit
import KlimaCore

// MARK: smartwidgets – the small Live Activity family (`ActivityFamily.small`, docs/WIDGETS_SMARTSTACK.md §5). The paired
// Apple Watch shows it in its Smart Stack (watchOS 11 and later) without a watch app; the iPhone's Lock Screen and Dynamic
// Island keep their own layouts. Compiled into the extension (RideLiveActivity, FollowLiveActivity) and the app (the
// `liveActivitySmall` preview). ContentState and attributes are unchanged: the text comes from `ActivitySmallText`.

/// The Lock Screen content of "Unterwegs": the small family gets the watch layout, everything else the Lock Screen view.
struct RideActivityPresentation: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var isStale: Bool

    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            RideSmallActivityView(attributes: attributes, state: state, isStale: isStale)
        } else {
            RideLockScreenView(attributes: attributes, state: state, isStale: isStale)
        }
    }
}

/// The Lock Screen content of "Live verfolgen", with the same split.
struct FollowActivityPresentation: View {
    var attributes: FollowActivityAttributes
    var state: FollowLiveState
    var isStale: Bool

    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            FollowSmallActivityView(attributes: attributes, state: state, isStale: isStale)
        } else {
            FollowLockScreenView(attributes: attributes, state: state, isStale: isStale)
        }
    }
}

/// "Unterwegs" on the watch: "Zug 07:42", the destination and the time to the arrival (or since the start).
struct RideSmallActivityView: View {
    var attributes: RideActivityAttributes
    var state: RideActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        ActivitySmallLayout(
            line: ActivitySmallText.ride(modeName: attributes.mode.displayName, lineLabel: attributes.lineLabel,
                                         toName: attributes.toName, startedAt: attributes.startedAt,
                                         expectedArrival: state.expectedArrival, phase: state.phase, isStale: isStale,
                                         endedAt: state.endedAt),
            symbol: attributes.mode.symbolName,
            timerStart: attributes.startedAt,
            countUpRange: attributes.timerRange,
            tone: state.status?.tone == .delayed || state.status?.tone == .disrupted ? .late : .normal)
    }
}

/// "Live verfolgen" on the watch: "RJX 66 07:42 +3", the destination and the countdown to departure or arrival.
struct FollowSmallActivityView: View {
    var attributes: FollowActivityAttributes
    var state: FollowLiveState
    var isStale: Bool

    var body: some View {
        let line = ActivitySmallText.follow(lineName: attributes.lineName, alightName: attributes.alightName, stage: state.stage,
                                            plannedDeparture: attributes.plannedDeparture,
                                            plannedArrival: attributes.plannedArrival, nextStopTime: state.nextStopTime,
                                            delayMinutes: state.delayMinutes, transferStation: state.transferStation,
                                            transferDeparture: state.transferDeparture, updatedAt: state.updatedAt,
                                            isStale: isStale)
        ActivitySmallLayout(line: line, symbol: "train.side.front.car", timerStart: attributes.startedAt,
                            countUpRange: nil,
                            tone: state.stage == .cancelled ? .cancelled : ((state.delayMinutes ?? 0) >= 5 ? .late : .normal))
    }
}

/// Short lines for the watch: the headline with the delay, the destination, the running time with its label, and the
/// data age once it is old.
struct ActivitySmallLayout: View {
    enum Tone { case normal, late, cancelled }

    var line: ActivitySmallLine
    var symbol: String
    /// Lower end of the countdown range (the activity's start), so the range is never empty.
    var timerStart: Date
    /// The range a counting-up timer runs in (a ride without arrival); nil runs from the target for eight hours.
    var countUpRange: ClosedRange<Date>?
    var tone: Tone = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.glacier)
                headline
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(verbatim: "\(line.destinationPrefix) \(line.destination)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let target = line.countdownTarget {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: line.countdownLabel)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    timer(target)
                }
                .font(.system(size: 12.5, weight: .medium))
                .minimumScaleFactor(0.8)
            }
            if let footnote = line.footnote {
                Text(verbatim: footnote)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tone == .normal ? Theme.textSecondary : Theme.summitText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
    }

    /// The headline with its delay part tinted (never colour alone: the "+3" is part of the text).
    private var headline: Text {
        guard let delay = line.delay, line.headline.hasSuffix(" \(delay)") else {
            return Text(verbatim: line.headline)
                .foregroundStyle(tone == .cancelled ? Theme.negativeText : Theme.textPrimary)
        }
        let main = Text(verbatim: String(line.headline.dropLast(delay.count + 1)))
            .foregroundStyle(Theme.textPrimary)
        let badge = Text(verbatim: " \(delay)")
            .foregroundStyle(tone == .late ? Theme.summitText : Theme.textSecondary)
        return Text("\(main)\(badge)")
    }

    /// The running time: down to the target, or up from the start. The system updates it every second.
    private func timer(_ target: Date) -> some View {
        Group {
            if line.countsUp {
                Text(timerInterval: countUpRange ?? target...target.addingTimeInterval(8 * 3600), countsDown: false)
            } else {
                Text(timerInterval: min(timerStart, target)...target, countsDown: true)
            }
        }
        .fontWeight(.semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.accentText)
        .lineLimit(1)
    }
}
