import SwiftUI
import KlimaCore

/// Step 4 (optional) – usual route: home station → destination, round trip, Vorteilscard,
/// and a live preview after how many trips the ticket pays off.
/// Motion: the cards rise in on the first visit; a picked station morphs into place, the swap arrows turn with a bouncy
/// spring and a tap; once both stations are set the preview rises in and its number counts up – the first "aha" of the
/// setup – and every option change rolls it.
struct OnbHabitsStep: View {
    @Bindable var model: OnboardingModel
    @Environment(AppState.self) private var app
    @State private var pickerTarget: OnbStationTarget?
    @State private var swapTurns = 0

    var body: some View {
        OnbPage(kicker: (OnboardingModel.Step.habits.kicker ?? "") + " · optional",
                title: "Deine Strecke",
                subtitle: "Mit deiner üblichen Strecke siehst du sofort, wann sich dein Ticket rentiert. Sie wird dein erster Favorit.") {
            routeCard
                .onbReveal(order: 1)
            optionsGroup
                .onbReveal(order: 2)
            previewCard
                .onbReveal(order: 3)
        }
        .preference(key: OnbCoveredKey.self, value: pickerTarget != nil)
        .sheet(item: $pickerTarget) { target in
            OnbStationPicker(title: target.title,
                             near: target == .to ? model.homeStation?.location : model.commuteDestination?.location,
                             excludedID: target == .to ? model.homeStation?.id : model.commuteDestination?.id) { station in
                withMotion(Motion.smooth) {
                    switch target {
                    case .from: model.homeStation = station
                    case .to: model.commuteDestination = station
                    }
                }
            }
        }
        .haptic(.selection, trigger: model.commuteBreakEvenTrips)
    }

    // MARK: Route

    private var routeCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                RouteGlyph(color: Theme.accent, endColor: Theme.summit, height: 84)
                VStack(spacing: 0) {
                    stationButton(.from)
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                    stationButton(.to)
                }
                if model.homeStation != nil || model.commuteDestination != nil {
                    swapButton
                        .motionTransition(.pop)
                }
            }
        }
    }

    private func stationButton(_ target: OnbStationTarget) -> some View {
        let station = target == .from ? model.homeStation : model.commuteDestination
        return Button {
            pickerTarget = target
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target == .from ? "Von" : "Nach")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(station?.name ?? target.placeholder)
                        .font(.headline)
                        .foregroundStyle(station == nil ? Theme.accentText : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.interpolate)
                    if let station {
                        Text(OnbStationText.subtitle(for: station))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .motionTransition(.opacity)
                    }
                }
                Spacer(minLength: Theme.Spacing.xxs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(target == .from ? "Von" : "Nach")
        .accessibilityValue(station?.name ?? "nicht gewählt")
        .accessibilityHint("Öffnet die Haltestellensuche")
    }

    private var swapButton: some View {
        Button {
            swapTurns += 1
            withMotion(Motion.bouncy) { model.swapStations() }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(Double(swapTurns) * 180))
                .motionAnimation(Motion.bouncy, value: swapTurns)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .haptic(.tap, trigger: swapTurns)
        .accessibilityLabel("Start und Ziel tauschen")
    }

    // MARK: Options

    private var vorteilscardBinding: Binding<Bool> {
        Binding(
            get: { model.discount == .vorteilscard },
            set: { isOn in withMotion(Motion.snappy) { model.discount = isOn ? .vorteilscard : .none } }
        )
    }

    private var roundTripBinding: Binding<Bool> {
        Binding(
            get: { model.commuteRoundTrip },
            set: { isOn in withMotion(Motion.snappy) { model.commuteRoundTrip = isOn } }
        )
    }

    /// The preview's number rolls with every switch (and plays the selection tick), so no extra haptic here.
    private var optionsGroup: some View {
        OnbFormGroup {
            Toggle(isOn: roundTripBinding) {
                OnbToggleLabel(symbol: "arrow.left.arrow.right", tint: Theme.dusk,
                               title: "Hin- und Rückfahrt", subtitle: "Wert wird verdoppelt")
                    .setSymbolOnEnable(model.commuteRoundTrip)
            }
            .tint(Theme.accent)
            .padding(.vertical, Theme.Spacing.s)
            OnbDivider()
            Toggle(isOn: vorteilscardBinding) {
                OnbToggleLabel(symbol: "percent", tint: Theme.dawn,
                               title: "Vorteilscard",
                               subtitle: "Einzeltickets kosten dann rund die Hälfte – wir rechnen ehrlich mit diesem Preis.")
                    .setSymbolOnEnable(model.discount == .vorteilscard)
            }
            .tint(Theme.accent)
            .padding(.vertical, Theme.Spacing.s)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewCard: some View {
        if let trips = model.commuteBreakEvenTrips, let estimate = model.commuteEstimate {
            OnbCommutePreview(trips: trips, estimate: estimate, isRoundTrip: model.commuteRoundTrip,
                              valuePerTrip: model.commuteValuePerTrip ?? estimate.fareEUR, ticketPrice: model.price)
                .motionTransition(.rise)
        } else {
            GlassCard {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "mountain.2")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.routeGradient)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Deine Vorschau")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(model.stationsAreIdentical
                             ? "Start und Ziel sind gleich – wähle ein anderes Ziel."
                             : "Wähle Start und Ziel – wir zeigen dir, nach wie vielen Fahrten sich dein Ticket rentiert.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .motionTransition(.opacity)
        }
    }
}

// MARK: - Live preview

/// "Mit dieser Strecke rentiert sich dein Ticket nach ca. · 30 Hin- & Rückfahrten" – the number as hero numeral.
private struct OnbCommutePreview: View {
    var trips: Int
    var estimate: FareEstimate
    var isRoundTrip: Bool
    var valuePerTrip: Double
    var ticketPrice: Double

