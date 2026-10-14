import SwiftUI
import KlimaCore

/// Options of the connection search (docs/OEBB_LIVE.md §E3 „Options sheet“): KlimaTicket filter, vehicle types, changes,
/// extra change time, accessibility and bikes. Stored in UserDefaults `planner.options`; a running search is repeated when
/// the sheet closes with a change.
struct PlannerOptionsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var original: PlannerOptions?

    var body: some View {
        let model = app.planner
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(get: { model.isKlimaTicketOnly }, set: { model.options.klimaTicketOnly = $0 })) {
                        SetRowLabel(title: "Nur mit KlimaTicket gültig", subtitle: "Blendet Verbindungen aus, die dein Ticket nicht abdeckt",
                                    symbol: "ticket.fill", tint: Theme.pine)
                    }
                    .listRowBackground(Theme.surface)
                } footer: {
                    SetFooter(text: "Teilweise gültige Verbindungen bleiben sichtbar – mit dem Hinweis, bis wohin dein Ticket gilt.")
                }
                Section {
                    ForEach(PlannerOptions.Group.allCases) { group in
                        Toggle(isOn: groupBinding(group, model)) {
                            Label(group.title, systemImage: group.symbol)
                        }
                        .listRowBackground(Theme.surface)
                    }
                } header: {
                    SetSectionHeader(title: "Verkehrsmittel")
                }
                Section {
                    Picker("Max. Fußweg", selection: Binding(get: { model.options.maxWalkMeters ?? -1 }, set: { model.options.maxWalkMeters = $0 < 0 ? nil : $0 })) {
                        Text("Beliebig").tag(-1)
                        Text("300 m").tag(300)
                        Text("500 m").tag(500)
                        Text("1 km").tag(1_000)
                        Text("2 km").tag(2_000)
                    }
                    .listRowBackground(Theme.surface)
                    Picker("Klasse", selection: Binding(get: { model.options.travelClass }, set: { model.options.travelClass = $0 })) {
                        Text("Wie Einstellungen").tag(TravelClass?.none)
                        Text("2. Klasse").tag(TravelClass?.some(.second))
                        Text("1. Klasse").tag(TravelClass?.some(.first))
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Theme.surface)
                    Toggle("Mit Vorteilscard", isOn: Binding(get: { model.effectiveDiscount == .vorteilscard },
                                                             set: { model.options.discount = $0 ? .vorteilscard : FareDiscount.none }))
                        .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Fußweg und Preis")
                } footer: {
                    SetFooter(text: "Der Fußweg zählt je Verbindung (Umsteigen in einem Bahnhof zählt nicht). Klasse und Vorteilscard gelten für die Preise hier und für die Erfassung.")
                }
                Section {
                    Picker("Umstiege", selection: Binding(get: { model.options.maxChanges ?? -1 }, set: { model.options.maxChanges = $0 < 0 ? nil : $0 })) {
                        Text("Beliebig").tag(-1)
                        Text("Direkt").tag(0)
                        Text("Max. 1").tag(1)
                        Text("Max. 2").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Theme.surface)
                    Picker("Umsteigezeit", selection: Binding(get: { model.options.extraTransferMinutes }, set: { model.options.extraTransferMinutes = $0 })) {
                        Text("Normal").tag(0)
                        Text("+5 min").tag(5)
                        Text("+10 min").tag(10)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Umstiege")
                } footer: {
                    SetFooter(text: "Mehr Umsteigezeit macht die Verbindung sicherer, aber oft länger.")
                }
                Section {
                    Toggle("Barrierefrei", isOn: Binding(get: { model.options.accessible }, set: { model.options.accessible = $0 }))
                        .listRowBackground(Theme.surface)
                    Toggle("Fahrradmitnahme", isOn: Binding(get: { model.options.bike }, set: { model.options.bike = $0 }))
                        .listRowBackground(Theme.surface)
                } header: {
                    SetSectionHeader(title: "Komfort")
                }
                Section {
                    Button("Zurücksetzen", role: .destructive) { model.options = PlannerOptions() }
                        .disabled(model.options.isDefault)
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.4) }
            .navigationTitle("Optionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.fontWeight(.semibold) } }
        }
        .onAppear { original = model.options }
        .onDisappear {
            if original != model.options, model.hasBoth, model.path.contains(.results) { model.restartSearch() }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.sheetBackground)
    }

    /// A group is on when any of its products is in the filter. At least one group stays on.
    private func groupBinding(_ group: PlannerOptions.Group, _ model: PlannerModel) -> Binding<Bool> {
        Binding(get: { !model.options.products.intersection(group.mask).isEmpty },
                set: { on in
                    var products = model.options.products
                    if on { products.formUnion(group.mask) } else {
                        let rest = products.subtracting(group.mask)
                        guard !rest.isEmpty else { return }
                        products = rest
                    }
                    model.options.products = products
                })
    }
}

/// Date and time of the search, departure or arrival (docs/OEBB_LIVE.md §E3, UX §4.1).
struct PlannerTimeSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var isArrival = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Zeit", selection: $isArrival) {
                        Text("Abfahrt").tag(false)
                        Text("Ankunft").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Theme.surface)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                        .listRowBackground(Theme.surface)
                    DatePicker("Uhrzeit", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .listRowBackground(Theme.surface)
                }
                Section {
                    Button("Jetzt") { apply(nil) }.listRowBackground(Theme.surface)
                }
            }
            .environment(\.locale, Format.locale)
            .environment(\.timeZone, Format.timeZone)
            .environment(\.calendar, .vienna)
            .scrollContentBackground(.hidden)
            .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.4) }
            .navigationTitle("Zeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { apply(date) }.fontWeight(.semibold) }
            }
        }
        .onAppear {
            let model = app.planner
            date = model.when ?? Date()
            isArrival = model.isArrival
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.sheetBackground)
    }

    private func apply(_ chosen: Date?) {
        app.planner.setWhen(chosen, arrival: chosen == nil ? false : isArrival)
        dismiss()
    }
}
