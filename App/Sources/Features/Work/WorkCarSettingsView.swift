import SwiftUI
import KlimaCore

/// Einstellungen › Auto-Vergleich: how the car alternative is valued (Kilometergeld, Nur Sprit, Vollkosten) and the
/// "Auto abgeschafft" fixed costs. Grouped list on the pale sky, like the rest of the settings.
struct WorkCarSettingsView: View {
    /// Shows a link to the "Öffis vs. Auto" screen (hidden when pushed from that screen).
    var showsDetailLink: Bool = true

    @Environment(AppState.self) private var app
    @State private var resetTrigger = 0

    var body: some View {
        @Bindable var settings = WorkSettings.shared
        List {
            modeSection(settings)
            parameterSection(settings)
            fixedCostsSection(settings)
            assumptionsSection
            if showsDetailLink {
                Section {
                    NavigationLink {
                        WorkCarView()
                    } label: {
                        SetRowLabel(title: "Öffis vs. Auto ansehen", subtitle: "Kosten-Verlauf, Break-even, CO₂ und Zeit",
                                    symbol: "chart.line.uptrend.xyaxis", tint: Theme.pine)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            if !settings.isCarAtDefaults {
                Section {
                    Button {
                        withAnimation(.snappy) { settings.resetCar() }
                        resetTrigger += 1
                    } label: {
                        Label("Standardwerte wiederherstellen", systemImage: "arrow.uturn.backward")
                            .font(.body.weight(.medium))
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Theme.Spacing.l)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { SetBackdrop() }
        .navigationTitle("Auto-Vergleich")
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.selection, trigger: settings.carMode) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: settings.carGivenUp) { _, _ in app.settings.hapticsEnabled }
        .sensoryFeedback(.success, trigger: resetTrigger) { _, _ in app.settings.hapticsEnabled }
    }

    // MARK: Mode

    private func modeSection(_ settings: WorkSettings) -> some View {
        Section {
            ForEach(CarCostMode.allCases) { mode in
                modeRow(mode, settings: settings)
                    .listRowBackground(Theme.surface)
            }
        } header: {
            SetSectionHeader(title: "So rechnest du das Auto")
        } footer: {
            SetFooter(text: "Andere Rechner nutzen noch das alte Kilometergeld von € 0,42. Seit 1. Jänner 2025 gilt für Pkw amtlich € 0,50 pro Kilometer.")
        }
    }

    private func modeRow(_ mode: CarCostMode, settings: WorkSettings) -> some View {
        let isSelected = settings.carMode == mode
        return Button {
            withAnimation(.snappy) { settings.carMode = mode }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                SetIconTile(symbol: mode.symbol, tint: mode.tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(mode.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(WorkFormat.perKm(rate(mode, settings: settings)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? Theme.accentText : Theme.textSecondary)
                    }
                    Text(mode.explanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.displayName), \(WorkFormat.perKm(rate(mode, settings: settings)))")
        .accessibilityHint(mode.explanation)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func rate(_ mode: CarCostMode, settings: WorkSettings) -> Double {
        var profile = settings.carProfile(catalog: app.catalog)
        profile.mode = mode
        return profile.costPerKm
    }

    // MARK: Parameters

    @ViewBuilder
    private func parameterSection(_ model: WorkSettings) -> some View {
        @Bindable var settings = model
        switch settings.carMode {
        case .kilometergeld:
            Section {
                LabeledContent {
                    Text(WorkFormat.perKm(app.catalog.kilometergeldEUR > 0 ? app.catalog.kilometergeldEUR : CarProfile.defaultKilometergeld))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                } label: {
                    SetRowLabel(title: "Amtliches Kilometergeld", subtitle: "Pkw · gültig seit 1. Jänner 2025",
                                symbol: "building.columns.fill", tint: Theme.glacier)
                }
                .listRowBackground(Theme.surface)
            } footer: {
                SetFooter(text: "Das Kilometergeld ist eine realistische Untergrenze der echten Autokosten. Mitfahrende (€ 0,15/km) zählt KlimaBilanz nicht dazu.")
            }
        case .fuelOnly:
            Section {
                Group {
                    WorkDecimalField(title: "Verbrauch", symbol: "gauge.with.dots.needle.67percent", tint: Theme.dawn,
                                     value: $settings.litersPer100Km, unit: "l/100 km", fractionDigits: 1, range: 2...25)
                    WorkDecimalField(title: "Spritpreis", symbol: "fuelpump.fill", tint: Theme.dawn,
                                     value: $settings.fuelPricePerLiter, unit: "€/l", fractionDigits: 2, range: 0.5...4)
                    LabeledContent {
                        Text(WorkFormat.perKm(settings.carProfile(catalog: app.catalog).fuelCostPerKm))
                            .font(.body.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                    } label: {
                        Text("Ergibt")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Dein Auto")
            } footer: {
                SetFooter(text: "Beispielwerte: 6,5 l auf 100 km und € 1,65 pro Liter. Trag ein, was dein Auto wirklich braucht.")
            }
        case .fullCost:
            Section {
                WorkDecimalField(title: "Kosten pro km", symbol: "chart.pie.fill", tint: Theme.dusk,
                                 value: fullCostBinding(settings), unit: "€/km", fractionDigits: 2, range: 0.05...3)
                    .listRowBackground(Theme.surface)
            } header: {
                SetSectionHeader(title: "Deine Vollkosten")
            } footer: {
                SetFooter(text: "Vollkosten enthalten Wertverlust, Versicherung, Steuer, Service, Reifen und Sprit. Der ÖAMTC-Autokostenrechner kommt für Kompakt- und Mittelklasse meist auf € 0,45–0,60 pro Kilometer.")
            }
        }
    }

    private func fullCostBinding(_ settings: WorkSettings) -> Binding<Double> {
        Binding(get: { settings.effectiveFullCost(catalog: app.catalog) },
                set: { settings.fullCostPerKm = $0 })
    }

    // MARK: Fixed costs

    private func fixedCostsSection(_ model: WorkSettings) -> some View {
        @Bindable var settings = model
        return Section {
            Group {
                Toggle(isOn: $settings.carGivenUp.animation(.snappy)) {
                    SetRowLabel(title: "Auto abgeschafft", subtitle: "Eingesparte Fixkosten anteilig dazurechnen",
                                symbol: "car.side.fill", tint: Theme.pine)
                }
                if settings.carGivenUp {
                    WorkDecimalField(title: "Versicherung & Steuer", symbol: "checkmark.shield.fill", tint: Theme.glacier,
                                     value: $settings.insurance, unit: "€/Jahr", range: 0...20_000)
                    WorkDecimalField(title: "Vignette", symbol: "road.lanes", tint: Theme.dusk,
                                     value: $settings.vignette, unit: "€/Jahr", range: 0...1_000)
                    WorkDecimalField(title: "Parken", symbol: "parkingsign.circle.fill", tint: Theme.glacier,
                                     value: $settings.parking, unit: "€/Jahr", range: 0...20_000)
                    WorkDecimalField(title: "Service & Pickerl", symbol: "wrench.and.screwdriver.fill", tint: Theme.dawn,
                                     value: $settings.service, unit: "€/Jahr", range: 0...20_000)
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Format.euro(settings.fixedCosts.total, decimals: 0)) pro Jahr")
                                .font(.body.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                            Text("\(Format.euroPrecise(settings.fixedCosts.total / 365)) pro Tag")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } label: {
                        Text("Zusammen")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if settings.carMode != .fuelOnly {
                        doubleCountingHint(settings)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Ohne Auto")
        } footer: {
            SetFooter(text: settings.carGivenUp
                      ? "Die Fixkosten laufen Tag für Tag mit – egal, wie viel du fährst. Vignette 2026: € \(Format.number(CarFixedCosts.vignette2026, decimals: 2)) (ASFINAG). Die übrigen Werte sind Beispiele für einen Kompaktwagen."
                      : "Hast du dein Auto für das KlimaTicket aufgegeben? Laut KlimaTicket-Report haben das 11 % der Befragten getan.")
        }
    }

    private func doubleCountingHint(_ settings: WorkSettings) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label {
                Text("\(settings.carMode.displayName) enthält schon anteilige Fixkosten – zusammen mit „Auto abgeschafft“ würden sie doppelt zählen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.summit)
            }
            Button {
                withAnimation(.snappy) { settings.carMode = .fuelOnly }
            } label: {
                Label("Auf „Nur Sprit“ umstellen", systemImage: "fuelpump.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: Assumptions

    private var assumptionsSection: some View {
        Section {
            Group {
                WorkFactRow(symbol: "road.lanes", tint: Theme.dusk, title: "Straßen-km = Bahn-km × 1,15",
                            detail: "Deine Fahrten kennen Bahn- oder Linienkilometer. Mit dem Auto kommen Wege zum Ziel, Umfahrungen und Parkplatzsuche dazu.")
                WorkFactRow(symbol: "leaf.fill", tint: Theme.pine, title: "CO₂: \(Format.number(app.catalog.emissions.car)) g pro Pkw-km",
                            detail: "Umweltbundesamt, Pkw allein unterwegs, inkl. Vorkette – verglichen mit deinen Öffis je Verkehrsmittel.")
                WorkFactRow(symbol: "steeringwheel", tint: Theme.dusk, title: "Zeit am Steuer",
                            detail: "Durchschnittstempo je Strecke: 30 km/h im Ort, 50 bis 40 km, 70 bis 120 km, darüber 85 km/h – ohne Stau.")
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.surface)
        } header: {
            SetSectionHeader(title: "Annahmen")
        }
    }
}
