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
        // MARK: integrate-radar3 – VoiceOver names the sheet the button opens („Filter & Darstellung“), and whether a filter holds
        .accessibilityLabel(RadarModesText.sheetTitle)
        .accessibilityValue(model.filter.isActive ? "Filter aktiv" : "kein Filter")
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
            if model.filter.isActive {   // MARK: radarmodes – a stored filter is always visible
                RadarActiveFilterRow(filter: model.filter, onOpen: { showsFilter = true },
                                     onClear: { withMotion(Motion.smooth) { model.filter = RadarFilter() } })
                    .motionTransition(.drop)
            }
            if travel.isAway {   // MARK: radartime – "Zeitreise · Prognose aus dem Fahrplan"
                RadarTimeBanner(travel: travel).motionTransition(.drop)
            }
        }
        .motionAnimation(Motion.smooth, value: travel.isAway)
        .motionAnimation(Motion.smooth, value: model.filter.isActive)   // MARK: radarmodes
        // MARK: radar2-fix-radarmodes – the bars over the map grow with the text up to AX2 (the chips up to AX1, as the layer bar and the Cockpit's
        // switcher): at AX5 the field, two chips and the bottom stack left the map a strip (radarModesAX5).
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                // MARK: radarmodes – buses, Bims and U-Bahnen too; radar2-fix-radarmodes – from xLarge on the short one: the long one was shrunk to
                // fit the field (at AX5 it stood at about 18 pt next to a 53-pt magnifier)
                TextField(heatTypeSize <= .large ? RadarModesText.searchPlaceholder : RadarModesText.searchPlaceholderShort, text: $query)
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
                    Text(RadarModesText.searchNoMatch)   // MARK: radarmodes
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
                radar2TopBarItems   // MARK: radar2
                ForEach(RadarMode.allCases) { mode in
                    Chip(title: mode.title, symbol: mode.symbol, isSelected: model.modes.contains(mode)) {
                        toggleMode(mode)   // MARK: radarmodes – stored per device
                    }
                    .modifier(RadarModeChipZoom(mode: mode, isOn: model.modes.contains(mode), outOfZoom: model.cityOutOfZoom))   // MARK: radarmodes
                    .accessibilityShowsLargeContentViewer { Label(mode.title, systemImage: mode.symbol) }   // MARK: radar2-fix-radarmodes
                }
            }
            .padding(.horizontal, Theme.Spacing.cardGutter)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // MARK: radar2-fix-radarmodes – a row of controls: up to AX1, long press shows one large
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()   // MARK: radarmodes – the chips' zoom badge reaches over their edge
        .haptic(.selection, trigger: model.modes)   // MARK: radarmodes
    }

    // MARK: Status

    var statusBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if heatOn { heatPanel }   // MARK: radarheat – the summary panel, above the layer bar
            radar2Panel   // MARK: radar2 – a part's panel (radarmine's stop panel)
            // MARK: radar2-fix-radarmodes – the lines and controls of the map grow with the text up to AX2 (the layer bar up to AX1), like the Zeitreise's
            // chip under them: at AX5 the stack was twice its area, and the counts, the notes and the chip were only reached by scrolling (radarModesAX5).
            Group {
            if !travel.isOpen && !radar2PanelIsOpen { mapLayerPanel }   // MARK: radartime, radar2 – an open card leaves the map room: the layer bar waits
            if layers.isOn(.trains) || layers.isOn(.punctuality), let reason = app.live.timetableUnavailable {   // MARK: radarheat – the Pünktlichkeit layer needs the live data as well
                trainsOffNotice(reason)
            }
            // The train status is only shown while trains are on: with the layer off no request is sent and nothing is pending.
            if loadsRadar && !travel.isAway {   // MARK: radarheat – trains or the Pünktlichkeit layer; radartime – the Zeitreise has its own status
                if model.lowPower {
                    PlannerNoticeCard(symbol: "battery.25percent", title: "Stromspar-Modus",
                                      message: "Das Radar aktualisiert sich nicht, solange der Stromspar-Modus an ist.",
                                      actionTitle: "Jetzt aktualisieren") {
                        model.refreshNow()
                    }
                }
                if case .failed(let message) = model.load {
                    PlannerNoticeCard(symbol: "wifi.exclamationmark", title: "Radar pausiert", message: message,
                                      actionTitle: "Erneut versuchen") {
                        model.refreshNow()
                    }
                }
                if focusMissing {
                    Text("Dieser Zug ist gerade nicht auf der Karte. Zoom heraus oder probier es später noch einmal.")
                        .radarHint()
                }
                if !heatOn { RadarStatusCard(model: model, onLegend: { showsLegend = true }) }   // MARK: radarheat – the panel has its own age and notes; radarmodes – „Legende“
            }
            radar2StatusNotes   // MARK: radar2 – outside the block above: each note decides itself when it shows (also while away)
            if !model.route.isEmpty {
                Button("Route ausblenden") {
                    model.route = []
                    model.routeTripID = nil
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
            }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // MARK: radar2-fix-radarmodes
            if timeAvailable { RadarTimePanel(travel: travel) }   // MARK: radartime – the clock chip, expanding to the scrubber
            // MARK: radarmodes – where the clock chip sits; radar2-review-radarmine – not under the „Meine“ panel (the clock would close it anyway; the
            // hint took the map another line where the stop's arrivals should be)
            else if timeHintShown && !radar2PanelIsOpen { Text(RadarModesText.timeTravelHint).radarHint() }
        }
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .frame(maxWidth: .infinity)
        .motionAnimation(Motion.smooth, value: model.load)
    }
}

