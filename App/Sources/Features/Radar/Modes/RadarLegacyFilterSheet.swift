import SwiftUI
import KlimaCore

// MARK: radarmodes – the radar's filter sheet as it was before „Filter & Darstellung“: it stays what users get until the new sheet's screenshots
// have been looked at (`RadarFilterRollout`); then this file goes. Transport mode and line, delay state, Bundesland by keyword (a heuristic, said
// so in the footer) and "nur verspätet". Every change applies at once to the map.

/// Which filter sheet the radar opens: the new „Filter & Darstellung“ in screenshot launches only, until its screenshots are reviewed.
enum RadarFilterRollout {
    static var newSheet: Bool { LaunchMode.isSandboxed }
}

struct RadarLegacyFilterSheet: View {
    @Binding var filter: RadarFilter
    @Binding var modes: RadarModeSelection
    /// Line categories seen in the last answers ("RJX", "REX", "S", …).
    var categories: [String]
    /// MARK: radar2 – the parts of the second wave add their sections at the end (`Radar2SettingsSections`).
    var parts: Radar2Parts? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(RadarMode.allCases) { mode in
                        Toggle(isOn: modeBinding(mode)) {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                } header: {
                    Text("Verkehrsmittel")
                } footer: {
                    Text("Das Radar fragt jedes eingeschaltete Verkehrsmittel bei der ÖBB-Auskunft ab. Mindestens eins bleibt an.")
                }

                Section {
                    if categories.isEmpty {
                        Text("Im Ausschnitt gerade keine Linien")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(categories, id: \.self) { category in
                        Toggle(category, isOn: categoryBinding(category))
                    }
                } header: {
                    Text("Linie")
                } footer: {
                    Text("Ohne Auswahl sind alle Linien zu sehen.")
                }

                Section {
                    Toggle("Nur verspätet (ab 5 Minuten)", isOn: lateBinding)
                    Toggle("Pünktlich", isOn: delayBinding(.onTime))
                    Toggle("Fällt aus", isOn: delayBinding(.cancelled))
                } header: {
                    Text("Verspätung")
                } footer: {
                    Text("Ohne Auswahl sind alle Züge zu sehen. „Nur verspätet“ ersetzt „Pünktlich“ und „Fällt aus“.")
                }

                Section {
                    Picker("Bundesland", selection: $filter.state) {
                        Text("Alle").tag(AustrianState?.none)
                        ForEach(AustrianState.allCases, id: \.self) { state in
                            Text(state.title).tag(Optional(state))
                        }
                    }
                } header: {
                    Text("Region")
                } footer: {
                    Text("Schätzung über Haltestellennamen und Richtung. Züge ohne eindeutigen Treffer fallen bei einer Region heraus.")
                }

                Section {
                    Button("Alles zurücksetzen", role: .destructive) {
                        filter = RadarFilter()
                        modes = .default
                    }
                    .disabled(!filter.isActive && modes == .default)
                }

                Radar2SettingsSections(parts: parts)   // MARK: radar2
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    private func modeBinding(_ mode: RadarMode) -> Binding<Bool> {
        Binding(get: { modes.contains(mode) },
                set: { on in modes.set(mode, on: on) })   // at least one stays on
    }

    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(get: { filter.categories.contains(category) },
                set: { on in
                    if on {
                        filter.categories.insert(category)
                    } else {
                        filter.categories.remove(category)
                    }
                })
    }

    private func delayBinding(_ state: RadarDelayState) -> Binding<Bool> {
        Binding(get: { filter.delays.contains(state) },
                set: { on in
                    if on {
                        filter.delays.insert(state)
                        filter.onlyLate = false   // "Nur verspätet" and the other delay states exclude each other
                    } else {
                        filter.delays.remove(state)
                    }
                })
    }

    /// "Nur verspätet": on, it replaces the delay states. Without it the states above apply as they are.
    private var lateBinding: Binding<Bool> {
        Binding(get: { filter.onlyLate },
                set: { on in
                    filter.onlyLate = on
                    if on { filter.delays = [] }
                })
    }
}
