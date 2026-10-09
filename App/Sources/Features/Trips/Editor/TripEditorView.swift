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
    @Query(filter: #Predicate<FavoriteRouteEntity> { $0.deletedAt == nil }, sort: \FavoriteRouteEntity.sortIndex)
    private var favorites: [FavoriteRouteEntity]

    @State private var picking: TripEdPick?
    @State private var selectionTick = 0
    /// Saved: the button turns into "✓ Gespeichert" for a moment, then the sheet closes.
    @State private var isSaved = false
    @FocusState private var focus: TripEdField?

    init(app: AppState, draft: TripDraft, editing: TripEntity?) {
        _model = State(initialValue: TripEditorModel(app: app, draft: draft, editing: editing))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaBar(edge: .bottom) {
                    TripEdSaveBar(model: model, isSaved: isSaved, onSave: save)
                }
        }
        .sheet(item: $picking) { pick in
            stationPicker(for: pick)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .haptic(.selection, trigger: model.mode)
        .haptic(.selection, trigger: selectionTick)
        // MARK: tripmeta – suggest the purpose from the favourite / the route's last trip.
        .onAppear { model.metaApplySuggestion(favorites: favorites, context: context) }
        .onChange(of: model.metaSuggestionKey) { _, _ in
            withMotion(Motion.snappy) { model.metaApplySuggestion(favorites: favorites, context: context) }
        }
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
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                // MARK: tripmeta – purpose chips scroll edge to edge, so the section sits outside the padded group.
                MetaTripPurposeSection(model: model)
                TripEdDetailsCard(model: model, showsCompanions: showsCompanions,
                                  isExistingFavorite: existingFavorite != nil, focus: $focus)
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
                    // MARK: via – a via pick goes to its slot (TripEdViaRows.swift)
                    withMotion(Motion.smooth) {
                        if !model.tripEdSetVia(station, for: pick) { model.setStation(station, for: pick.endpoint) }
                    }
                    selectionTick += 1
                },
                customName: pick.tripEdAllowsCustomName ? { name in
                    withMotion(Motion.smooth) { model.setCustomName(name, for: pick.endpoint) }
                    selectionTick += 1
                } : nil)
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
        withMotion(Motion.smooth) { model.apply(favorite: favorite) }
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
              let impact = model.tripEdImpact(ticket: ticket, context: context),
              impact.inPeriod else { return nil }
        return Outcome(before: impact.before, after: impact.after, ticketID: ticket.id)
    }

    private func save() {
        focus = nil
        guard !isSaved, model.canSave else { return }
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
        // The toast plays the success haptic; the button confirms in place, then the sheet goes.
        withMotion(Motion.bouncy) { isSaved = true }
        let pause: Duration = MotionPolicy.isStatic ? .zero : .milliseconds(MotionPolicy.prefersReducedMotion ? 300 : 420)
        Task { @MainActor in
            try? await Task.sleep(for: pause)
            dismiss()
        }
    }
}

// MARK: - Save bar

/// Bottom call to action "✓ Fahrt speichern | € 49,80" in a safe-area bar (system scroll-edge effect, rides above the keyboard).
/// The value rolls with every change of the form; after saving, the label morphs into "✓ Gespeichert" (check bounces).
private struct TripEdSaveBar: View {
    let model: TripEditorModel
    let isSaved: Bool
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if let hint = model.validationHint, !isSaved {
                Label(hint, systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
                    .motionTransition(.lift)
            }
            Button(action: onSave) {
                label
            }
            .buttonStyle(.primary)
            .disabled(!model.canSave && !isSaved)
            .allowsHitTesting(!isSaved)
            .accessibilityLabel(isSaved ? "Gespeichert" : (model.isEditing ? "Änderungen speichern" : "Fahrt speichern"))
            .accessibilityValue(model.totalValue > 0 && !isSaved ? Format.euroPrecise(model.totalValue) : "")
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xxs)
        .motionAnimation(Motion.smooth, value: model.validationHint)
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: isSaved ? "checkmark.circle.fill" : "checkmark")
                .font(.headline.weight(.bold))
                .symbolReplaceTransition()
                .symbolBounce(on: isSaved)
            Text(isSaved ? "Gespeichert" : (model.isEditing ? "Änderungen speichern" : "Fahrt speichern"))
                .contentTransition(.opacity)
            if model.totalValue > 0 && !isSaved {
                Capsule()
                    .fill(Theme.onAccent.opacity(0.4))
                    .frame(width: 1, height: 22)
                    .transition(.opacity)
                Text(Format.euroPrecise(model.totalValue))
                    .monospacedDigit()
                    .numericValue(model.totalValue)
                    .transition(.opacity)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, Theme.Spacing.m)
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
