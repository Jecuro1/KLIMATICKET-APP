import SwiftUI
import KlimaCore

// MARK: radarcockpit – the HUD of the Cockpit-Ansicht (docs/RADAR_COCKPIT.md §5): the next stop big with its platform, when the train gets there with the
// delay as a chip, the distance, the progress along the whole run with the stops as ticks and the train on it, the speed estimate, how old the
// position is. VoiceOver reads all of it as one element that updates politely. At the accessibility text sizes it keeps the essentials.

struct CockpitHUDCard: View {
    var model: CockpitModel
    var onAlarm: () -> Void
    var onFollow: () -> Void
    var isFollowing: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var stopSize: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var etaSize: CGFloat = 36
    @State private var showsInfo = false

    var body: some View {
        let hud = model.hud
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let summary = hud.summary {
                content(summary, hud: hud)
            } else {
                Text(CockpitText.waitingTitle)
                    .font(.system(size: stopSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(CockpitText.waitingDetail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !typeSize.isAccessibilitySize { actions(hud: hud) } else { compactActions(hud: hud) }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedCard(cornerRadius: Theme.Radius.card)
        .popover(isPresented: $showsInfo) { info(hud: hud).presentationCompactAdaptation(.popover) }
    }

    // MARK: Content

    @ViewBuilder private func content(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            stopBlock(summary, hud: hud)
            if !typeSize.isAccessibilitySize {
                if !hud.isProvisional { progress(summary) }
                footer(summary, hud: hud)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CockpitText.spoken(summary, now: hud.clock))
        .accessibilityAddTraits(.updatesFrequently)
        .haptic(.snap, trigger: summary.nextStop)
    }

    /// The next stop, the arrival and the delay.
    private func stopBlock(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(CockpitText.stopLabel(summary))
                    .font(Theme.Typography.kicker)
                    .tracking(1.06)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if let platform = summary.platform { platformChip(platform) }
            }
            Text(summary.nextStop ?? CockpitText.phaseLine(summary))
                .font(.system(size: stopSize, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if summary.nextStop != nil { arrivalRow(summary, hud: hud) }
            Text(CockpitText.phaseLine(summary))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
    }

    private func arrivalRow(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs))
        return layout {
            if let eta = summary.eta {
                Text(CockpitText.clock(eta))
                    .font(.system(size: etaSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .motionAnimation(Motion.number, value: CockpitText.clock(eta))
            }
            CockpitDelayChip(text: CockpitText.delayChip(seconds: summary.delaySeconds, state: summary.delayState), state: summary.delayState)
            if summary.showsCountdown(now: hud.clock), let seconds = summary.secondsToArrival(now: hud.clock),
               let countdown = CockpitText.countdown(seconds: seconds) {
                Text(countdown)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .motionAnimation(Motion.number, value: countdown)
            }
        }
    }

    private func platformChip(_ platform: PlatformLabel) -> some View {
        Text(platform.text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.surfaceSecondary, in: .capsule)
            .overlay(Capsule().strokeBorder(platform.changed ? Theme.summit : Color.clear, lineWidth: 1.5))
            .accessibilityHidden(true)
    }

    // MARK: Progress

    private func progress(_ summary: CockpitSummary) -> some View {
        CockpitProgressBar(progress: summary.progress, ticks: summary.stopTicks, tint: summary.delayState.tint)
            .accessibilityHidden(true)
    }

    /// Distance, speed, the age of the position and the way to the note about where the position comes from.
    private func footer(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { footerItems(summary, hud: hud) }
            VStack(alignment: .leading, spacing: 2) { footerItems(summary, hud: hud) }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder private func footerItems(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        if let km = summary.distanceKm {
            Text("noch \(CockpitText.distance(km: km))")
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .motionAnimation(Motion.number, value: CockpitText.distance(km: km))
        }
        if let speed = CockpitText.speed(summary.speed) {
            dot
            Text(speed)
                .monospacedDigit()
                .contentTransition(.numericText())
                .motionAnimation(Motion.number, value: speed)
        }
        Spacer(minLength: 4)
        if let age = summary.fixAge {
            Text(CockpitText.age(age))
                .monospacedDigit()
        }
        Button { showsInfo = true } label: {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Woher die Position kommt")
    }

    private var dot: some View {
        Text("·").foregroundStyle(Theme.textTertiary)
    }

    private func info(hud: CockpitHUD) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Woher die Zahlen kommen")
                .font(.headline)
            Text(CockpitText.positionNote)
            Text("Die Geschwindigkeit ist der Weg zwischen zwei Positionen geteilt durch die Zeit dazwischen, über etwa eine Minute geglättet, kein Tacho. Steht der Zug, zeigt das Cockpit keine.")
            if hud.isStraightLine { Text("\(CockpitText.straightLineNote): Zu dieser Fahrt hat die Auskunft keine Strecke geliefert.") }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.textPrimary)
        .padding(Theme.Spacing.m)
        .frame(maxWidth: 340, alignment: .leading)
    }

    // MARK: Actions

    /// The quick actions: the exit alarm, "Live verfolgen", sharing.
    private func actions(hud: CockpitHUD) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            CockpitActionButton(title: "Aussteige-Wecker", symbol: "bell.badge", action: onAlarm)
            CockpitActionButton(title: isFollowing ? "Wird verfolgt" : "Live verfolgen", symbol: isFollowing ? "location.fill" : "location",
                                isOn: isFollowing, action: onFollow)
                .disabled(isFollowing)
            if let summary = hud.summary {
                ShareLink(item: CockpitText.share(summary)) {
                    CockpitActionLabel(title: "Teilen", symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            }
        }
    }

    /// At the largest text sizes the three actions are one menu: the card keeps its room for the stop and its time.
    private func compactActions(hud: CockpitHUD) -> some View {
        Menu {
            Button(action: onAlarm) { Label("Aussteige-Wecker", systemImage: "bell.badge") }
            Button(action: onFollow) { Label(isFollowing ? "Wird verfolgt" : "Live verfolgen", systemImage: "location") }
                .disabled(isFollowing)
            if let summary = hud.summary {
                ShareLink(item: CockpitText.share(summary)) { Label("Teilen", systemImage: "square.and.arrow.up") }
            }
        } label: {
            Label("Aktionen", systemImage: "ellipsis.circle")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Pieces

/// The delay as a chip: green on time, orange five minutes or more late, red cancelled, grey without realtime. The text is the colour's text-safe
/// variant, the shape and the words carry the meaning as well.
struct CockpitDelayChip: View {
    var text: String
    var state: RadarDelayState

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(state.tint.opacity(0.18), in: .capsule)
            .overlay(Capsule().strokeBorder(state.tint.opacity(0.55), lineWidth: 1))
            .fixedSize()
    }

    private var textColor: Color {
        switch state {
        case .onTime: Theme.positiveText
        case .late: Theme.summitText
        case .cancelled: Theme.negativeText
        case .unknown: Theme.textSecondary
        }
    }
}

struct CockpitActionLabel: View {
    var title: String
    var symbol: String
    var isOn = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolReplaceTransition()
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isOn ? Theme.accentText : Theme.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(.rect(cornerRadius: 18))
    }
}

struct CockpitActionButton: View {
    var title: String
    var symbol: String
    var isOn = false
    var action: () -> Void

    var body: some View {
        Button(action: action) { CockpitActionLabel(title: title, symbol: symbol, isOn: isOn) }
            .buttonStyle(.pressable(scale: 0.96))
            .glassEffect(isOn ? .regular.tint(Theme.accent.opacity(0.2)) : .regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

/// The whole run as a bar: filled to the train, a tick for every stop the train calls at, the train as a glowing dot. Decoration for the eyes: the HUD's
/// spoken summary says the same in words.
struct CockpitProgressBar: View {
    var progress: Double
    var ticks: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = min(max(progress, 0), 1) * width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSecondary).frame(height: 6)
                Capsule().fill(Theme.routeGradient).frame(width: max(x, 6), height: 6)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    let passed = tick <= progress + 0.0005
                    Circle()
                        .fill(passed ? Color.white : Theme.textTertiary.opacity(0.9))
                        .overlay(Circle().strokeBorder(passed ? Theme.accent : Color.clear, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                        .position(x: min(max(tick, 0), 1) * width, y: proxy.size.height / 2)
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3.5))
                    .frame(width: 18, height: 18)
                    .shadow(color: tint.opacity(0.8), radius: 6)
                    .position(x: min(max(x, 9), width - 9), y: proxy.size.height / 2)
            }
            .motionAnimation(Motion.smooth, value: progress)
        }
        .frame(height: 20)
    }
}
