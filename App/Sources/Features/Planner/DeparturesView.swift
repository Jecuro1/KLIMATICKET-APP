import SwiftUI
import KlimaCore

/// The departure and arrival board (docs/OEBB_LIVE.md §E3 „Abfahrten“, UX §4.4, mock 13): station header with the live
/// age, mode chips that filter client-side, the rows, „Später“ (+60 min). Refreshes every 30 s while visible.
struct DeparturesView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tripSheet: BoardRow?

    var body: some View {
        let model = app.planner
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
        .task(id: model.boardStation?.id) { await model.loadBoard() }
        .task(id: model.boardKind) { await model.loadBoard() }
        .task(id: app.live.generation) { await refreshLoop(model) }
    }

    // MARK: Header

    private func header(_ model: PlannerModel) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            Button { model.beginSearch(.board) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.boardStation?.title ?? "")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
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
            Spacer(minLength: 0)
            Menu {
                Picker("Anzeige", selection: Binding(get: { model.boardKind }, set: { model.boardKind = $0 })) {
                    Text("Abfahrt").tag(BoardKind.departures)
                    Text("Ankunft").tag(BoardKind.arrivals)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.boardKind == .departures ? "Abfahrt" : "Ankunft").font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }

    @ViewBuilder
    private func subline(_ model: PlannerModel) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 6) {
                if let near = model.nearby, near.station.id == model.boardStation.flatMap({ if case .station(let s) = $0 { s.id } else { nil } }),
                   let meters = near.distanceMeters {
                    Image(systemName: "location.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text("\(meters) m").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                    Text("·").foregroundStyle(Theme.textTertiary)
                }
                if let updated = model.boardUpdatedAt, model.boardPhase == .loaded {
                    LiveDot(state: .onTime, size: 7)
                    Text("Live").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.live)
                    Text("vor \(max(0, Int(context.date.timeIntervalSince(updated)))) s")
                        .font(.system(size: 15)).foregroundStyle(Theme.textSecondary).monospacedDigit()
                } else if model.boardPhase == .loading {
                    ProgressView().controlSize(.mini)
                    Text("lädt …").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

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
                            Text(filter.title).font(.system(size: 17, weight: .semibold))
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
        case .failed(.unavailable(let reason)):
            PlannerUnavailableView(reason: reason) { app.isShowingSettings = true }
        case .failed(let failure) where model.boardRows.isEmpty:
            PlannerErrorBanner(failure: failure) { Task { await model.loadBoard() } }
        case .loading where model.boardRows.isEmpty:
            PlannerSkeletonList(count: 2)
        default:
            let rows = model.filteredBoardRows
            if case .failed(let failure) = model.boardPhase {
                if failure == .offline { PlannerOfflinePill(since: model.boardUpdatedAt) } else { PlannerErrorBanner(failure: failure) { Task { await model.loadBoard() } } }
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
                        Text("Später").font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 30 s while visible; paused in the background and in Low Power Mode.
    private func refreshLoop(_ model: PlannerModel) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, scenePhase == .active, !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
            await model.loadBoard(reset: false)
        }
    }
}
