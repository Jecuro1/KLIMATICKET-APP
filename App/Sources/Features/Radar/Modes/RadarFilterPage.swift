import SwiftUI
import KlimaCore

// MARK: radarmodes – the page „Filter“ of „Filter & Darstellung“ (docs/RADAR_MODES.md §6). Every option changes the map at once; the modes ask the
// Auskunft (both lanes), every filter is applied on the iPhone to the vehicles the radar holds (live and Zeitreise, one matcher).

struct RadarFilterPage: View {
    @Binding var filter: RadarFilter
    @Binding var modes: RadarModeSelection
    var vehicles: [RadarVehicle]
    var counts: RadarModeCounts
    var scrollTo: String?

    @State private var lineText = ""
    @FocusState private var lineFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                quickSection
                modesSection
                trainClassSection
                linesSection.id("lines")
                operatorSection
                delaySection
                regionSection
                Section {
                    Button(RadarModesText.resetAll, role: .destructive) {
                        withMotion(Motion.smooth) {
                            filter = RadarFilter()
                            modes = .default
                        }
                    }
                    .disabled(!filter.isActive && modes == .default)
                }
            }
            .scrollContentBackground(.hidden)
            .onAppear {
                guard let scrollTo else { return }
                DispatchQueue.main.async { proxy.scrollTo(scrollTo, anchor: .top) }
            }
        }
    }

    // MARK: Schnellwahl

    private var quickSection: some View {
        Section {
            let current = RadarQuickChoice.current(selection: modes, filter: filter)
            ScrollView(.horizontal) {
                GlassMorphGroup(spacing: Theme.Spacing.xs) { ns in
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(RadarQuickChoice.allCases) { choice in
                            let chosen = current == choice
                            Button {
                                withMotion(Motion.smooth) { (modes, filter) = choice.apply(to: modes, filter: filter) }
                            } label: {
                                Label(choice.title, systemImage: choice.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(chosen ? Theme.accentText : Theme.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            .morphingGlass(chosen ? .regular.tint(Theme.accent.opacity(0.22)).interactive() : .regular.interactive(),
                                           in: .capsule, id: choice.rawValue, namespace: ns)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .listRowInsets(EdgeInsets(top: 6, leading: Theme.Spacing.cardGutter, bottom: 6, trailing: Theme.Spacing.cardGutter))
            .listRowBackground(Color.clear)
            .haptic(.selection, trigger: current)
        } header: {
            Text(RadarModesText.quickHeader)
        } footer: {
            Text(RadarModesText.quickFooter)
        }
    }

    // MARK: Verkehrsmittel

    private var modesSection: some View {
        Section {
            ForEach(RadarMode.allCases) { mode in
                Toggle(isOn: Binding(get: { modes.contains(mode) }, set: { on in modes.set(mode, on: on) })) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Label(mode.title, systemImage: mode.symbol)
                        Spacer(minLength: 4)
                        if modes.contains(mode), let count = counts.entries.first(where: { $0.mode == mode })?.count {
                            Text(RadarModesText.countNow(count))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                                .contentTransition(.numericText(value: Double(count)))
                        }
                    }
                }
            }
        } header: {
            Text(RadarModesText.modesHeader)
        } footer: {
            Text(RadarModesText.modesFooter())
        }
    }

    // MARK: Zugart

    private var trainClassSection: some View {
        Section {
            AutoFlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                ForEach(RadarTrainClass.allCases) { kind in
                    let on = filter.trainClasses.contains(kind)
                    Chip(title: kind.title, isSelected: on) {
                        withMotion(Motion.snappy) {
                            if on { filter.trainClasses.remove(kind) } else { filter.trainClasses.insert(kind) }
                        }
                    }
                    .accessibilityLabel(kind.spoken)
                }
            }
            .padding(.vertical, 4)
            .haptic(.selection, trigger: filter.trainClasses)
        } header: {
            Text(RadarModesText.trainClassHeader)
        } footer: {
            Text(RadarModesText.trainClassFooter)
        }
    }

    // MARK: Linie oder Zugnummer

    private var lineSuggestions: [String] {
        guard let query = RadarSearchQuery(lineText) else { return [] }
        let titles = RadarSearch.suggestions(for: query, in: vehicles, limit: 6).compactMap { $0.line.map(LinePresentation.title) }
        return titles.filter { !filter.lines.contains($0) }
    }

    private func addLine(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withMotion(Motion.snappy) { _ = filter.lines.insert(trimmed) }
        lineText = ""
    }

    private var linesSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "number").foregroundStyle(Theme.textSecondary)
                TextField(RadarModesText.linesPlaceholder, text: $lineText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($lineFocused)
                    .onSubmit { addLine(lineText) }
            }
            if !filter.lines.isEmpty {
                AutoFlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                    ForEach(filter.lines.sorted(by: LinePlateOrder.naturalLess), id: \.self) { line in
                        Button {
                            withMotion(Motion.snappy) { _ = filter.lines.remove(line) }
                        } label: {
                            HStack(spacing: 4) {
                                Text(line).font(.subheadline.weight(.semibold))
                                Image(systemName: "xmark.circle.fill").font(.caption)
                            }
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.14), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(RadarModesText.removeLine(line))
                    }
                }
                .padding(.vertical, 2)
            }
            let suggestions = lineSuggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RadarModesText.linesSuggestions).font(.footnote).foregroundStyle(Theme.textSecondary)
                    AutoFlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                        ForEach(suggestions, id: \.self) { title in
                            Chip(title: title, symbol: "plus") { addLine(title) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(RadarModesText.linesHeader)
        } footer: {
            Text(RadarModesText.linesFooter)
        }
    }

    // MARK: Betreiber

    @ViewBuilder private var operatorSection: some View {
        let operators = RadarOperator.counts(vehicles)
        // Only with two operators or more (or one already chosen): a section without effect is no option.
        if operators.count >= 2 || !filter.operators.isEmpty {
            let names = Set(operators.map(\.name)).union(filter.operators)
            Section {
                ForEach(names.sorted { a, b in
                    (operators.first { $0.name == a }?.count ?? 0) > (operators.first { $0.name == b }?.count ?? 0)
                }, id: \.self) { name in
                    Toggle(isOn: Binding(get: { filter.operators.contains(name) },
                                         set: { on in if on { filter.operators.insert(name) } else { filter.operators.remove(name) } })) {
                        HStack {
                            Text(name)
                            Spacer(minLength: 4)
                            Text(RadarModesText.countNow(operators.first { $0.name == name }?.count ?? 0))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } header: {
                Text(RadarModesText.operatorHeader)
            } footer: {
                Text(RadarModesText.operatorFooter)
            }
        }
    }

    // MARK: Verspätung

    private var delaySection: some View {
        Section {
            Toggle(RadarModesText.delayOnlyLate, isOn: Binding(get: { filter.onlyLate }, set: { on in
                filter.onlyLate = on
                if on { filter.delays = [] }   // „Nur verspätet“ replaces the delay states
            }))
            Toggle(RadarModesText.delayOnlyRealtime, isOn: $filter.onlyRealtime)
            Toggle(RadarModesText.delayOnTime, isOn: delayBinding(.onTime))
            Toggle(RadarModesText.delayCancelled, isOn: delayBinding(.cancelled))
        } header: {
            Text(RadarModesText.delayHeader)
        } footer: {
            Text(RadarModesText.delayFooter)
        }
    }

    private func delayBinding(_ state: RadarDelayState) -> Binding<Bool> {
        Binding(get: { filter.delays.contains(state) },
                set: { on in
                    if on {
                        filter.delays.insert(state)
                        filter.onlyLate = false
                    } else {
                        filter.delays.remove(state)
                    }
                })
    }

    // MARK: Region

    private var regionSection: some View {
        Section {
            Picker(RadarModesText.regionPicker, selection: $filter.state) {
                Text(RadarModesText.regionAll).tag(AustrianState?.none)
                ForEach(AustrianState.allCases, id: \.self) { state in
                    Text(state.title).tag(Optional(state))
                }
            }
        } header: {
            Text(RadarModesText.regionHeader)
        } footer: {
            Text(RadarModesText.regionFooter)
        }
    }
}
