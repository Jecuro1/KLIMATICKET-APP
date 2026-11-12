import SwiftUI
import KlimaCore

// Aussteige-Wecker: the card and its progress ring (docs/EXIT_ALARM.md §4). Pure views of an `ExitAlarmState` and a clock, so the
// live screen, the Settings test and the CI screenshots draw the same card. The numbers come from `ExitAlarmPresentation`
// (KlimaCore, tested); the card never makes one up: no fix on the run, no distance; a GPS or delayed time says "geschätzt".

/// The ring that fills toward the target stop, with the minutes left in the middle.
struct ExitAlarmRing: View {
    let progress: Double
    /// Seconds to the arrival; nil when unknown.
    let remainingSeconds: TimeInterval?
    var isApproaching = false
    var isFired = false
    var size: CGFloat = 96

    private var line: CGFloat { size * 0.095 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.textPrimary.opacity(0.10), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.015))
                .stroke(isFired ? AnyShapeStyle(Theme.summit) : AnyShapeStyle(Theme.routeGradient),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .motionAnimation(Motion.gentle, value: progress)
            // The end of the ride sits at twelve o'clock: the stop the ring fills toward.
            Image(systemName: "flag.checkered")
                .font(.system(size: size * 0.15, weight: .bold))
                .foregroundStyle(isApproaching || isFired ? Theme.summitText : Theme.textSecondary)
                .padding(size * 0.05)
                .background(Circle().fill(.thinMaterial))
                .offset(y: -size / 2)
                .accessibilityHidden(true)
            VStack(spacing: -1) {
                Text(value.text)
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .numericValue(value.number)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(value.unit)
                    .font(.system(size: size * 0.14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.06)
        .background {
            if isApproaching { Color.clear.frame(width: size, height: size).pulsingHalo(Theme.summit) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Noch \(value.spoken) bis zum Ausstieg")
        .accessibilityValue("\(Int((progress * 100).rounded())) Prozent der Fahrt")
    }

    private var value: (text: String, number: Double, unit: String, spoken: String) {
        guard let seconds = remainingSeconds else { return ("–", 0, "Min", "unbekannt") }
        if seconds < 60 { return ("<1", 0, "Min", "weniger als eine Minute") }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 100 {
            let hours = minutes / 60, rest = minutes % 60
            return (String(format: "%d:%02d", hours, rest), Double(minutes), "Std", "\(hours) Stunden \(rest) Minuten")
        }
        return ("\(minutes)", Double(minutes), "Min", "\(minutes) Minuten")
    }
}

/// One alarm as a card: ring, stop, when it wakes you, what is left, and the honest "geschätzt" tag.
struct ExitAlarmCard: View {
    let state: ExitAlarmState
    var now: Date = Date()
    var kind: ExitAlarmKind = .alarmKit
    var locationAuthorization: ExitAlarmLocationAuthorization = .always
    /// Shows "Ändern" and "Abbrechen".
    var showsActions = false
    var onEdit: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        let estimate = ExitAlarmPresentation.estimate(state, now: now)
        let approaching = state.phase == .approaching
        GlassCard(padding: Theme.Spacing.m, tint: approaching ? Theme.summit : nil) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    ExitAlarmRing(progress: estimate.progress, remainingSeconds: estimate.remainingSeconds,
                                  isApproaching: approaching, isFired: state.phase == .fired)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.badge.waveform.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(approaching ? Theme.summitText : Theme.accentText)
                            Kicker(text: "Aussteige-Wecker", color: approaching ? Theme.summitText : Theme.textSecondary)
                            Spacer(minLength: 4)
                            ExitAlarmPhasePill(phase: state.phase, isPassed: state.passedAt != nil)
                        }
                        Text(ExitAlarmPresentation.title(state))
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ExitAlarmPresentation.statusLine(state, now: now))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let line = ExitAlarmPresentation.remainingLine(estimate), state.phase != .ended {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(line)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(ExitAlarmPresentation.estimateTag(estimate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(estimate.isEstimate ? Theme.summitText : Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((estimate.isEstimate ? Theme.summit : Theme.textTertiary).opacity(0.14), in: .capsule)
                        Spacer(minLength: 0)
                    }
                }
                ExitAlarmFacts(lead: state.spec.lead, kind: kind, locationAuthorization: locationAuthorization)
                if showsActions, state.isActive {
                    HStack(spacing: Theme.Spacing.s) {
                        Button(action: onEdit) {
                            Label("Ändern", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive, action: onCancel) {
                            Label("Abbrechen", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The phase as a small capsule.
struct ExitAlarmPhasePill: View {
    let phase: ExitAlarmPhase
    var isPassed = false

    var body: some View {
        let (text, color) = descriptor
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.fill.opacity(0.16), in: .capsule)
            .contentTransition(.opacity)
    }

    private var descriptor: (String, (text: Color, fill: Color)) {
        switch phase {
        case .armed: ("scharf", (Theme.positiveText, Theme.positive))
        case .approaching: ("gleich", (Theme.summitText, Theme.summit))
        case .fired: (isPassed ? "vorbei" : "jetzt", (Theme.summitText, Theme.summit))
        case .snoozed: ("schlummert", (Theme.accentText, Theme.accent))
        case .acknowledged: ("quittiert", (Theme.positiveText, Theme.positive))
        case .ended: ("beendet", (Theme.textSecondary, Theme.textTertiary))
        }
    }
}

/// What the alarm uses, in three short facts: the lead, the kind of alarm and the location. Honest about each.
struct ExitAlarmFacts: View {
    let lead: ExitAlarmLead
    let kind: ExitAlarmKind
    let locationAuthorization: ExitAlarmLocationAuthorization

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        fact("clock", lead.title)
        fact(kindSymbol, kindText)
        fact(locationSymbol, locationText)
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.surfaceSecondary, in: .capsule)
    }

    private var kindText: String {
        switch kind {
        case .alarmKit: "Weckton auch lautlos"
        case .notifications: "Mitteilung"
        case .none: "Nur in der App"
        }
    }

    private var kindSymbol: String {
        switch kind {
        case .alarmKit: "alarm.fill"
        case .notifications: "bell.fill"
        case .none: "iphone"
        }
    }

    private var locationText: String {
        switch locationAuthorization {
        case .always: "Standort immer"
        case .whenInUse: "Standort beim Verwenden"
        default: "Nur Fahrplan"
        }
    }

    private var locationSymbol: String {
        locationAuthorization.allowsUpdates ? "location.fill" : "location.slash"
    }
}
