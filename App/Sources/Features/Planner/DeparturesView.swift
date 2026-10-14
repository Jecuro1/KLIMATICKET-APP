import SwiftUI
import KlimaCore

/// The departure and arrival board (docs/OEBB_LIVE.md §E3 „Abfahrten“, UX §4.4, mock 13): station header with the live
/// age, mode chips that filter client-side, the rows, „Später“ (+60 min). Refreshes every 30 s while the scene is active.
struct DeparturesView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tripSheet: BoardRow?

    var body: some View {
        let model = app.planner
        let isActive = scenePhase == .active
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let reason = app.live.timetableUnavailable, reason != .offline {
                PlannerUnavailableView(reason: reason) { app.isShowingSettings = true }
            } else if model.boardStation == nil {
                PlannerNoticeCard(symbol: "list.bullet.rectangle", title: "Station wählen",
                                  message: "Suche eine Haltestelle und sieh live, was als Nächstes abfährt – mit Gleis und Verspätung.",
                                  actionTitle: "Station suchen", action: { model.beginSearch(.board) })
            } else {
                header(model)
                chips(model)
                board(model)
            }
        }
        .sheet(item: $tripSheet) { row in
            TripSheetView(row: row, tripID: model.tripID(forBoardRow: row.id) ?? "", station: model.boardStation, isArrival: model.boardKind == .arrivals)
        }
        // One load for each station and kind, when the view appears or either one changes.
        .task(id: BoardLoadKey(station: model.boardStation?.id, kind: model.boardKind)) { await model.loadBoard() }
        // The phase is part of the key: going to the background ends the loop, coming back starts a new one. (A value read
        // from the environment inside the loop would stay at the phase the task started in.)
        .task(id: RefreshKey(generation: app.live.generation, active: isActive)) {
            guard isActive else { return }
            await refreshLoop(model)
        }
    }

    // MARK: Header

    private func header(_ model: PlannerModel) -> some View {
        // At accessibility sizes the station and the mode menu stack instead of fighting for one line.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.s))
        return layout {
            Button { model.beginSearch(.board) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.boardStation?.title ?? "")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                    subline(model)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Station: \(model.boardStation?.title ?? "")")
            .accessibilityHint("Öffnet die Suche")
            if !stacked { Spacer(minLength: 0) }
            Menu {
                Picker("Anzeige", selection: Binding(get: { model.boardKind }, set: { model.boardKind = $0 })) {
                    Text("Abfahrt").tag(BoardKind.departures)
                    Text("Ankunft").tag(BoardKind.arrivals)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.boardKind == .departures ? "Abfahrt" : "Ankunft").font(.system(.body, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }

    /// The status under the station name. „Live“ only when ÖBB stated a realtime time stamp for the answer; the demo
    /// timetable says so, and an answer without one shows the plan with the age of the fetch.
    @ViewBuilder
    private func subline(_ model: PlannerModel) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 6) {
                if let near = model.nearby, near.station.id == model.boardStation.flatMap({ if case .station(let s) = $0 { s.id } else { nil } }),
                   let meters = near.distanceMeters {
                    Image(systemName: "location.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text("\(meters) m").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Text("·").foregroundStyle(Theme.textTertiary)
                }
                if model.boardPhase == .loaded, let fetched = model.boardUpdatedAt {
                    if app.live.isDemo {
                        Text("Demo-Daten").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    } else if let realtime = model.boardRealtimeAt {
                        LiveDot(state: .onTime, size: 7)
                        Text("Live").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.live)
                        Text("Stand vor \(age(realtime, context.date)) s")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary).monospacedDigit()
                    } else {
                        Text("Fahrplan, abgefragt vor \(age(fetched, context.date)) s")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary).monospacedDigit()
                    }
                } else if model.boardPhase == .loading {
                    ProgressView().controlSize(.mini)
                    Text("lädt …").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func age(_ date: Date, _ now: Date) -> Int { max(0, Int(now.timeIntervalSince(date))) }

    // MARK: Chips

    private func chips(_ model: PlannerModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(PlannerModel.BoardFilter.allCases) { filter in
                    let selected = model.boardFilter == filter
                    Button {
                        withMotion(Motion.snappy) { model.boardFilter = filter }
                    } label: {
                        HStack(spacing: 6) {
                            if let mode = filter.mode { Image(systemName: mode.symbolName).font(.system(size: 14, weight: .semibold)) }
                            Text(filter.title).font(.system(.body, weight: .semibold))
                        }
                        .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(selected ? AnyShapeStyle(Theme.prominentTint) : AnyShapeStyle(.clear), in: .capsule)
                        .glassEffect(selected ? .identity : .regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
        .haptic(.selection, trigger: model.boardFilter)
    }

    // MARK: Rows

    @ViewBuilder
    private func board(_ model: PlannerModel) -> some View {
        switch model.boardPhase {
        // Offline with rows already on screen keeps them (the offline pill below); without rows it is the unavailable card.
        case .failed(.unavailable(let reason)) where reason != .offline || model.boardRows.isEmpty:
            PlannerUnavailableView(reason: reason) { app.isShowingSettings = true }
        case .failed(let failure) where model.boardRows.isEmpty:
            PlannerErrorBanner(failure: failure) { Task { await model.loadBoard() } }
        case .loading where model.boardRows.isEmpty:
            PlannerSkeletonList(count: 2)
        default:
            let rows = model.filteredBoardRows
            if case .failed(let failure) = model.boardPhase {
                if failure == .offline || failure == .unavailable(.offline) {
                    PlannerOfflinePill(since: model.boardUpdatedAt)
                } else {
                    PlannerErrorBanner(failure: failure) { Task { await model.loadBoard() } }
                }
            }
            if rows.isEmpty {
                PlannerNoticeCard(symbol: "moon.zzz", title: "Nichts in den nächsten Stunden",
                                  message: model.boardFilter == .all ? "Zu dieser Zeit fährt hier nichts." : "Für diesen Filter fährt hier gerade nichts.",
                                  actionTitle: model.boardFilter == .all ? nil : "Alle zeigen", action: { model.boardFilter = .all })
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { tripSheet = row } label: { DepartureRow(row: row, isArrival: model.boardKind == .arrivals) }
                            .buttonStyle(.pressableCard)
                        if index < rows.count - 1 { Divider().overlay(Theme.separator) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .frostedCard(cornerRadius: Theme.Radius.card)
                .opacity({ if case .failed = model.boardPhase { return 0.72 } else { return 1 } }())
                .motionAnimation(Motion.smooth, value: rows.map(\.id))
                Button { Task { await model.loadLaterBoard() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                        Text("Später").font(.system(.body, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Zeigt eine Stunde mehr")
            }
        }
    }

    /// 30 s while the scene is active; paused in the background and in Low Power Mode.
    private func refreshLoop(_ model: PlannerModel) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await model.loadBoard(reset: false)
        }
    }
}

/// The inputs that start a board load.
private struct BoardLoadKey: Hashable {
    let station: String?
    let kind: BoardKind
}

/// The inputs that restart the 30 s refresh: a new live generation (consent, switches) or a change of the scene phase.
private struct RefreshKey: Hashable {
    let generation: Int
    let active: Bool
}
