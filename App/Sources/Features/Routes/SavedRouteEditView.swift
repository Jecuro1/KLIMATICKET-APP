import SwiftUI
import SwiftData
import KlimaCore

// „Meine Routen“ editor (docs/ROUTES_ALARMS.md §1.5): name, stops (with via stops), mode, fare and distance, and the optional
// weekday/time pattern with its reminder. A fare and a distance are estimated when both stops are known, with the app's
// estimator; the user can change them.

struct SavedRouteEditView: View {
    /// nil for a new route.
    let route: FavoriteRouteEntity?

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var fromName: String
    @State private var fromID: String?
    @State private var toName: String
    @State private var toID: String?
    @State private var vias: [TripVia]
    @State private var mode: TransportMode
    @State private var isRoundTrip: Bool
    @State private var fareText: String
    @State private var distanceText: String
    @State private var fareIsEstimated = false
    @State private var scheduleOn: Bool
    @State private var weekdays: Set<RouteWeekday>
    @State private var time: Date
    @State private var lead: Int
    @State private var pick: RoutePick?
    @State private var isSaving = false

    private static let modes: [TransportMode] = [.train, .sBahn, .bus, .tram, .metro]

    init(route: FavoriteRouteEntity?) {
        self.route = route
        let schedule = route?.schedule
        _title = State(initialValue: route?.title ?? "")
        _fromName = State(initialValue: route?.fromName ?? "")
        _fromID = State(initialValue: route?.fromStationID)
        _toName = State(initialValue: route?.toName ?? "")
        _toID = State(initialValue: route?.toStationID)
        _vias = State(initialValue: route?.via ?? [])
        _mode = State(initialValue: route?.mode ?? .train)
        _isRoundTrip = State(initialValue: route?.isRoundTrip ?? false)
        _fareText = State(initialValue: route.map { $0.fareEUR > 0 ? EuroInput.editableText($0.fareEUR) : "" } ?? "")
        _distanceText = State(initialValue: route.map { $0.distanceKm > 0 ? Format.number($0.distanceKm, decimals: 1) : "" } ?? "")
        _scheduleOn = State(initialValue: schedule != nil)
        _weekdays = State(initialValue: schedule?.weekdays ?? [.monday, .tuesday, .wednesday, .thursday, .friday])
        _time = State(initialValue: SavedRouteEditView.clock(hour: schedule?.hour ?? 7, minute: schedule?.minute ?? 30))
        _lead = State(initialValue: schedule?.leadMinutes ?? 10)
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("z. B. Arbeit", text: $title)
                    .textInputAutocapitalization(.sentences)
            }
            Section("Strecke") {
                stopRow(title: "Von", name: fromName, symbol: "circle.fill", tint: Theme.glacier) { pick = .from }
                ForEach(Array(vias.enumerated()), id: \.offset) { index, via in
                    HStack {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(Theme.textTertiary)
                        Text(via.name)
                        Spacer()
                        Button(role: .destructive) {
                            vias.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zwischenhalt \(via.name) entfernen")
                    }
                }
                if vias.count < JourneyQuery.maxViaStops {
                    Button { pick = .via } label: {
                        Label("Zwischenhalt hinzufügen", systemImage: "plus.circle")
                    }
                }
                stopRow(title: "Nach", name: toName, symbol: "mappin.circle.fill", tint: Theme.dawn) { pick = .to }
            }
            Section {
                Picker("Verkehrsmittel", selection: $mode) {
                    ForEach(Self.modes, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Hin und zurück", isOn: $isRoundTrip)
                LabeledContent("Preis je Fahrt") {
                    HStack(spacing: 4) {
                        TextField("0,00", text: $fareText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .onChange(of: fareText) { _, _ in fareIsEstimated = false }
                        Text("€").foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledContent("Strecke") {
                    HStack(spacing: 4) {
                        TextField("0", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text("km").foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                Text("Fahrt")
            } footer: {
                Text(fareIsEstimated
                     ? "Preis und Strecke sind geschätzt. Du kannst sie ändern."
                     : "Mit Haltestellen wird der Preis geschätzt, sobald Von und Nach feststehen.")
            }
            Section {
                Toggle("Zeitplan und Erinnerung", isOn: $scheduleOn)
                if scheduleOn {
                    weekdayChips
                    DatePicker("Abfahrt", selection: $time, displayedComponents: .hourAndMinute)
                    Picker("Erinnern", selection: $lead) {
                        ForEach(RouteSchedule.leadChoices, id: \.self) { minutes in
                            Text(minutes == 0 ? "Zur Abfahrt" : "\(minutes) Min vorher").tag(minutes)
                        }
                    }
                }
            } header: {
                Text("Zeitplan")
            } footer: {
                Text("KlimaBilanz erinnert dich an den gewählten Tagen zur gewählten Zeit. Die Erinnerung kommt von iOS, ohne Abfrage im Netz. Mitteilungen musst du erlauben.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sheetBackground)
        .navigationTitle(route == nil ? "Neue Route" : "Route bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }
                    .disabled(!canSave || isSaving)
            }
        }
        .sheet(item: $pick) { choice in
            NavigationStack {
                StationPickerView(title: choice.pickerTitle) { station in
                    apply(station, for: choice)
                    pick = nil
                }
            }
        }
    }

    // MARK: Parts

    private func stopRow(title: String, name: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(name.isEmpty ? "wählen" : name)
                    .foregroundStyle(name.isEmpty ? Theme.accentText : Theme.textPrimary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var weekdayChips: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(RouteWeekday.allCases, id: \.self) { day in
                let selected = weekdays.contains(day)
                Button {
                    if selected { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(day.shortName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Theme.accentText : Theme.textSecondary)
                .background(selected ? Theme.glacier.opacity(0.22) : Color.clear, in: Capsule())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Logic

    private var canSave: Bool {
        !fromName.trimmingCharacters(in: .whitespaces).isEmpty
            && !toName.trimmingCharacters(in: .whitespaces).isEmpty
            && (!scheduleOn || !weekdays.isEmpty)
    }

    private func apply(_ station: Station, for choice: RoutePick) {
        switch choice {
        case .from:
            fromName = station.name
            fromID = station.id
        case .to:
            toName = station.name
            toID = station.id
        case .via:
            vias.append(TripVia(station))
        }
        estimateIfPossible()
    }

    /// The fare and distance of the planner's estimator, once both stops are known and the fare was not typed by the user.
    private func estimateIfPossible() {
        guard let fromID, let toID, let from = app.stations.station(id: fromID), let to = app.stations.station(id: toID),
              fareText.isEmpty || fareIsEstimated,
              let estimate = SavedRouteFigures.estimate(from: from, to: to, mode: mode, app: app) else { return }
        fareText = EuroInput.editableText(estimate.fareEUR)
        distanceText = Format.number(estimate.distanceKm, decimals: 1)
        fareIsEstimated = true
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let repository = Repository(context: context, app: app)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fare = EuroInput.parse(fareText) ?? 0
        let distance = Double(distanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let target: FavoriteRouteEntity
        if let route {
            target = route
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<FavoriteRouteEntity>(predicate: #Predicate { $0.deletedAt == nil }))) ?? 0
            target = FavoriteRouteEntity(title: name, fromName: fromName, toName: toName, fromStationID: fromID, toStationID: toID,
                                         mode: mode, distanceKm: distance, fareEUR: fare, isRoundTrip: isRoundTrip, sortIndex: count)
        }
        target.title = name
        target.fromName = fromName
        target.fromStationID = fromID
        target.toName = toName
        target.toStationID = toID
        target.mode = mode
        target.distanceKm = distance
        target.fareEUR = fare
        target.isRoundTrip = isRoundTrip
        target.via = vias
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        target.schedule = scheduleOn
            ? RouteSchedule(weekdays: weekdays, hour: clock.hour ?? 7, minute: clock.minute ?? 30, leadMinutes: lead)
            : nil
        if route == nil {
            repository.addFavorite(target)
        } else {
            target.touch()
            repository.commit()
        }
        let reminders = await SavedRouteReminders.apply(to: target)
        if !reminders {
            app.showToast("bell.slash.fill", "Route gespeichert", "Die Erinnerung ist aus. Erlaube Mitteilungen in den iOS-Einstellungen.")
        } else {
            app.showToast("checkmark.circle.fill", "Route gespeichert", target.displayTitle)
        }
        dismiss()
    }

    private static func clock(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

/// Which stop the station picker chooses.
enum RoutePick: String, Identifiable {
    case from, to, via

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .from: "Von"
        case .to: "Nach"
        case .via: "Zwischenhalt"
        }
    }
}
