import SwiftUI
import KlimaCore

// MARK: commute – the three quiet faces of the Pendel-Modus card (docs/COMMUTE.md §1): the invitation „Ist das dein
// Arbeitsweg?“, the compact „Nächste Pendelfahrt heute 17:12“ outside the live window, and „Stammstrecke fehlt“.

// MARK: - Invitation

/// Asked only when the detector is confident and the pair was not declined in the last 30 days. „Ja, merken“ makes it the
/// Stammstrecke; „Nein“ keeps it quiet for 30 days (with „Rückgängig“ in the toast).
struct CommuteInviteCard: View {
    let guess: CommuteGuess
    var onAccept: () -> Void
    var onDecline: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GlassCard(padding: Theme.Spacing.m, tint: Theme.glacier) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentText)
                        .symbolEffect(.pulse, options: .nonRepeating)
                        .accessibilityHidden(true)
                    Kicker(text: "Pendel-Modus", color: Theme.accentText)
                }
                Text("Ist das dein Arbeitsweg?")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("\(TripRow.short(guess.origin.name)) \(Image(systemName: "arrow.left.arrow.right")) \(TripRow.short(guess.destination.name))")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(TripRow.short(guess.origin.name)) und \(TripRow.short(guess.destination.name))")
                Text(evidence)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text("Dann zeigt dir die Übersicht vor der Abfahrt die nächsten Züge mit Verspätung, Gleis und einer Alternative.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                buttons
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var buttons: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xs))
                                                  : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
        layout {
            Button(action: onAccept) {
                Label("Ja, merken", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentTint)
            .accessibilityLabel("Ja, als Stammstrecke merken")
            Button(action: onDecline) {
                Label("Nein", systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Nein, das ist nicht mein Arbeitsweg")
            .accessibilityHint("Fragt 30 Tage nicht mehr nach")
        }
        .controlSize(.large)
    }

    /// „34 Fahrten an 17 Tagen in 7 Wochen · Mo–Fr · meist 07:20 hin, 17:10 zurück“.
    private var evidence: String {
        var parts = ["\(guess.rides) Fahrten an \(guess.days) Tagen in \(guess.weeks) Wochen"]
        parts.append(CommutePlan(weekdays: guess.weekdays).dayText)
        if let out = guess.outboundMinute, let back = guess.returnMinute {
            parts.append("meist \(CommutePlan.clockText(out)) hin, \(CommutePlan.clockText(back)) zurück")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Compact (outside the window)

/// „Nächste Pendelfahrt heute 17:12“ from the plan – no request is made outside the live window.
struct CommuteCompactCard: View {
    let slot: CommuteSlot
    let now: Date

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    private var model: CommuteModel { .shared }

    var body: some View {
        let ends = model.ends(slot.direction)
        let when = CommuteWindow.dayText(slot.departure, now: now, calendar: .vienna)
        let actions = CommuteActions(app: app)
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    Image(systemName: slot.direction == .outbound ? "sunrise.fill" : "sunset.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                        .background(Theme.glacier.opacity(0.14), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Pendeln · \(slot.direction.title)", color: Theme.accentText)
                        Text("Nächste Pendelfahrt \(when)")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        if let ends {
                            Text("\(TripRow.short(ends.from.name)) → \(TripRow.short(ends.to.name)) · aktualisiert beim Öffnen")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    if !typeSize.isAccessibilitySize {
                        logButton(actions)
                    }
                }
                if typeSize.isAccessibilitySize {
                    logButton(actions).padding(.top, Theme.Spacing.s)
                }
            }
        }
        .contextMenu {
            Button("Fahrt erfassen", systemImage: "plus.circle.fill") { actions.logTrip(now: now) }
            Button("Verbindung suchen", systemImage: "slider.horizontal.3") { actions.changeConnection(shown: slot.direction) }
            Button("Rückfahrt planen", systemImage: "arrow.uturn.backward") { actions.planReturn(shown: slot.direction, now: now) }
            Button("Pendel-Einstellungen", systemImage: "gearshape") { model.showsSetup = true }
        }
        .accessibilityActions {
            Button("Verbindung suchen") { actions.changeConnection(shown: slot.direction) }
            Button("Rückfahrt planen") { actions.planReturn(shown: slot.direction, now: now) }
            Button("Pendel-Einstellungen") { model.showsSetup = true }
        }
    }

    @ViewBuilder
    private func logButton(_ actions: CommuteActions) -> some View {
        if typeSize.isAccessibilitySize {
            Button { actions.logTrip(now: now) } label: {
                Label("Fahrt erfassen", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentTint)
            .controlSize(.large)
        } else {
            Button { actions.logTrip(now: now) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Theme.prominentTint)
            .accessibilityLabel("Pendelfahrt erfassen")
        }
    }
}

// MARK: - Needs a route

/// The mode is on, but the Stammstrecke (or its weekdays) is missing: one tap opens the setup.
struct CommuteNeedsRouteCard: View {
    var title = "Stammstrecke fehlt"
    var subtitle = "Wähle deine Strecke, dann zeigt die Karte hier vor der Abfahrt die nächsten Züge."
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(padding: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 44, height: 44)
                        .background(Theme.glacier.opacity(0.14), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: "Pendeln", color: Theme.accentText)
                        Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet die Pendel-Einstellungen")
    }
}
