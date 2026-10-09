import SwiftUI
import KlimaCore

/// Glass capsule on the Übersicht while a ride runs ("Unterwegs · St. Anton ⇄ Innsbruck Hbf · 42:17"): the same ride
/// as the Live Activity, so it can also be saved or ended from inside the app. Renders nothing without a running ride.
struct RideDashCapsule: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controller = RideActivityController.shared
    @State private var asking: RideRecord?
    @State private var finishedTick = 0

    var body: some View {
        if !controller.rides.isEmpty {
            capsules
        }
    }

    private var capsules: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(controller.rides) { ride in
                capsule(ride)
            }
        }
        .confirmationDialog("Fahrt beenden?", isPresented: isAsking, titleVisibility: .visible, presenting: asking) { ride in
            Button("Fahrt speichern · \(RideFormat.plusEuro(ride.trip.totalValue))") { finish(ride, saving: true) }
            Button("Beenden ohne Speichern", role: .destructive) { finish(ride, saving: false) }
            Button("Weiterfahren", role: .cancel) {}
        } message: { ride in
            Text("\(RideNames.route(from: ride.trip.fromName, to: ride.trip.toName, roundTrip: ride.trip.isRoundTrip)) · unterwegs seit \(Format.time(ride.startedAt))")
        }
        .sensoryFeedback(.success, trigger: finishedTick) { _, _ in app.settings.hapticsEnabled }
    }

    private func capsule(_ ride: RideRecord) -> some View {
        Button {
            asking = ride
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.summitText)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating,
                                  isActive: !reduceMotion && !LaunchMode.isScreenshot)
                destinationLine(ride)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text(timerInterval: ride.startedAt...RidePolicy.staleDate(for: ride.startedAt), countsDown: false)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.dawn.opacity(0.16)).interactive(), in: .capsule)
        .accessibilityLabel("Unterwegs: \(RideNames.route(from: ride.trip.fromName, to: ride.trip.toName, roundTrip: ride.trip.isRoundTrip))")
        .accessibilityValue("seit \(Format.time(ride.startedAt)), Wert \(Format.euroPrecise(ride.trip.totalValue))")
        .accessibilityHint("Fahrt speichern oder beenden")
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// "Unterwegs nach Innsbruck Hbf" – the destination says enough; the full route is in the dialog and VoiceOver.
    private func destinationLine(_ ride: RideRecord) -> Text {
        let destination = Text(RideNames.short(ride.trip.toName))
            .fontWeight(.semibold)
            .foregroundStyle(Theme.textPrimary)
        return Text("Unterwegs nach \(destination)")
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
    }

    private func finish(_ ride: RideRecord, saving: Bool) {
        asking = nil
        guard let activityID = ride.activityID else { return }
        if saving { finishedTick += 1 }
        Task { await controller.end(activityID, saving: saving) }
    }
}
