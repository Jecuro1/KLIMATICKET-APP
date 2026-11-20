import SwiftUI
import SwiftData
import KlimaCore

// MARK: delaydiary – „Verspätung“: the small sheet that records a trip's arrival delay (docs/DELAY_DIARY.md §2)

/// A stepper from 0 („pünktlich“) to 240 minutes in 1-minute steps (hold to repeat), quick values, what the mark makes of it,
/// „Speichern“ and – when something is recorded – „Entfernen“. Writes through `Repository.recordDelay` / `removeDelay`.
struct DelayEntrySheet: View {
    let trip: TripEntity

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var minutes: Int
    /// The big number grows with the text (64 pt at the default size), up to what the line still holds.
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64
    @State private var stepUp = 0
    @State private var stepDown = 0
    @State private var picked = 0

    private static let quickValues = [0, 5, 10, 15, 20, 30, 45, 60]

    init(trip: TripEntity) {
        self.trip = trip
        _minutes = State(initialValue: trip.recordedDelay?.minutes ?? 0)
    }

    private var threshold: Int { DelayDiarySettings.shared.options.thresholdMinutes }
    private var recorded: (minutes: Int, source: TripDelaySource)? { trip.recordedDelay }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    header
                    if recorded == nil {
                        Text("Noch nicht erfasst – wähle die Minuten oder „Pünktlich“.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    valueCard
                    quickValues
                    notes
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .background(Theme.sheetBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .navigationTitle("Verspätung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel("Schließen")
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .haptic(.increase, trigger: stepUp)
        .haptic(.decrease, trigger: stepDown)
        .haptic(.selection, trigger: picked)
        .accessibilityIdentifier("delay.entry")
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 2) {
            Text(TripListFormat.routeTitle(trip.fromName, trip.toName, roundTrip: trip.isRoundTrip))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [DelayDiaryFormat.when(trip.date)]
        let line = trip.lineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { parts.append(line) }
        return parts.joined(separator: " · ")
    }

    // MARK: Value

    private var valueCard: some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
            VStack(spacing: Theme.Spacing.s) {
                if typeSize.isAccessibilitySize {
                    // At the accessibility sizes the number gets the full width, the buttons go under it.
                    numeral
                        .frame(maxWidth: .infinity)
                    HStack {
                        minusButton
                        Spacer(minLength: Theme.Spacing.s)
                        plusButton
                    }
                } else {
                    HStack(spacing: Theme.Spacing.s) {
                        minusButton
                        numeral
                            .frame(maxWidth: .infinity)
                        plusButton
                    }
                }
                verdict
            }
        }
    }

    private var minusButton: some View {
        stepButton(symbol: "minus", label: "Eine Minute weniger", enabled: minutes > 0) {
            guard minutes > 0 else { return }
            withMotion(Motion.snappy) { minutes -= 1 }
            stepDown += 1
        }
    }

    private var plusButton: some View {
        stepButton(symbol: "plus", label: "Eine Minute mehr", enabled: minutes < DelayDiaryRules.maximumMinutes) {
            guard minutes < DelayDiaryRules.maximumMinutes else { return }
            withMotion(Motion.snappy) { minutes += 1 }
            stepUp += 1
        }
    }

    private var numeral: some View {
        VStack(spacing: 0) {
            if minutes == 0 {
                Label("pünktlich", systemImage: "checkmark.circle.fill")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.positiveText)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .motionTransition(.pop)
                Text("angekommen")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("+\(minutes)")
                        .font(.system(size: numeralSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(minutes)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Min.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .motionTransition(.pop)
                Text("später angekommen")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
        }
        .frame(minHeight: 96)
        .motionAnimation(Motion.snappy, value: minutes == 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verspätung")
        .accessibilityValue(DelayDiaryText.spoken(minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if minutes < DelayDiaryRules.maximumMinutes { minutes += 1 }
            case .decrement: if minutes > 0 { minutes -= 1 }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("delay.entry.value")
    }

    private func stepButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// What the personal mark makes of the value – in words and a symbol, never colour alone.
    private var verdict: some View {
        let late = DelayDiaryRules.isLate(minutes, threshold: threshold)
        return Label {
            Text(late ? "Zählt als verspätet (ab \(threshold)\u{00A0}Min.)" : "Zählt als pünktlich (unter \(threshold)\u{00A0}Min.)")
                .contentTransition(.interpolate)
        } icon: {
            Image(systemName: late ? "clock.badge.exclamationmark.fill" : "checkmark.seal.fill")
                .foregroundStyle(late ? Theme.summitText : Theme.positiveText)
                .symbolReplaceTransition()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .motionAnimation(Motion.snappy, value: late)
        .accessibilityElement(children: .combine)
    }

    // MARK: Quick values

    private var quickValues: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 120 : 68), spacing: Theme.Spacing.xs)],
                  spacing: Theme.Spacing.xs) {
            ForEach(Self.quickValues, id: \.self) { value in
                let selected = value == minutes
                Button {
                    withMotion(Motion.snappy) { minutes = value }
                    picked += 1
                } label: {
                    Text(value == 0 ? "Pünktlich" : "+\(value)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selected ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(Theme.surfaceSecondary), in: .capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(value == 0 ? "Pünktlich" : "\(value) Minuten")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        // At AX5 „Pünktlich“ filled its capsule edge to edge and sat lower than „+5“ (fourth screenshots): the chips stop at AX2.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Notes

    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if trip.journeyID != nil {
                note("point.topleft.down.to.point.bottomright.curvepath",
                     "Ankunft dieser Etappe. Für die Reise zählt die letzte erfasste Ankunft – eine Reise ist eine Fahrt.")
            }
            if trip.isRoundTrip {
                note("arrow.left.arrow.right", "Hin & Retour ist ein Eintrag: trag die größere der beiden Verspätungen ein.")
            }
            if let recorded, recorded.source == .live {
                note("dot.radiowaves.left.and.right", "Aus Live-Daten übernommen. Änderst du die Minuten, gilt der Eintrag als von Hand.")
            }
            // review-delaydiary: the JSON backup carries the minutes too (Daten & Sicherung), not only the PDF.
            note("lock.fill", "Bleibt auf diesem iPhone – weiter geht es nur, wenn du selbst das PDF oder eine Sicherung teilst.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.textTertiary)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                save()
            } label: {
                Text(saveTitle)
                    .contentTransition(.numericText(value: Double(minutes)))
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("delay.entry.save")
            if recorded != nil {
                Button(role: .destructive) {
                    remove()
                } label: {
                    Label("Entfernen", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.negativeText)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Die Fahrt gilt dann wieder als nicht erfasst")
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xs)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .background {
            Theme.sheetBackground
                .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
                .ignoresSafeArea()
        }
    }

    /// „Speichern · +9 Min.“; at the accessibility sizes just „Speichern“ (the number is right above).
    private var saveTitle: String {
        if minutes == 0 { return typeSize.isAccessibilitySize ? "Pünktlich speichern" : "Als pünktlich speichern" }
        return typeSize.isAccessibilitySize ? "Speichern" : "Speichern · +\(minutes)\u{00A0}Min."
    }

    private func save() {
        let before = (trip: trip, minutes: trip.delayMinutes, sourceRaw: trip.delaySourceRaw)
        // An unchanged live value stays live; anything typed here is „von Hand“.
        let source: TripDelaySource = (recorded?.source == .live && recorded?.minutes == minutes) ? .live : .manual
        let repo = Repository(context: context, app: app)
        guard repo.recordDelay(trip, minutes: minutes, source: source) else { return }
        dismiss()
        let title = minutes == 0 ? "Als pünktlich eingetragen" : "Verspätung eingetragen"
        app.showToast("clock.badge.checkmark", title, "\(DelayDiaryText.minutes(minutes)) · \(TripListFormat.routeTitle(trip.fromName, trip.toName))",
                      actionTitle: "Rückgängig", haptic: .success) {
            Repository(context: context, app: app).restoreDelays([before])
        }
    }

    private func remove() {
        let before = (trip: trip, minutes: trip.delayMinutes, sourceRaw: trip.delaySourceRaw)
        guard Repository(context: context, app: app).removeDelay(trip) else { return }
        dismiss()
        app.showToast("clock.arrow.circlepath", "Verspätung entfernt", "Die Fahrt gilt wieder als nicht erfasst",
                      actionTitle: "Rückgängig", haptic: .warning) {
            Repository(context: context, app: app).restoreDelays([before])
        }
    }
}

// MARK: - The row in a trip

/// Fahrt-Detail: „Verspätung“ with what is recorded („+12 Min. · von Hand“ / „nicht erfasst“); a tap opens the sheet.
struct DelayTripRow: View {
    let trip: TripEntity

    @State private var isEditing = false

    var body: some View {
        let recorded = trip.recordedDelay
        let threshold = DelayDiarySettings.shared.options.thresholdMinutes
        let late = recorded.map { DelayDiaryRules.isLate($0.minutes, threshold: threshold) } ?? false
        Button {
            isEditing = true
        } label: {
            GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.tile) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        DelayDiaryTile(size: 40, isLate: late, isOpen: recorded == nil)
                        titles
                        Spacer(minLength: Theme.Spacing.xs)
                        value(recorded, late: late, alignment: .trailing)
                        chevron
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.s) {
                            DelayDiaryTile(size: 40, isLate: late, isOpen: recorded == nil)
                            titles
                            Spacer(minLength: 0)
                            chevron
                        }
                        value(recorded, late: late, alignment: .leading)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verspätung")
        .accessibilityValue(DelayDiaryText.spokenRow(minutes: recorded?.minutes, source: recorded?.source))
        .accessibilityHint(recorded == nil ? "Trägt ein, ob die Fahrt pünktlich war" : "Ändert oder entfernt den Eintrag")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("delay.row")
        .sheet(isPresented: $isEditing) {
            DelayEntrySheet(trip: trip)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Verspätung")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(trip.journeyID == nil ? "bei der Ankunft" : "Ankunft dieser Etappe")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// „+12 Min.“ over „von Hand“, „pünktlich“ over „von Hand“, or „nicht erfasst“ over „Eintragen“.
    private func value(_ recorded: (minutes: Int, source: TripDelaySource)?, late: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(recorded.map { DelayDiaryText.minutes($0.minutes) } ?? "nicht erfasst")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(recorded == nil ? Theme.textSecondary : (late ? Theme.summitText : Theme.positiveText))
                .contentTransition(.numericText())
            Text(recorded.map { DelayDiaryText.sourceName($0.source) } ?? "Eintragen")
                .font(.caption)
                .foregroundStyle(recorded == nil ? Theme.accentText : Theme.textSecondary)
        }
        .lineLimit(1)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
    }
}

/// The diary's tile: a clock on the dawn → alpenglow gradient (pine → glacier for „pünktlich“). `isOpen` (a trip without an
/// entry) shows the plain clock on the diary's colours – neither a check nor a warning (review-delaydiary: an unrecorded trip
/// showed the green „pünktlich“ tile).
struct DelayDiaryTile: View {
    var size: CGFloat = 44
    var isLate: Bool = true
    var isOpen: Bool = false

    private var symbol: String {
        if isOpen { return "clock" }
        return isLate ? "clock.badge.exclamationmark" : "clock.badge.checkmark"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: isLate || isOpen ? [Theme.dawn, Theme.alpenglow] : [Theme.pine, Theme.glacier],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .environment(\.colorScheme, .light)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}
