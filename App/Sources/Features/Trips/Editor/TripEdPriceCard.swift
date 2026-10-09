import SwiftUI
import KlimaCore

/// Price card: eyebrow (or the "Offizieller ÖBB-Preis" badge) + ⓘ popover, the big "€ 23,50 pro Richtung"
/// numeral with the "2 × € 23,50 · Hin + Rück" breakdown, the explanation line, "Anpassen" → inline
/// decimal field (de-AT comma input), "Zurücksetzen", and the round-trip toggle ("Wert wird verdoppelt").
struct TripEdPriceCard: View {
    let model: TripEditorModel
    var focus: FocusState<TripEdField?>.Binding

    @State private var isEditingFare = false
    @State private var fareText = ""
    @State private var showsInfo = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    amountRow
                    Text(model.fareExplanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .onChange(of: fareText) { _, text in
            // Live update while typing (CTA + impact follow); ignore the prefill that equals the current fare.
            guard isEditingFare, let value = TripEdFormat.parseEuro(text), abs(value - model.fare) > 0.001 else { return }
            model.manualFare = value
        }
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
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        } else {
            Kicker(text: eyebrowText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var eyebrowText: String {
        if model.isFareManual { return "Eigener Preis" }
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
        } else if model.isFareManual {
            HStack(spacing: 6) {
                pill("Zurücksetzen", symbol: "arrow.uturn.backward") { resetFare() }
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
                .buttonStyle(TripEdPressStyle())
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
        .buttonStyle(TripEdPressStyle())
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
            .contentTransition(.numericText(value: model.fare))
            .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: model.fare)
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
                .contentTransition(.numericText(value: model.fare))
            Text("Hin + Rück")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
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
                withAnimation(.snappy(duration: 0.3)) { model.isRoundTrip = newValue }
            }
        )
    }

    // MARK: Manual fare

    private func beginEditing() {
        fareText = TripEdFormat.editableEuro(model.fare)
        withAnimation(.snappy(duration: 0.25)) { isEditingFare = true }
    }

    private func finishEditing() {
        let trimmed = fareText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if model.estimate != nil { model.resetManualFare() }
        } else if let value = TripEdFormat.parseEuro(trimmed) {
            model.manualFare = value
        }
        // Typing the estimate again is the same as resetting (keeps the "Offizieller ÖBB-Preis" badge).
        if let manual = model.manualFare, let estimate = model.estimate, abs(manual - estimate.fareEUR) < 0.005 {
            model.resetManualFare()
        }
        withAnimation(.snappy(duration: 0.25)) { isEditingFare = false }
    }

    private func resetFare() {
        withAnimation(.snappy(duration: 0.3)) {
            model.resetManualFare()
            isEditingFare = false
        }
        fareText = ""
        focus.wrappedValue = nil
    }
}
