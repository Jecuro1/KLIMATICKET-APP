import SwiftUI
import KlimaCore

// The Zeitreise's controls on the radar (docs/RADAR_TIMETRAVEL.md §5): a clock chip at the bottom that expands into a glass card with a big
// time, the scrubber, "Zurück zu Jetzt", a time-lapse button with speed, and what is true about the picture (calculated from the timetable and
// the delays known now, how old they are, what was loaded). The banner at the top says it again while away from now.

struct RadarTimePanel: View {
    var travel: RadarTimeModel

    var body: some View {
        GlassMorphGroup(spacing: Theme.Spacing.s) { ns in
            if travel.isOpen {
                RadarTimeCard(travel: travel)
                    .morphingGlass(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous), id: "time", namespace: ns)
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    RadarTimeChip(travel: travel)
                        .morphingGlass(travel.isAway ? .regular.tint(Theme.dusk.opacity(0.28)).interactive() : .regular.interactive(),
                                       in: .capsule, id: "time", namespace: ns)
                    if travel.isAway {
                        Button { travel.backToNow() } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .morphingGlass(in: .circle, id: "back", namespace: ns)
                        .accessibilityLabel("Zurück zu Jetzt")
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .motionAnimation(Motion.smooth, value: travel.isOpen)
        .motionAnimation(Motion.smooth, value: travel.isAway)
    }
}

/// The closed state: "Jetzt", or the time the map shows.
struct RadarTimeChip: View {
    var travel: RadarTimeModel

    var body: some View {
        Button {
            withMotion(Motion.smooth) { travel.toggleOpen() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(travel.isAway ? Theme.dusk : Theme.accentText)
                if travel.isAway {
                    Text(travel.clockText).font(.subheadline.weight(.bold)).monospacedDigit()
                    Text(travel.offsetTitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Jetzt").font(.subheadline.weight(.semibold))
                }
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(travel.isAway ? "Zeitreise, \(travel.spokenValue)" : "Zeitreise, jetzt")
        .accessibilityHint("Öffnet den Zeitregler")
    }
}

/// The open state.
struct RadarTimeCard: View {
    var travel: RadarTimeModel
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            header
            RadarTimeScrubber(travel: travel)
            controls
            if travel.isMetered, travel.profile == .coarse, travel.isAway { meteredNotice }
            if travel.isAway { status }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    /// The time, how far from now, and the close button on one line: the card takes as little of the map as it can.
    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs))
        return layout {
            if typeSize.isAccessibilitySize { closeButton.frame(maxWidth: .infinity, alignment: .trailing) }
            Text(travel.clockText)
                .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .motionAnimation(Motion.number, value: travel.clockText)
            VStack(alignment: .leading, spacing: 0) {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let note = travel.dayNote {
                    Text(note).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                closeButton
            }
        }
    }

    private var closeButton: some View {
        Button {
            withMotion(Motion.smooth) { travel.close() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Theme.surfaceSecondary, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zeitregler schließen")
    }

    private var subtitle: String {
        guard travel.isAway else { return "Zieh den Regler" }
        return travel.isPlaying ? "\(travel.offsetTitle) · läuft" : travel.offsetTitle
    }

    // MARK: Controls

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                backButton
                Spacer(minLength: 0)
                speedPicker
                playButton
            }
            VStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    speedPicker
                    Spacer(minLength: 0)
                    playButton
                }
                backButton
            }
        }
    }

