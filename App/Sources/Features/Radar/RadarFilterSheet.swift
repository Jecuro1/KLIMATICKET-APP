import SwiftUI
import KlimaCore

// Filter for the radar: transport mode and line, delay state, Bundesland by keyword (a heuristic, said so in the footer)
// and "nur verspätet". Every change applies at once to the map.

struct RadarFilterSheet: View {
    @Binding var filter: RadarFilter
    @Binding var modes: Set<RadarMode>
    /// Line categories seen in the last answers ("RJX", "REX", "S", …).
    var categories: [String]

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
                    Text("Verkehrsmittel fragt ÖBB direkt ab. Mindestens eins bleibt an.")
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
                        modes = [.rail]
                    }
                    .disabled(!filter.isActive && modes == [.rail])
                }
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
                set: { on in
                    if on {
                        modes.insert(mode)
                    } else if modes.count > 1 {
                        modes.remove(mode)
                    }
                })
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
