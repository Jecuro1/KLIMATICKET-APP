import SwiftUI
import SwiftData
import KlimaCore

/// "Vorschläge" from automatic trip detection – one card per detected trip with "Erfassen" / "Verwerfen".
/// The caller hides the section when there are no suggestions. Cards rise in and out; "Erfassen" confirms through the
/// toast (its success haptic), "Verwerfen" with a light tap.
struct DashSuggestionsSection: View {
    var suggestions: [TripSuggestion]

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var dismissTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DashStyle.cardSpacing) {
            SectionHeader(title: "Vorschläge")
                .padding(.horizontal, DashStyle.headerInset)
            ForEach(suggestions) { suggestion in
                DashSuggestionCard(suggestion: suggestion,
                                   onConfirm: { confirm(suggestion) },
                                   onDismiss: { discard(suggestion) })
                    .motionTransition(.rise)
            }
        }
        .haptic(.tap, trigger: dismissTick)
    }

    private func confirm(_ suggestion: TripSuggestion) {
        let repository = Repository(context: context, app: app)
        withMotion(Motion.smooth) { app.detection.confirm(suggestion, repository: repository) }
        let route = "\(TripRow.short(suggestion.fromName)) → \(TripRow.short(suggestion.toName))"
        app.showToast("checkmark.circle.fill", "Fahrt erfasst", route + " · + " + Format.euroPrecise(suggestion.fareEUR))
    }

    private func discard(_ suggestion: TripSuggestion) {
        withMotion(Motion.smooth) { app.detection.dismiss(suggestion) }
        dismissTick += 1
    }
}

struct DashSuggestionCard: View {
    let suggestion: TripSuggestion
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                summary
                actions
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 40, height: 40)
                .background(Theme.ctaGradient, in: .rect(cornerRadius: Theme.Radius.modeTile, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "Erkannte Fahrt", color: Theme.accentText)
                Text("\(TripRow.short(suggestion.fromName)) → \(TripRow.short(suggestion.toName))")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.xs)
            Text(Format.euroPrecise(suggestion.fareEUR))
                .font(Theme.Typography.numberSmall)
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button(action: onConfirm) {
                Label("Erfassen", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            Button(action: onDismiss) {
                Text("Verwerfen")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
    }

    private var detail: String {
        let times = "\(Format.time(suggestion.departedAt))–\(Format.time(suggestion.arrivedAt))"
        var parts = ["\(Format.relativeDay(suggestion.departedAt)), \(times)"]
        if suggestion.distanceKm > 0 { parts.append(Format.km(suggestion.distanceKm)) }
        return parts.joined(separator: " · ")
    }
}
