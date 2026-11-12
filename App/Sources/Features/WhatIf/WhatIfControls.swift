import SwiftUI
import KlimaCore

/// Which station of which route the picker sheet is choosing.
struct WhatIfPick: Identifiable, Equatable {
    var routeID: UUID
    var isFrom: Bool
    var id: String { "\(routeID.uuidString)-\(isFrom ? "von" : "nach")" }
}

// MARK: - Assumptions

/// „Eigene Annahmen“: presets, up to three routes, ticket kind and start month.
struct WhatIfAssumptionsControls: View {
    @Bindable var model: WhatIfModel
    let result: WhatIfResult
    var onPick: (WhatIfPick) -> Void
    var onAddRoute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            presetChips
            ForEach($model.assumptions.routes) { $route in
                WhatIfRouteCard(route: $route,
                                index: model.assumptions.routes.firstIndex { $0.id == route.id } ?? 0,
                                fare: result.routeFares.first { $0.id == route.id },
                                onPick: { isFrom in onPick(WhatIfPick(routeID: route.id, isFrom: isFrom)) },
                                onSwap: { withMotion(Motion.bouncy) { model.swapStations(routeID: route.id) } },
                                onRemove: { withMotion(Motion.smooth) { model.removeRoute(id: route.id) } })
                    .motionTransition(.rise)
            }
            if model.canAddRoute {
                Button(action: onAddRoute) {
                    Label("Strecke hinzufügen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityHint("Noch \(WhatIfLimits.maxRoutes - model.assumptions.routes.count) möglich")
            }
            WhatIfTicketKindCard(variant: $model.assumptions.variant, ownVariant: nil) {
                startMonthMenu
            }
        }
    }

    private var presetChips: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Kicker(text: "Beispiele")
                .padding(.horizontal, Theme.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(WhatIfPreset.all) { preset in
                        Chip(title: preset.title, symbol: preset.symbol, isSelected: model.matches(preset)) {
                            withMotion(Motion.smooth) { model.apply(preset) }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.Spacing.cardGutter, for: .scrollContent)
            .padding(.horizontal, -Theme.Spacing.cardGutter)
        }
    }

