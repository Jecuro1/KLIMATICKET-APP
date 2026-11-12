import SwiftUI
import SwiftData
import KlimaCore

// MARK: tripdetect – "Bearbeiten": change start, destination and mode of a proposal before it becomes a ride. The value follows
// live (the same fare logic as the trip editor), "Übernehmen" files the ordinary ride.

struct TripCandidateEditSheet: View {
    let candidate: TripCandidateEntity
    let initial: CandidateStations

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var stations: CandidateStations
    @State private var mode: TransportMode
    @State private var facts: CandidateTripFacts?
    @State private var acceptTick = 0

    init(candidate: TripCandidateEntity, initial: CandidateStations) {
        self.candidate = candidate
        self.initial = initial
        _stations = State(initialValue: initial)
        _mode = State(initialValue: candidate.mode)
    }

    private var modes: [TransportMode] {
        var list: [TransportMode] = [.train, .bus, .tram, .metro]
        if !list.contains(candidate.mode) { list.insert(candidate.mode, at: 1) }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    routeCard
                    modeCard
                    valueCard
                    Text("Zeit: \(Format.relativeDay(candidate.departedAt)), \(Format.time(candidate.departedAt))–\(Format.time(candidate.arrivedAt)). Die Fahrt wird wie jede andere erfasst – Statistik, Jahresrückblick und Widgets zählen sie mit.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.xxs)
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollContentBackground(.hidden)
            .background { Theme.sheetBackground.ignoresSafeArea() }
            .navigationTitle("Fahrt bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { acceptBar }
            .task(id: valueKey) { recompute() }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.sheetBackground)
        .haptic(.success, trigger: acceptTick)
    }

    // MARK: Cards

    private var routeCard: some View {
        GlassCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            VStack(spacing: 0) {
                stationRow(title: "Von", station: stations.from, fallback: candidate.fromName) { stations.from = $0; stations.via = [] }
                Divider().padding(.leading, 56)
                stationRow(title: "Nach", station: stations.to, fallback: candidate.toName) { stations.to = $0; stations.via = [] }
            }
        }
    }

    private func stationRow(title: String, station: Station?, fallback: String, pick: @escaping (Station) -> Void) -> some View {
        NavigationLink {
            StationPickerView(title: title, selection: pick)
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: title == "Von" ? "circle" : "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(title == "Von" ? Theme.glacier : Theme.dawn)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(station?.name ?? (fallback.isEmpty ? "Haltestelle wählen" : fallback))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }

    private var modeCard: some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Verkehrsmittel").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: Theme.Spacing.xs, alignment: .leading)],
                          alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(modes) { option in
                        Chip(title: option.displayName, symbol: option.symbolName, isSelected: mode == option, tint: Theme.modeColor(option)) {
                            withMotion(Motion.snappy) { mode = option }
                        }
                    }
                }
            }
        }
        .haptic(.selection, trigger: mode)
    }

    private var valueCard: some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.formGroup) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wert der Fahrt").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                if let facts {
                    Text(Format.euroPrecise(facts.fareEUR))
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .numericValue(facts.fareEUR)
                    Text("\(facts.explanation) · \(Format.km(facts.distanceKm))")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Wähle Start und Ziel, dann steht hier der Normalpreis.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var acceptBar: some View {
        Button {
            if TripCandidateActions(app: app, context: context).accept(candidate, stations: stations, mode: mode) {
                acceptTick += 1
                dismiss()
            }
        } label: {
            Label("Übernehmen", systemImage: "checkmark")
        }
        .buttonStyle(.primary)
        .disabled(!stations.isComplete)
        .padding(.horizontal, Theme.Spacing.cardGutter)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
    }

    // MARK: Value

    private var valueKey: String { "\(stations.from?.id ?? "-")>\(stations.to?.id ?? "-")|\(mode.rawValue)" }

    private func recompute() {
        guard let from = stations.from, let to = stations.to, from.id != to.id else { facts = nil; return }
        facts = Repository(context: context, app: app).facts(mode: mode, date: candidate.departedAt, from: from, to: to, via: stations.via)
    }
}
