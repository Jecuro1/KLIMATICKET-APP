import SwiftUI
import KlimaCore

/// Price card: eyebrow (or the "Offizieller ÖBB-Preis" badge) + ⓘ popover, the big "€ 23,50 pro Richtung"
/// numeral with the "2 × € 23,50 · Hin + Rück" breakdown, the explanation line, "Anpassen" → inline
/// decimal field (comma or dot, normalised while typing – `EuroInput`), a plausibility callout for an own price that looks
/// off ("€ 150 für Wien → Mödling? Das wirkt hoch." – never blocking), "Zurücksetzen", and the round-trip toggle.
struct TripEdPriceCard: View {
    let model: TripEditorModel
    var focus: FocusState<TripEdField?>.Binding

    @State private var isEditingFare = false
    @State private var fareText = ""
    /// The own price when "Anpassen" was tapped (restored when the field is emptied and there is no estimate).
    @State private var manualFareBeforeEditing: Double? = nil
    @State private var showsInfo = false
    /// The plausibility callout shown – follows `model.tripEdFareHint` once typing pauses (no "Das wirkt niedrig" for the
    /// "1" of "150").
    @State private var shownHint: TripEdFareHint?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    amountRow
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let shownHint {
                        TripEdFareHintCallout(hint: shownHint, onFix: applyFix)
                            .padding(.top, Theme.Spacing.xxs)
                            .motionTransition(.rise)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, 14)
                .padding(.bottom, Theme.Spacing.s)
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .padding(.horizontal, Theme.Spacing.m)
                roundTripRow
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, 10)
            }
        }
        .onChange(of: focus.wrappedValue) { oldValue, newValue in
            if oldValue == .fare && newValue != .fare { finishEditing() }
        }
        .onChange(of: fareText) { oldText, text in
            // Normalised while typing ("23.5" → "23,5", two decimals, four digits); the corrected text comes back here.
            let normalized = EuroInput.live(text, previous: oldText)
            guard normalized == text else {
                fareText = normalized
                return
            }
            // Live update while typing (CTA + impact follow).
            guard isEditingFare else { return }
            applyFareText(text)
        }
        // The callout follows the price once typing pauses; right away for changes from elsewhere (favourite, reset).
        .task(id: model.tripEdFareHint) {
            let hint = model.tripEdFareHint
            guard hint != shownHint else { return }
            if isEditingFare && hint != nil {
                try? await Task.sleep(for: .milliseconds(700))
                if Task.isCancelled { return }
            }
            withMotion(Motion.smooth) { shownHint = hint }
        }
    }

    /// Under the price: the tariff basis – for an own price the estimate it replaces (the eyebrow already says "Eigener Preis").
    private var explanation: String {
        guard model.isFareManual else { return model.fareExplanation }
        guard let estimate = model.estimate else { return "Von dir eingetragen" }
        let basis = estimate.method == .officialTable ? "Offiziell" : "Schätzung"
        return "\(basis) \(Format.euroPrecise(estimate.fareEUR)) · \(estimate.explanation)"
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize >= .xxxLarge {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: 4) {
                    eyebrow
                    infoButton
                }
                actions
            }
        } else {
            HStack(spacing: 4) {
                eyebrow
                infoButton
                Spacer(minLength: Theme.Spacing.xxs)
                actions
            }
        }
    }

    @ViewBuilder
    private var eyebrow: some View {
        if model.isOfficialPrice {
            Label("Offizieller ÖBB-Preis", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.positiveText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.pine.opacity(0.13), in: .capsule)
                .motionTransition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        } else {
            Kicker(text: eyebrowText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var eyebrowText: String {
        if model.isFareManual { return "Eigener Preis" }
        if model.showsStoredFare { return "Erfasster Normalpreis" }
        return model.estimate == nil ? "Normalpreis" : "Geschätzter Normalpreis"
    }

    private var infoButton: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Wie wird der Preis geschätzt?")
        .popover(isPresented: $showsInfo) {
            infoPopover
        }
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("So schätzt KlimaBilanz den Preis")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(Copy.fareExplanation)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding(Theme.Spacing.m)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private var actions: some View {
        if isEditingFare {
            pill("Fertig", symbol: "checkmark") {
                // Losing focus finishes the edit; if the field never got focus, finish directly.
                if focus.wrappedValue == .fare { focus.wrappedValue = nil } else { finishEditing() }
            }
        } else if model.canResetFare {
            // Only with an estimate to go back to – for a custom place "Zurücksetzen" would wipe the only price.
            // A saved older price (editing) can be brought up to today's estimate ("Aktualisieren").
            HStack(spacing: 6) {
                if model.isFareManual {
                    pill("Zurücksetzen", symbol: "arrow.uturn.backward") { resetFare() }
                } else {
                    pill("Aktualisieren", symbol: "arrow.clockwise") { resetFare() }
                }
                Button {
                    beginEditing()
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent.opacity(0.12), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Preis anpassen")
            }
        } else {
            pill(model.fare > 0 ? "Anpassen" : "Preis eingeben", symbol: "pencil") { beginEditing() }
        }
    }

    private func pill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, 6)
                .background(Theme.accent.opacity(0.12), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .fixedSize()
    }

    // MARK: Amount

    @ViewBuilder
    private var amountRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                numeral
                perDirection
                if showsBreakdown { breakdown }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                numeral
                perDirection
                Spacer(minLength: Theme.Spacing.xxs)
                if showsBreakdown { breakdown }
            }
        }
    }

    private var showsBreakdown: Bool { model.isRoundTrip && model.fare > 0 }

    private var numeral: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("€")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            if isEditingFare {
                fareField
            } else {
                amountText
            }
        }
    }

    private var amountText: some View {
        Text(model.fare > 0 ? Format.number(model.fare, decimals: 2) : "–")
            .font(Theme.Typography.priceNumeral)
            .foregroundStyle(model.fare > 0 ? Theme.textPrimary : Theme.textTertiary)
            // Route, mode, class, Vorteilscard: the price rolls to the new fare.
            .numericValue(model.fare)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .onTapGesture { beginEditing() }
            .accessibilityLabel("Normalpreis pro Richtung")
            .accessibilityValue(model.fare > 0 ? Format.euroPrecise(model.fare) : "noch kein Preis")
            .accessibilityHint("Doppeltippen, um den Preis anzupassen")
            .accessibilityAddTraits(.isButton)
    }

    private var fareField: some View {
        TextField("0,00", text: $fareText)
            .font(Theme.Typography.priceNumeral)
            .foregroundStyle(Theme.textPrimary)
            .keyboardType(.decimalPad)
            .focused(focus, equals: .fare)
            .frame(maxWidth: 180)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Theme.accent)
                    .frame(height: 2)
                    .offset(y: 2)
            }
            .onAppear {
                Task { @MainActor in focus.wrappedValue = .fare }
            }
            .accessibilityLabel("Eigener Normalpreis in Euro pro Richtung")
    }

    private var perDirection: some View {
        Text("pro Richtung")
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
    }

    /// "2 × € 23,50 / Hin + Rück"
    private var breakdown: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("2 × " + Format.euroPrecise(model.fare))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .numericValue(model.fare)
            Text("Hin + Rück")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .motionTransition(.opacity.combined(with: .move(edge: .trailing)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Round trip

    private var roundTripRow: some View {
        Toggle(isOn: roundTripBinding) {
            TripEdRowLabel(symbol: "arrow.left.arrow.right", tint: Theme.dusk, title: "Hin- und Rückfahrt",
                           subtitle: "Wert wird verdoppelt")
        }
        .tint(Theme.accent)
    }

    private var roundTripBinding: Binding<Bool> {
        Binding(
            get: { model.isRoundTrip },
            set: { newValue in
                withMotion(Motion.snappy) { model.isRoundTrip = newValue }
            }
        )
    }

    // MARK: Manual fare

    private func beginEditing() {
        manualFareBeforeEditing = model.manualFare
        fareText = TripEdFormat.editableEuro(model.fare)
        withMotion(Motion.snappy) { isEditingFare = true }
    }

    /// Applies the field to the model (live and on finish). The prefill equals the current fare and changes nothing.
    /// An empty field means "no own price": back to the estimate, or – without one – to the price from before this edit,
    /// so deleting the digits never leaves a half-typed value (e.g. "2" of "23,50") behind in the CTA or the saved trip.
    private func applyFareText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let restored = model.estimate == nil ? manualFareBeforeEditing : nil
            if model.manualFare != restored { model.manualFare = restored }
        } else if let value = TripEdFormat.parseEuro(trimmed), abs(value - model.fare) > 0.001 {
            model.manualFare = value
        }
    }

    private func finishEditing() {
        guard isEditingFare else { return }
        applyFareText(fareText)
        // Typing the estimate again is the same as resetting (keeps the "Offizieller ÖBB-Preis" badge).
        if let manual = model.manualFare, let estimate = model.estimate, abs(manual - estimate.fareEUR) < 0.005 {
            model.resetManualFare()
        }
        withMotion(Motion.snappy) { isEditingFare = false }
    }

    /// One tap from the plausibility callout: the one-way half, or back to the estimate.
    private func applyFix(_ fix: TripEdFareHint.Fix) {
        switch fix {
        case .halve(let oneWay):
            withMotion(Motion.smooth) {
                model.manualFare = oneWay
                if isEditingFare { fareText = TripEdFormat.editableEuro(oneWay) }
            }
            if let estimate = model.estimate, abs(oneWay - estimate.fareEUR) < 0.005 { resetFare() }
        case .useEstimate:
            resetFare()
        }
    }

    private func resetFare() {
        withMotion(Motion.smooth) {
            model.resetManualFare()
            isEditingFare = false
        }
        fareText = ""
        focus.wrappedValue = nil
    }
}