/// "923 Züge · vor 12 s": the vehicles in the visible area and the age of the oldest answer behind them, and under it what is
/// true about the tiles (a cut-off tile, a partial failure, tiles still loading, a refresh slower than 25 s: docs/OEBB_LIVE.md §R11).
/// One glass card: text straight on the map would not be legible between the markers. A view of its own: its age ticks every
/// second, and only this card is re-evaluated for it, not the map with its markers.
/// MARK: radar2-fix-radarmodes – at the accessibility sizes (up to AX2, `statusBar`) the card takes the full width, the number and the age stand on
/// two lines without the symbol („142“ stood alone over „Fahrzeuge · vor 9 s“), „Legende“ sits beside them and the counts and notes use the width.
struct RadarStatusCard: View {
    var model: RadarModel
    /// MARK: radarmodes – opens „Legende“; nil: no button.
    var onLegend: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let text: String
        var spoken: String
        if let pill = model.pillText {
            text = pill
            let age = model.status.oldestAnswerAgeOfBothLanes.map { ", aktualisiert \(RadarStatusText.spokenAge($0))" } ?? ""   // MARK: radarmodes
            spoken = model.summary + age
        } else {
            text = model.load == .loading ? "Lade Fahrzeuge …" : "Noch keine Positionen"
            spoken = text
        }
        // MARK: radarmodes – the counts per mode while a city mode is on (they add up to the pill); radar2-fix-radarmodes – with a filter only the
        // modes with a vehicle on the map
        let counts = model.statusModeCounts
        if let counts { spoken += ". " + counts.spoken }
        let notes = model.notes
        if !notes.isEmpty { spoken += ". " + notes.joined(separator: " ") }
        let large = typeSize.isAccessibilitySize
        return Group {
            if large {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        largePill(text).accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityAddTraits(.updatesFrequently)
                        Spacer(minLength: 0)
                        legendButton
                    }
                    details(counts: counts, notes: notes, alignment: .leading)
                        .accessibilityHidden(true)   // the pill's label says it all, as at the other sizes
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    VStack(spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text(text).monospacedDigit()   // the age ticks every second: the card keeps its width
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        details(counts: counts, notes: notes, alignment: .center)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken)
                    .accessibilityAddTraits(.updatesFrequently)
                    legendButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// „142 Fahrzeuge“ over „vor 9 s“: never a number alone on a line. Always two lines at these sizes: one line when it fits would jump between one
    /// and two lines as the age ticks („vor 9 s“, „vor 10 s“) at the sizes where it just fits.
    private func largePill(_ text: String) -> some View {
        let parts = text.components(separatedBy: " · ")   // `RadarStatusText.pill`: count and noun, then the age
        return VStack(alignment: .leading, spacing: 0) {
            Text(parts[0])
            if parts.count > 1 { Text(parts.dropFirst().joined(separator: " · ")).foregroundStyle(Theme.textSecondary) }
        }
        .monospacedDigit()
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
    }

    @ViewBuilder private func details(counts: RadarModeCounts?, notes: [String], alignment: TextAlignment) -> some View {
        if let counts { RadarModeCountsRow(counts: counts).padding(.vertical, 1) }
        ForEach(notes, id: \.self) { note in
            Text(note)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var legendButton: some View {
        if let onLegend {
            Button(action: onLegend) {
                Image(systemName: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle().inset(by: -11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(RadarModesText.legendTitle)
        }
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
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // MARK: radar2-fix-radarmodes – a line over the map, like the status card
    }
}