    private var unit: String {
        if isRoundTrip { return trips == 1 ? "Hin- & Rückfahrt" : "Hin- & Rückfahrten" }
        return trips == 1 ? "Fahrt" : "Fahrten"
    }

    var body: some View {
        GlassCard(tint: Theme.summit) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.summitText)
                        .setSymbolEffect(.wiggle, trigger: trips)
                    Kicker(text: "Deine Vorschau", color: Theme.summitText)
                }
                Text("Mit dieser Strecke rentiert sich dein Ticket nach ca.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The aha: the number counts up when the preview first appears, then rolls with every change.
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    CountUpText(value: Double(trips), delay: 0.12) { Format.number($0) }
                        .font(Theme.Typography.priceNumeral)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                }
                Text("Danach fährst du gratis – jede weitere Fahrt ist Gewinn.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                OnbDivider(inset: 0)
                    .padding(.vertical, Theme.Spacing.xxs)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Format.euroPrecise(estimate.fareEUR)) pro Richtung")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .numericValue(estimate.fareEUR)
                        Text(estimate.explanation)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    if estimate.method == .officialTable {
                        OnbBadge(title: "ÖBB-Preis", symbol: "checkmark.seal.fill", tint: Theme.positive, textColor: Theme.positiveText)
                    }
                }
                Text("\(trips) × \(Format.euroPrecise(valuePerTrip)) ≥ \(Format.euro(ticketPrice)) Ticketpreis")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mit dieser Strecke rentiert sich dein Ticket nach ca. \(trips) \(unit).")
        .accessibilityValue("\(Format.euroPrecise(estimate.fareEUR)) pro Richtung, \(estimate.explanation)")
    }
}

// MARK: - Station picker

private enum OnbStationTarget: String, Identifiable {
    case from, to

    var id: String { rawValue }

    var title: String { self == .from ? "Heimatbahnhof" : "Übliches Ziel" }
    var placeholder: String { self == .from ? "Heimatbahnhof wählen" : "Übliches Ziel wählen" }
}

private struct OnbNearbyStation: Identifiable {
    let station: Station
    let distanceKm: Double
    var id: String { station.id }
}

private enum OnbStationText {
    static func subtitle(for station: Station) -> String {
        station.rowSubtitle
    }

    static func mode(for station: Station) -> TransportMode {
        station.primaryMode
    }
}

/// Lightweight station search (bundled station index) with an optional "near me" shortcut.
private struct OnbStationPicker: View {
    var title: String
    var near: GeoPoint?
    var excludedID: String?
    var onPick: (Station) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Station] = []
    /// The query `results` belong to – no "Keine Haltestelle gefunden" flash while a search is still running.
    @State private var resultsQuery: String?
    @State private var locator: LocationService?
    @State private var nearby: [OnbNearbyStation] = []
    @State private var isLocating = false
    @State private var locationFailed = false

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    nearbySection
                }
                Section {
                    ForEach(results) { station in
                        row(station, distanceKm: nil)
                    }
                } header: {
                    Text(trimmedQuery.isEmpty ? (near == nil ? "Wichtige Bahnhöfe" : "In der Umgebung") : "Treffer")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.sheetBackground)
            .overlay {
                if results.isEmpty && !trimmedQuery.isEmpty && resultsQuery == trimmedQuery {
                    ContentUnavailableView("Keine Haltestelle gefunden", systemImage: "magnifyingglass",
                                           description: Text("Prüfe die Schreibweise oder versuche einen kürzeren Namen."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bahnhof oder Haltestelle")
            .autocorrectionDisabled()
            .task(id: trimmedQuery) { await search() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var nearbySection: some View {
        Section {
            Button(action: locate) {
                HStack(spacing: Theme.Spacing.s) {
                    OnbIconTile(symbol: "location.fill", tint: Theme.glacier, size: 32)
                    Text(isLocating ? "Suche Haltestellen in der Nähe …" : "Haltestellen in meiner Nähe")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: Theme.Spacing.xs)
                    if isLocating {
                        ProgressView()
                    }
                }
            }
            .disabled(isLocating)
            ForEach(nearby.filter { $0.station.id != excludedID }) { item in
                row(item.station, distanceKm: item.distanceKm)
                    .motionTransition(.rise)
            }
            if locationFailed {
                Text("Standort nicht verfügbar – such einfach nach dem Namen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func row(_ station: Station, distanceKm: Double?) -> some View {
        Button {
            onPick(station)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                ModeIcon(mode: OnbStationText.mode(for: station), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(OnbStationText.subtitle(for: station))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if let distanceKm {
                    Text(Format.km(distanceKm))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(station.name)
        .accessibilityValue(OnbStationText.subtitle(for: station))
    }

    /// Ranks all ~40.000 stops off the main thread (it used to run in `body` on every keystroke and state change),
    /// with a light debounce while typing – like the trip editor's station picker.
    private func search() async {
        let q = trimmedQuery
        if !q.isEmpty {
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
        }
        let index = app.stations
        let near = near
        let excludedID = excludedID
        let found = await Task.detached(priority: .userInitiated) {
            index.search(q, limit: 40, near: near).filter { $0.id != excludedID }
        }.value
        if Task.isCancelled { return }
        results = found
        resultsQuery = q
    }

    private func locate() {
        isLocating = true
        locationFailed = false
        let service = locator ?? LocationService()
        locator = service
        Task {
            let found = await service.nearestStations(in: app.stations, limit: 4)
            withMotion(Motion.smooth) {
                nearby = found.map { OnbNearbyStation(station: $0.station, distanceKm: $0.distanceKm) }
                locationFailed = found.isEmpty
                isLocating = false
            }
        }
    }
}
