import SwiftUI
import SwiftData
import UIKit
import KlimaCore

/// Trip editor entry point "Fahrt jetzt starten": instead of saving right away, the ride runs as a Live Activity on the
/// Lock Screen and in the Dynamic Island and is saved with one tap when you arrive. Shown for new trips departing
/// around now; explains itself (ⓘ → preview) and handles switched-off Live Activities gracefully.
struct RideEdStartCard: View {
    let model: TripEditorModel
    /// "Als Favorit speichern" is honoured on start, unless the route already is a favourite.
    var isExistingFavorite: Bool
    /// Called after the ride started (the editor closes).
    var onStarted: () -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var controller = RideActivityController.shared
    @State private var isStarting = false
    @State private var showsPreview = false
    @State private var errorMessage: String?
    @State private var startedTick = 0

    var body: some View {
        if !model.isEditing && RidePlanner.canStart(at: model.date) {
            SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        label
                        Spacer(minLength: Theme.Spacing.xs)
                        actionButton
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        label
                        actionButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 11)
            }
            .sheet(isPresented: $showsPreview) {
                NavigationStack {
                    RideActivityPreviewView(isSheet: true)
                }
            }
            .alert("Fahrt nicht gestartet", isPresented: hasError) {
                if errorMessage == RideActivityError.disabled.errorDescription {
                    Button("Einstellungen") { openSettings() }
                    Button("OK", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: startedTick) { _, _ in app.settings.hapticsEnabled }
        }
    }

    // MARK: Parts

    private var isEnabled: Bool { controller.areActivitiesEnabled || LaunchMode.isScreenshot }

    private var label: some View {
        HStack(spacing: Theme.Spacing.s) {
            TripEdIconTile(symbol: "dot.radiowaves.left.and.right", tint: Theme.dusk)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Fahrt jetzt starten")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        showsPreview = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minWidth: 28, minHeight: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("So sieht die Live-Aktivität aus")
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        if !isEnabled { return "Live-Aktivitäten sind für KlimaBilanz ausgeschaltet." }
        return "Live am Sperrbildschirm – gespeichert wird beim Ankommen."
    }

    @ViewBuilder
    private var actionButton: some View {
        if isEnabled {
            Button(action: start) {
                HStack(spacing: 6) {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.onAccent)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.footnote.weight(.bold))
                    }
                    Text("Starten")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.dusk)
            .disabled(!model.canSave || isStarting)
            .accessibilityLabel("Fahrt jetzt starten")
            .accessibilityHint(model.canSave ? "Zeigt die Fahrt als Live-Aktivität und speichert sie, wenn du ankommst."
                                             : (model.validationHint ?? ""))
        } else {
            Button("Einschalten", action: openSettings)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .accessibilityHint("Öffnet die Einstellungen von KlimaBilanz, dort kannst du Live-Aktivitäten erlauben.")
        }
    }

    private var hasError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: Actions

    private func start() {
        guard !isStarting, let ride = RidePlanner.ride(from: model, context: context) else { return }
        isStarting = true
        Task { @MainActor in
            defer { isStarting = false }
            do {
                try await controller.start(ride: ride)
                if model.saveAsFavorite && !isExistingFavorite { addFavorite() }
                startedTick += 1
                app.showToast("dot.radiowaves.left.and.right", "Gute Fahrt!",
                              "Live am Sperrbildschirm · speichern, wenn du ankommst")
                onStarted()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? RideActivityError.failed.errorDescription
            }
        }
    }

    /// The route becomes a favourite right away (the trip itself is saved when the ride ends).
    private func addFavorite() {
        let route = TripEntity(date: model.date, fromName: model.resolvedFromName, toName: model.resolvedToName,
                               fromStationID: model.fromStation?.id, toStationID: model.toStation?.id, mode: model.mode,
                               distanceKm: model.distanceKm, fareEUR: model.fare, isFareManual: model.isFareManual,
                               isRoundTrip: model.isRoundTrip, travelClass: model.travelClass, states: model.states)
        Repository(context: context, app: app).addFavorite(from: route)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
