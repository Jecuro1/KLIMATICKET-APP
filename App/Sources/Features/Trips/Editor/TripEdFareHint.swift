import SwiftUI
import KlimaCore

// Plausibility of an own price in the trip editor ("€ 150 für Wien → Mödling? Das wirkt hoch.") – a friendly callout
// under the price with a one-tap fix, never a block: saving always takes what was typed (KlimaCore `FarePlausibility`).

/// What the price card says about an own price.
struct TripEdFareHint: Equatable {
    enum Fix: Equatable {
        /// Take the one-way half of a there-and-back price.
        case halve(Double)
        /// Back to the estimate.
        case useEstimate
    }

    var title: String
    var detail: String
    var fix: Fix?
    var fixTitle: String?
}

extension TripEditorModel {
    /// Nil while the price is plausible, estimated or not set.
    var tripEdFareHint: TripEdFareHint? {
        guard let manualFare, manualFare > 0,
              let verdict = FarePlausibility.check(entered: manualFare, estimate: estimate?.fareEUR) else { return nil }
        let amount = Format.euro(manualFare)
        let route = resolvedFromName.isEmpty || resolvedToName.isEmpty
            ? nil : TripEdFormat.routeTitle(from: resolvedFromName, to: resolvedToName, roundTrip: false)
        switch verdict {
        case .looksLikeReturn(let oneWay):
            return TripEdFareHint(title: "\(amount) sieht nach Hin + Rück aus.",
                                  detail: "Hier gehört der Preis für eine Richtung hin\(isRoundTrip ? " – die Rückfahrt zählt der Schalter darunter." : ".")",
                                  fix: .halve(oneWay), fixTitle: "\(Format.euroPrecise(oneWay)) nehmen")
        case .high(let reference):
            let title = route.map { "\(amount) für \($0)? Das wirkt hoch." } ?? "\(amount) für eine Richtung? Das wirkt hoch."
            guard let reference else {
                return TripEdFareHint(title: title, detail: "Prüf kurz das Komma – gespeichert wird, was du eingibst.")
            }
            return TripEdFareHint(title: title,
                                  detail: "Geschätzt sind es etwa \(Format.euroPrecise(reference)) pro Richtung. Gespeichert wird, was du eingibst.",
                                  fix: .useEstimate, fixTitle: "Schätzung nehmen")
        case .low(let reference):
            let title = route.map { "Nur \(amount) für \($0)? Das wirkt niedrig." } ?? "Nur \(amount)? Das wirkt niedrig."
            return TripEdFareHint(title: title,
                                  detail: "Geschätzt sind es etwa \(Format.euroPrecise(reference)) pro Richtung. Gespeichert wird, was du eingibst.",
                                  fix: .useEstimate, fixTitle: "Schätzung nehmen")
        }
    }
}

/// "ⓘ € 150 für Wien Hbf → Mödling? Das wirkt hoch." · detail · [Schätzung nehmen] – warm, quiet, inside the price card.
struct TripEdFareHintCallout: View {
    let hint: TripEdFareHint
    var onFix: (TripEdFareHint.Fix) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.summitText)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hint.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(hint.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hinweis: \(hint.title) \(hint.detail)")
                if let fix = hint.fix, let fixTitle = hint.fixTitle {
                    Button {
                        onFix(fix)
                    } label: {
                        Text(fixTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.summitText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.summit.opacity(0.14), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s)
        .background(Theme.summit.opacity(0.09), in: .rect(cornerRadius: Theme.Radius.chip, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