    private var startMonthMenu: some View {
        Menu {
            Picker("Startmonat", selection: $model.startOffset) {
                ForEach(0..<12, id: \.self) { offset in
                    Text(model.startLabel(forOffset: offset)).tag(offset)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                Text("Start \(model.startLabel(forOffset: model.startOffset))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Startmonat des Tickets")
        .accessibilityValue(model.startLabel(forOffset: model.startOffset))
    }
}

// MARK: - Route card

/// One route: two stations, the price of one trip, how often per month (stepper and slider), the class.
struct WhatIfRouteCard: View {
    @Binding var route: WhatIfRoute
    let index: Int
    let fare: WhatIfRouteFare?
    var onPick: (Bool) -> Void
    var onSwap: () -> Void
    var onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var numeralSize: CGFloat = 34

    private var isLarge: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .center) {
                    Kicker(text: "Strecke \(index + 1)")
                    Spacer(minLength: Theme.Spacing.xs)
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Strecke \(index + 1) entfernen")
                }
                .padding(.bottom, -Theme.Spacing.xs)
                stations
                fareLine
                Divider().overlay(Theme.separator)
                tripsRow
                slider
                GlassSegmentedPicker(selection: $route.travelClass, options: TravelClass.allCases) { Text($0.displayName) }
                    .accessibilityLabel("Klasse")
            }
        }
    }

    // MARK: Stations

    private var stations: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            if !isLarge {
                RouteGlyph(height: 92)
            }
            VStack(alignment: .leading, spacing: 0) {
                stationButton(title: "Von", name: fare?.fromName ?? "", isFrom: true)
                Divider().overlay(Theme.separator)
                stationButton(title: "Nach", name: fare?.toName ?? "", isFrom: false)
            }
            Button(action: onSwap) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start und Ziel tauschen")
        }
    }

    private func stationButton(title: String, name: String, isFrom: Bool) -> some View {
        Button { onPick(isFrom) } label: {
            HStack(spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(name.isEmpty ? "Station wählen" : name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(name.isEmpty ? Theme.accentText : Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(name.isEmpty ? "noch nicht gewählt" : name)")
        .accessibilityHint("Öffnet die Stationssuche")
    }

    // MARK: Price

    @ViewBuilder
    private var fareLine: some View {
        Label {
            Text(fareText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: fare?.isPriced == true ? "eurosign.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(fare?.isPriced == true ? Theme.accent : Theme.summit)
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
    }

    private var fareText: String {
        guard let fare else { return "Wähle Start und Ziel." }
        switch fare.status {
        case .priced:
            let source: String
            switch fare.method {
            case .officialTable?: source = "ÖBB-Tarif"
            case .cityTicket?: source = "Stadttarif"
            default: source = "Modell nach Entfernung"
            }
            return "\(Format.euroPrecise(fare.farePerTrip)) pro Fahrt · \(source) · \(route.travelClass.displayName)"
        case .unknownStation:
            return fare.fromName.isEmpty || fare.toName.isEmpty ? "Wähle Start und Ziel." : "Diese Station kennen wir nicht mehr."
        case .sameStation: return "Start und Ziel sind dieselbe Station."
        case .noFare: return "Für diese Strecke finden wir keinen Preis."
        }
    }

    // MARK: Trips per month

    private var tripsBinding: Binding<Int> {
        Binding(get: { route.clampedTrips }, set: { route.tripsPerMonth = min(max($0, 0), WhatIfLimits.maxTripsPerMonth) })
    }

    private var sliderBinding: Binding<Double> {
        Binding(get: { Double(route.clampedTrips) }, set: { route.tripsPerMonth = Int($0.rounded()) })
    }

    private var tripsRow: some View {
        let trips = route.clampedTrips
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) { tripsParts(trips) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { tripsParts(trips) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fahrten pro Monat")
        .accessibilityValue(WhatIfText.perMonth(Double(trips)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: tripsBinding.wrappedValue = trips + 1
            case .decrement: tripsBinding.wrappedValue = trips - 1
            @unknown default: break
            }
        }
        .haptic(.selection, trigger: trips)
    }

    @ViewBuilder
    private func tripsParts(_ trips: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(trips)")
                .font(.system(size: numeralSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .numericValue(Double(trips))
            Text("Fahrten pro Monat")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text("1 Fahrt = 1 Richtung")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        if !isLarge { Spacer(minLength: Theme.Spacing.xs) }
        Stepper("Fahrten pro Monat", value: tripsBinding, in: 0...WhatIfLimits.maxTripsPerMonth)
            .labelsHidden()
    }

    private var slider: some View {
        Slider(value: sliderBinding, in: 0...Double(WhatIfLimits.maxTripsPerMonth), step: 1) {
            Text("Fahrten pro Monat")
        } minimumValueLabel: {
            Text("0").font(.caption2).foregroundStyle(Theme.textSecondary)
        } maximumValueLabel: {
            Text("\(WhatIfLimits.maxTripsPerMonth)").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .tint(Theme.accent)
        .accessibilityHidden(true)   // the stepper above is the adjustable element
    }
}

// MARK: - Real data

/// „Meine Fahrten“: the slider ×0,5 … ×2, the three toggles and the ticket kind.
struct WhatIfHistoryControls: View {
    @Bindable var model: WhatIfModel
    let source: WhatIfSource
    let result: WhatIfResult

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sliderCard
            togglesCard
            WhatIfTicketKindCard(variant: $model.history.variant, ownVariant: source.ticketVariant) { EmptyView() }
        }
    }

    // MARK: Slider

    private var volume: Double { model.history.clampedVolume }

    private var sliderCard: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Kicker(text: "Wie viel fährst du?")
                    Spacer(minLength: Theme.Spacing.xs)
                    if abs(volume - 1) > 0.001 {
                        Button("Wie bisher") {
                            withMotion(Motion.snappy) { model.history.volumeFactor = 1 }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.bottom, -Theme.Spacing.xs)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(WhatIfText.factor(volume))
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .numericValue(volume)
                    Text("deiner bisherigen Fahrten")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Slider(value: $model.history.volumeFactor, in: WhatIfLimits.volumeRange, step: 0.05) {
                    Text("Fahrten")
                } minimumValueLabel: {
                    Text("×0,5").font(.caption2).foregroundStyle(Theme.textSecondary)
                } maximumValueLabel: {
                    Text("×2").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.accent)
                .accessibilityLabel("Fahrten im Verhältnis zu bisher")
                .accessibilityValue("\(WhatIfText.factor(volume)), \(WhatIfText.perMonth(result.tripsPerMonth))")
                .haptic(.selection, trigger: Int((volume * 20).rounded()))
                Text(basisText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Grundlage: 79 Fahrten seit 4. Mär." – honest about the window and about scaling to a year.
    private var basisText: String {
        let baseline = source.baseline
        var text = "Grundlage: \(WhatIfText.trips(source.tripCount))"
        text += baseline.observedDays >= 360 ? " der letzten 12 Monate" : " seit \(Format.dayMonth(baseline.windowStart))"
        if baseline.isAnnualized {
            text += ", aufs Jahr hochgerechnet (\(WhatIfText.factor(baseline.annualizationFactor)))"
        }
        if source.tripCount < WhatIfLimits.minHistoryTrips {
            text += ". Nur wenige Fahrten – die Rechnung ist grob."
        }
        return text
    }

    // MARK: Toggles

    private var togglesCard: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                WhatIfToggleRow(symbol: "sun.max.fill", tint: Theme.gold, title: "Juli und August ohne Fahrten",
                                subtitle: "Ferien: in diesen Monaten fährst du nicht",
                                isOn: Binding(get: { model.excludesSummer }, set: { model.excludesSummer = $0 }))
                Divider().overlay(Theme.separator)
                WhatIfToggleRow(symbol: "map.fill", tint: Theme.glacier, title: "Nur ein Bundesland",
                                subtitle: regionSubtitle, isOn: regionBinding)
                    .disabled(source.regions.isEmpty)
                if let selected = model.history.regionFilter, !source.regions.isEmpty {
                    regionChips(selected: selected)
                        .motionTransition(.rise)
                }
                Divider().overlay(Theme.separator)
                WhatIfToggleRow(symbol: "sofa.fill", tint: Theme.dusk, title: "Mit 1. Klasse",
                                subtitle: "Einzeltickets in der 1. Klasse, KlimaTicket Ö mit Upgrade",
                                isOn: $model.history.useFirstClass)
            }
        }
    }

    private var regionBinding: Binding<Bool> {
        Binding(get: { model.history.regionFilter != nil },
                set: { on in model.history.regionFilter = on ? source.regions.first?.state.rawValue : nil })
    }

    private var regionSubtitle: String {
        if source.regions.isEmpty { return "Keine deiner Fahrten liegt in nur einem Bundesland" }
        if let code = model.history.regionFilter, let state = FederalState(rawValue: code) {
            return "Nur Fahrten innerhalb von \(state.displayName) zählen"
        }
        return "Nur Fahrten innerhalb eines Bundeslands zählen"
    }

    private func regionChips(selected: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(source.regions) { region in
                    Chip(title: "\(region.state.displayName) · \(region.count)", isSelected: region.state.rawValue == selected) {
                        withMotion(Motion.snappy) { model.history.regionFilter = region.state.rawValue }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

/// Icon tile, title, one line of explanation and a switch – at least 44 pt high.
struct WhatIfToggleRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.16), in: .rect(cornerRadius: Theme.Radius.modeTile - 2, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .frame(minHeight: 52)
        .haptic(.selection, trigger: isOn)
    }
}

// MARK: - Ticket kind

/// Klassik · Jugend · Senior (plus the user's own variant when it is another one), with room for one more control.
struct WhatIfTicketKindCard<Extra: View>: View {
    @Binding var variant: TicketVariant
    let ownVariant: TicketVariant?
    @ViewBuilder var extra: Extra

    private var variants: [TicketVariant] {
        var list: [TicketVariant] = [.klassik, .jugend, .senior]
        if let ownVariant, !list.contains(ownVariant) { list.append(ownVariant) }
        return list
    }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Kicker(text: "Ticketart")
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(variants) { option in
                            Chip(title: option.displayName, isSelected: option == variant) {
                                withMotion(Motion.snappy) { variant = option }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -2)
                extra
            }
        }
    }
}
