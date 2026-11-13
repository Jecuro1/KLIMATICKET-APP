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
        // A popover; at the accessibility sizes the note is taller than the screen: a sheet that scrolls.
        .popover(isPresented: $showsInfo) {
            Group {
                if typeSize.isAccessibilitySize { ScrollView { info(hud: hud) } } else { info(hud: hud) }
            }
            .presentationCompactAdaptation(typeSize.isAccessibilitySize ? .sheet : .popover)
        }
    }

    // MARK: Content

    @ViewBuilder private func content(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            stopBlock(summary, hud: hud)
            if !typeSize.isAccessibilitySize {
                if !hud.isProvisional { progress(summary, hud: hud) }
                footer(summary, hud: hud)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CockpitText.spoken(summary, now: hud.clock))
        .accessibilityAddTraits(.updatesFrequently)
        // The info button sits inside this one element (and is not drawn at the accessibility sizes): VoiceOver reaches the note as an action.
        .accessibilityAction(named: Text(Self.infoTitle)) { showsInfo = true }
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
            Text(CockpitText.headline(summary))
                .font(.system(size: stopSize, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if summary.nextStop != nil { arrivalRow(summary, hud: hud) }
            // What the train does, under the stop it heads for. At the accessibility sizes a plain "Unterwegs" gives its room to the map.
            if let subline = CockpitText.subline(summary), !(typeSize.isAccessibilitySize && summary.phase == .underway) {
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
            }
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
            // The countdown; "laut Fahrplan" when the time is the plan and the chip the delay of an earlier stop (`CockpitText.arrivalNote`).
            if let countdown = CockpitText.arrivalNote(summary, now: hud.clock) {
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

    /// A train without a position for two minutes is grey on the bar as on the map: the dot marks where it was last seen, not a live place.
    private func progress(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        CockpitProgressBar(progress: summary.progress, ticks: summary.stopTicks,
                           tint: hud.isStale ? RadarDelayState.unknown.tint : summary.delayState.tint, glows: !hud.isStale)
            .accessibilityHidden(true)
    }

    /// Distance, speed, the age of the position and the way to the note about where the position comes from: one row when it fits, else the
    /// distance and the speed over the age, else each on its own line. Never a lone separator dot. Without a distance and a speed (at the
    /// destination) the age stands alone on the leading edge, where it stands in every other state.
    private func footer(_ summary: CockpitSummary, hud: CockpitHUD) -> some View {
        Group {
            if summary.distanceKm == nil, CockpitText.speed(summary.speed) == nil {
                HStack(spacing: 0) {
                    ageAndInfo(summary)
                    Spacer(minLength: 0)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) {
                        distanceAndSpeed(summary)
                        Spacer(minLength: 4)
                        ageAndInfo(summary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Theme.Spacing.xs) { distanceAndSpeed(summary) }
                        ageAndInfo(summary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        distanceText(summary)
                        speedText(summary)
                        ageAndInfo(summary)
                    }
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder private func distanceAndSpeed(_ summary: CockpitSummary) -> some View {
        distanceText(summary)
        if summary.distanceKm != nil, CockpitText.speed(summary.speed) != nil { dot }
        speedText(summary)
    }

    @ViewBuilder private func distanceText(_ summary: CockpitSummary) -> some View {
        if let km = summary.distanceKm {
            Text("noch \(CockpitText.distance(km: km))")
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText(countsDown: true))
                .motionAnimation(Motion.number, value: CockpitText.distance(km: km))
        }
    }

    /// "ca. 118 km/h · geschätzt", only while the train moves and two answers allow an estimate.
    @ViewBuilder private func speedText(_ summary: CockpitSummary) -> some View {
        if let speed = CockpitText.speed(summary.speed) {
            Text(speed)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
                .motionAnimation(Motion.number, value: speed)
        }
    }

    private func ageAndInfo(_ summary: CockpitSummary) -> some View {
        HStack(spacing: 2) {
            if let age = summary.fixAge {
                Text(CockpitText.age(age))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Button { showsInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.infoTitle)
        }
    }

    static let infoTitle = "Woher die Zahlen kommen"

    private var dot: some View {
        Text("·").foregroundStyle(Theme.textTertiary)
    }

    private func info(hud: CockpitHUD) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(Self.infoTitle)
                .font(.headline)
            Text(CockpitText.positionNote)
            Text(CockpitText.markerNote)
            Text("Die Geschwindigkeit ist der Weg zwischen zwei Positionen geteilt durch die Zeit dazwischen, über etwa eine Minute geglättet, kein Tacho. Steht der Zug, zeigt das Cockpit keine.")
            if hud.isStraightLine { Text("\(CockpitText.straightLineNote): Zu dieser Fahrt hat die Auskunft keine Strecke geliefert.") }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.textPrimary)
        .padding(Theme.Spacing.m)
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 340, alignment: .leading)
    }

    // MARK: Actions

    /// The exit alarm and "Live verfolgen" only make sense for a train that is still on its way: not once it has arrived, the run has ended
    /// or the run is cancelled. Sharing stays ("RJX 66 hat Salzburg Hbf erreicht.").
    private func offersTrainActions(_ hud: CockpitHUD) -> Bool {
        guard hud.state != .ended, !hud.isCancelled else { return false }
        guard let summary = hud.summary else { return true }
        switch summary.phase {
        case .arrived, .cancelled: return false
        default: return true
        }
    }

    /// The quick actions: the exit alarm, "Live verfolgen", sharing.
    private func actions(hud: CockpitHUD) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if offersTrainActions(hud) {
                CockpitActionButton(title: "Aussteige-Wecker", symbol: "bell.badge", action: onAlarm)
                CockpitActionButton(title: isFollowing ? "Wird verfolgt" : "Live verfolgen", symbol: isFollowing ? "location.fill" : "location",
                                    isOn: isFollowing, action: onFollow)
                    .disabled(isFollowing)
            }
            if let summary = hud.summary {
                ShareLink(item: CockpitText.share(summary)) {
                    CockpitActionLabel(title: "Teilen", symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            }
        }
    }

    /// At the largest text sizes the three actions are one menu: the card keeps its room for the stop and its time. The note about where the
    /// numbers come from is in it too: the row with its info button is not drawn at these sizes.
    private func compactActions(hud: CockpitHUD) -> some View {
        Menu {
            if offersTrainActions(hud) {
                Button(action: onAlarm) { Label("Aussteige-Wecker", systemImage: "bell.badge") }
                Button(action: onFollow) { Label(isFollowing ? "Wird verfolgt" : "Live verfolgen", systemImage: "location") }
                    .disabled(isFollowing)
            }
            if let summary = hud.summary {
                ShareLink(item: CockpitText.share(summary)) { Label("Teilen", systemImage: "square.and.arrow.up") }
            }
            Button { showsInfo = true } label: { Label(Self.infoTitle, systemImage: "info.circle") }
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
        // The delay is one of the essentials the panel keeps at AX5: it grows with the text like the arrival next to it (15 pt at the
        // standard size, as before), up to AX2, where it is twice the size it had at AX5 and the map above keeps its room.
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(state.tint.opacity(0.18), in: .capsule)
            .overlay(Capsule().strokeBorder(state.tint.opacity(0.55), lineWidth: 1))
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
        // The symbols differ in height (the share box is taller than the bell): one frame for all keeps the three titles on one line. The
        // title keeps a small margin to the button's edge; it first tightens its letters, then shrinks, before it touches the edge
        // ("Aussteige-Wecker" fills its third of the card on a 402-point phone), so the three titles stay close to one size.
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolReplaceTransition()
                .frame(height: 22)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
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
/// spoken summary says the same in words. Ticks and dot share one scale, inset by the dot's radius: at the last stop the dot covers the last tick
/// instead of stopping short of it.
struct CockpitProgressBar: View {
    var progress: Double
    var ticks: [Double]
    var tint: Color
    var glows = true

    private static let dot: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let inset = Self.dot / 2
            let usable = max(proxy.size.width - Self.dot, 1)
            let x = inset + min(max(progress, 0), 1) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSecondary).frame(height: 6)
                Capsule().fill(Theme.routeGradient).frame(width: max(x, 6), height: 6)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    let passed = tick <= progress + 0.0005
                    Circle()
                        .fill(passed ? Color.white : Theme.textTertiary.opacity(0.9))
                        .overlay(Circle().strokeBorder(passed ? Theme.accent : Color.clear, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                        .position(x: inset + min(max(tick, 0), 1) * usable, y: proxy.size.height / 2)
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3.5))
                    .frame(width: Self.dot, height: Self.dot)
                    .shadow(color: tint.opacity(glows ? 0.8 : 0), radius: 6)
                    .position(x: x, y: proxy.size.height / 2)
            }
            .motionAnimation(Motion.smooth, value: progress)
        }
        .frame(height: 20)
    }
}
