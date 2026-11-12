import SwiftUI
import MapKit
import SwiftData
import KlimaCore

// Controls and status of the Zug-Radar: top bar, search, mode chips, status bar (split from RadarView.swift).

extension RadarView {
    // MARK: Controls

    var filterButton: some View {
        Button { showsFilter = true } label: {
            Image(systemName: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(model.filter.isActive ? "aktiv" : "aus")
    }

    var styleMenu: some View {
        Menu {
            Picker("Kartenstil", selection: $styleRaw) {
                ForEach(RadarMapStyle.allCases) { style in
                    Label(style.title, systemImage: style.symbol).tag(style.rawValue)
                }
            }
        } label: {
            Image(systemName: mapStyle.symbol)
        }
        .accessibilityLabel("Kartenstil")
        .accessibilityValue(mapStyle.title)
    }

    var topBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            searchField
            modeChips
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Zugnummer oder Linie, z. B. RJX 66", text: $query)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .font(.body)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Suche löschen")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            if searchFocused || !query.isEmpty, let parsed = RadarSearchQuery(query) {
                suggestionCard(for: parsed)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
    }

    private func suggestionCard(for parsed: RadarSearchQuery) -> some View {
        let matches = RadarSearch.suggestions(for: parsed, in: model.knownVehicles)
        return GlassCard(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 4) {
                if matches.isEmpty {
                    Text("Kein Zug in den letzten Minuten gefunden. Zoom näher heran oder probier eine andere Nummer.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(matches) { vehicle in
                    Button { choose(vehicle) } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            if let line = vehicle.line {
                                PlannerLinePlate(line: line, size: .s)
                            }
                            Text(vehicle.line.map { LinePresentation.title($0) } ?? "Zug")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 8)
                            if let direction = vehicle.direction {
                                Text("nach \(direction)")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func choose(_ vehicle: RadarVehicle) {
        query = ""
        searchFocused = false
        model.selectedTripID = vehicle.tripID
        sheetVehicle = vehicle
        center(on: vehicle.tripID)
    }

    private var modeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(RadarMode.allCases) { mode in
                    Chip(title: mode.title, symbol: mode.symbol, isSelected: model.modes.contains(mode)) {
                        model.toggle(mode)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Status

    var statusBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            mapLayerPanel
            if layers.isOn(.trains), let reason = app.live.timetableUnavailable {
                trainsOffNotice(reason)
            }
            // The train status is only shown while trains are on: with the layer off no request is sent and nothing is pending.
            if trainsOn {
                if model.lowPower {
                    PlannerNoticeCard(symbol: "battery.25percent", title: "Stromspar-Modus",
                                      message: "Das Radar aktualisiert sich nicht, solange der Stromspar-Modus an ist.",
                                      actionTitle: "Jetzt aktualisieren") {
                        Task { if let s = radarService { await model.refreshNow(s) } }
                    }
                }
                if case .failed(let message) = model.load {
                    PlannerNoticeCard(symbol: "wifi.exclamationmark", title: "Radar pausiert", message: message,
                                      actionTitle: "Erneut versuchen") {
                        Task { if let s = radarService { await model.refreshNow(s) } }
                    }
                }
                if focusMissing {
                    Text("Dieser Zug ist gerade nicht auf der Karte. Zoom heraus oder probier es später noch einmal.")
                        .radarHint()
                }
                statusPill
            }
            if !model.route.isEmpty {
                Button("Route ausblenden") {
                    model.route = []
                    model.routeTripID = nil
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .frame(maxWidth: .infinity)
        .motionAnimation(Motion.smooth, value: model.load)
    }

    /// "923 Züge · vor 12 s": the vehicles in the visible area and the age of the oldest answer behind them, and under it what is
    /// true about the tiles (a cut-off tile, a partial failure, a refresh slower than 25 s: docs/OEBB_LIVE.md §R11). One glass
    /// card: text straight on the map would not be legible between the markers.
    private var statusPill: some View {
        let text: String
        var spoken: String
        if let pill = model.pillText {
            text = pill
            let age = model.status.oldestAnswerAge.map { ", aktualisiert \(RadarStatusText.spokenAge($0))" } ?? ""
            spoken = model.summary + age
        } else {
            text = model.load == .loading ? "Lade Fahrzeuge …" : "Noch keine Positionen"
            spoken = text
        }
        let notes = model.notes
        if !notes.isEmpty { spoken += ". " + notes.joined(separator: " ") }
        return VStack(spacing: 2) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text(text).monospacedDigit()   // the age ticks every second: the card keeps its width
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// A short hint over the map: caption text on a glass capsule, so it stays legible between markers and labels.
    func radarHint() -> some View {
        self
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
