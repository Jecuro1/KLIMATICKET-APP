import SwiftUI
import SwiftData
import KlimaCore

/// "Fahrt hinzufügen" / "Fahrt bearbeiten" sheet (DESIGN.md §5.2, mockup alpine-glass/02-add-trip).
/// Presented by RootView via `app.tripDraft`. Logging must feel instant: everything is prefilled from the
/// draft, the price is estimated live and the impact on the amortisation is previewed before saving.
struct TripEditorView: View {
    let draft: TripDraft

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    init(draft: TripDraft) {
        self.draft = draft
    }

    var body: some View {
        TripEdSheet(app: app, draft: draft, editing: editingTrip)
    }

    /// The trip being edited (looked up by `draft.editingTripID`).
    private var editingTrip: TripEntity? {
        guard let id = draft.editingTripID else { return nil }
        let descriptor = FetchDescriptor<TripEntity>(predicate: #Predicate<TripEntity> { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}

// MARK: - Sheet

private struct TripEdSheet: View {
    @State private var model: TripEditorModel

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<TicketEntity> { $0.deletedAt == nil }) private var tickets: [TicketEntity]
    @Query(filter: #Predicate<TripEntity> { $0.deletedAt == nil }) private var trips: [TripEntity]
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var picking: TripEdPick?
    @State private var selectionTick = 0
    @FocusState private var focus: TripEdField?

    init(app: AppState, draft: TripDraft, editing: TripEntity?) {
        _model = State(initialValue: TripEditorModel(app: app, draft: draft, editing: editing))
    }

    var body: some View {
        let haptics = app.settings.hapticsEnabled
        NavigationStack {
            form
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaBar(edge: .bottom) {
                    TripEdSaveBar(model: model, onSave: save)
                }
        }
        .sheet(item: $picking) { pick in
            stationPicker(for: pick)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: model.mode) { _, _ in haptics }
        .sensoryFeedback(.selection, trigger: selectionTick) { _, _ in haptics }
    }

    // MARK: Layout

    private var form: some View {
        ScrollView {
            VStack(spacing: 10) {
                if showsFavorites {
                    TripEdFavoritesRow(model: model, favorites: favorites) { favorite in
                        applyFavorite(favorite)
                    }
                }
                Group {
                    TripEdRouteCard(model: model) { pick in
                        focus = nil
                        picking = pick
                    }
                    TripEdModePicker(model: model)
                    TripEdDateCard(model: model)
                    TripEdPriceCard(model: model, focus: $focus)
                    TripEdImpactCard(model: model)
                    RideEdStartCard(model: model, isExistingFavorite: existingFavorite != nil) { dismiss() }  // MARK: live
                    TripEdDetailsCard(model: model, showsCompanions: showsCompanions,
                                      isExistingFavorite: existingFavorite != nil, focus: $focus)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
            }
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .rideScreenshotScrollAnchor()  // MARK: live
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background { TripEdBackdrop() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) {
                dismiss()
            }
            .accessibilityLabel("Schließen")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Fertig") { focus = nil }
                .fontWeight(.semibold)
        }
    }

    private func stationPicker(for pick: TripEdPick) -> some View {
        NavigationStack {
            StationPickerView(
                title: pick.pickerTitle,
                selection: { station in
                    withAnimation(.snappy(duration: 0.35)) { model.setStation(station, for: pick.endpoint) }
                    selectionTick += 1
                },
                customName: { name in
                    withAnimation(.snappy(duration: 0.35)) { model.setCustomName(name, for: pick.endpoint) }
                    selectionTick += 1
                })
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        picking = nil
                    }
                    .accessibilityLabel("Abbrechen")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Derived state

    private var showsFavorites: Bool { !model.isEditing && !favorites.isEmpty }

    private var activeTicket: TicketEntity? {
        Analytics.activeTicket(in: tickets, selectedID: app.settings.selectedTicketID)
    }

    /// Companions only matter for KlimaTicket Familie (or when an edited trip already has some).
    private var showsCompanions: Bool {
        activeTicket?.variant == .familie || model.companions > 0
    }

    private var existingFavorite: FavoriteRouteEntity? {
        favorites.first { model.tripEdMatches($0) }
    }

    // MARK: Actions

    private func applyFavorite(_ favorite: FavoriteRouteEntity) {
        focus = nil
        withAnimation(.snappy(duration: 0.35)) { model.apply(favorite: favorite) }
        selectionTick += 1
    }

    private struct Outcome {
        var before: Double
        var after: Double
        var ticketID: UUID
    }

    /// Amortisation of the active ticket before/after this save (nil when the trip is outside its validity).
    private func projectedOutcome() -> Outcome? {
        guard let ticket = activeTicket,
              let impact = model.tripEdImpact(ticket: ticket, trips: trips, catalog: app.catalog),
              impact.inPeriod else { return nil }
        return Outcome(before: impact.before, after: impact.after, ticketID: ticket.id)
    }

    private func save() {
        focus = nil
        guard model.canSave else { return }
        if existingFavorite != nil { model.saveAsFavorite = false }
        let outcome = projectedOutcome()
        let wasEditing = model.isEditing
        guard let trip = model.save(context: context) else { return }

        if wasEditing {
            let route = TripEdFormat.routeTitle(from: trip.fromName, to: trip.toName, roundTrip: trip.isRoundTrip)
            app.showToast("checkmark.circle.fill", "Änderungen gespeichert", route + " · " + Format.euroPrecise(trip.totalValue))
        } else {
            var subtitle = TripEdFormat.plusEuro(trip.totalValue)
            if let outcome {
                subtitle += outcome.before >= 1 ? " · reiner Gewinn" : " · jetzt \(Format.percent(outcome.after)) amortisiert"
            }
            app.showToast("checkmark.circle.fill", "Fahrt gespeichert", subtitle)
        }

        // Crossed the summit with this trip → global celebration (consumed by the dashboard, once per ticket).
        if let outcome, outcome.before < 1, outcome.after >= 1,
           !app.settings.celebratedBreakEvenTicketIDs.contains(outcome.ticketID.uuidString) {
            app.celebrateBreakEven = true
        }
        dismiss()
    }
}

// MARK: - Save bar

/// Bottom call to action "✓ Fahrt speichern | € 49,80" in a safe-area bar (system scroll-edge effect, rides above the keyboard).
private struct TripEdSaveBar: View {
    let model: TripEditorModel
    var onSave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let hint = model.validationHint {
                Label(hint, systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button(action: onSave) {
                label
            }
            .buttonStyle(.primary)
            .disabled(!model.canSave)
            .accessibilityLabel(model.isEditing ? "Änderungen speichern" : "Fahrt speichern")
            .accessibilityValue(model.totalValue > 0 ? Format.euroPrecise(model.totalValue) : "")
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xxs)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.validationHint)
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
            Text(model.isEditing ? "Änderungen speichern" : "Fahrt speichern")
            if model.totalValue > 0 {
                Capsule()
                    .fill(Theme.onAccent.opacity(0.4))
                    .frame(width: 1, height: 22)
                Text(Format.euroPrecise(model.totalValue))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: model.totalValue))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, Theme.Spacing.m)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.totalValue)
    }
}

// MARK: - Backdrop

/// Calm sheet surface with a faint "Morgendämmerung" wash (glacier from the top, dawn glow top-right) –
/// the sky stays pale behind forms (DESIGN.md §2). Opaque with Reduce Transparency.
private struct TripEdBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.sheetBackground
            if !reduceTransparency {
                LinearGradient(colors: [Theme.glacier.opacity(colorScheme == .dark ? 0.16 : 0.12), Theme.glacier.opacity(0)],
                               startPoint: .top, endPoint: .center)
                RadialGradient(colors: [Theme.dawn.opacity(colorScheme == .dark ? 0.12 : 0.16), Theme.dawn.opacity(0)],
                               center: .topTrailing, startRadius: 0, endRadius: 380)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