    private var backButton: some View {
        Button { travel.backToNow() } label: {
            Label("Zurück zu Jetzt", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.surfaceSecondary, in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .opacity(travel.isAway ? 1 : 0.4)
        .disabled(!travel.isAway)
    }

    private var speedPicker: some View {
        HStack(spacing: 2) {
            ForEach(RadarPlaybackSpeed.allCases, id: \.self) { speed in
                Button {
                    withMotion(Motion.snappy) { travel.speed = speed }
                } label: {
                    Text(speed.title)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .frame(minWidth: 36, minHeight: 40)
                        .background(travel.speed == speed ? Theme.accent.opacity(0.18) : .clear, in: .capsule)
                        .foregroundStyle(travel.speed == speed ? Theme.accentText : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speed == .x1 ? "Einfache Geschwindigkeit" : "Doppelte Geschwindigkeit")
                .accessibilityAddTraits(travel.speed == speed ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.surfaceSecondary, in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // two short labels: they grow with the text, but not past a pair of fingers
        .haptic(.selection, trigger: travel.speed)
    }

    private var playButton: some View {
        Button { travel.togglePlay() } label: {
            Image(systemName: travel.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3.weight(.bold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // the icon stays inside its circle
                .foregroundStyle(Theme.onAccent)
                .symbolReplaceTransition()
                .frame(width: 50, height: 50)
                .background(Theme.ctaGradient, in: .circle)
                .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.pressable(scale: 0.92))
        .haptic(travel.isPlaying ? .start : .stop, trigger: travel.isPlaying)
        .accessibilityLabel(travel.isPlaying ? "Zeitraffer anhalten" : "Zeitraffer abspielen")
        .accessibilityHint("Eine Sekunde sind fünf Minuten Fahrplan.")
    }

    // MARK: What is true

    private var meteredNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Mobilfunk: grobe Zeitreise, ein Zeitpunkt je Stunde.", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("So bleibt die Datenmenge klein. Für genau diese Minute lädst du mit \"Genau laden\".")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Spacing.xs) {
                smallButton("Fein laden", symbol: "square.stack.3d.up") { travel.useFine() }
                smallButton("Genau laden", symbol: "scope") { travel.refreshExactNow() }
            }
        }
        .padding(Theme.Spacing.s)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Theme.accent.opacity(0.16), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentText)
    }

    /// The picture's own numbers: how many, for when; how old the delays are and that nothing later is predicted; what is still loading; what the path
    /// is; what it cost.
    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 1) {
                    Text(travel.pill)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(RadarTimeText.statusCaption(age: travel.delayAge(at: context.date), offset: travel.offset))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusSpoken(at: context.date))
                .accessibilityAddTraits(.updatesFrequently)
            }
            if travel.isLoading {
                loadingRow
            } else if let failure = travel.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.summitText)
            } else if travel.isRefreshingExact {
                Label("Genau diese Minute wird geladen.", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if travel.hasSnapshotHere {
                Label("Für diese Minute hat die Auskunft die Positionen selbst berechnet.", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(Theme.positiveText)
            }
            DisclosureGroup("Wie das berechnet wird") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RadarTimeText.honesty(for: travel.offset))
                    if travel.hasStraightPins {
                        Text(RadarTimeText.straightLine)
                    }
                    Text("Zu jedem Zug kennt die App nur vier Halte: Start, den letzten, den nächsten und das Ziel. Dazwischen rechnet sie zwischen den geladenen Zeitpunkten. Je näher ein geladener Zeitpunkt, desto genauer.")
                    Text(travel.volumeNote)
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
            .font(.footnote.weight(.semibold))
            .tint(Theme.textSecondary)
        }
    }

    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(travel.loadingText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accentText)
            GeometryReader { proxy in
                let share = travel.progress.total > 0 ? Double(travel.progress.loaded) / Double(travel.progress.total) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceSecondary)
                    Capsule().fill(Theme.routeGradient).frame(width: max(proxy.size.width * share, 6))
                }
                .motionAnimation(Motion.smooth, value: travel.progress.loaded)
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(travel.loadingText)
    }

    private func statusSpoken(at date: Date) -> String {
        var text = travel.summary
        if let age = travel.delayAge(at: date) { text += ". " + RadarTimeText.spokenDelayAge(age) }
        return text
    }
}

// MARK: - Banner, tint, trail

/// "Zeitreise · Prognose aus dem Fahrplan": at the top of the map while the picture is not now.
struct RadarTimeBanner: View {
    var travel: RadarTimeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.footnote.weight(.bold))
                .symbolEffect(.pulse, isActive: travel.isPlaying)
                .symbolEffectsRemoved(reduceMotion || MotionPolicy.isStatic)
            Text(travel.banner)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // a banner, not a page: it grows with the text up to this size
        .glassEffect(.regular.tint(Theme.dusk.opacity(0.30)), in: .rect(cornerRadius: 18))
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(travel.banner)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The time of day on the map: a soft violet tint at night, a warm one at dusk and dawn. Decoration (`RadarDaylight`), never a statement.
struct RadarSkyTint: View {
    var travel: RadarTimeModel

    var body: some View {
        let sky = travel.sky
        ZStack {
            Rectangle().fill(Theme.dusk.opacity(0.30 * sky.night))
            LinearGradient(colors: [Theme.dawn.opacity(0.26 * sky.twilight), .clear], startPoint: .bottom, endPoint: .center)
        }
        .blendMode(.multiply)
        .opacity(travel.isAway ? 1 : 0)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .motionAnimation(Motion.gentle, value: travel.isAway)
        .motionAnimation(Motion.gentle, value: Int(sky.night * 20))
    }
}
