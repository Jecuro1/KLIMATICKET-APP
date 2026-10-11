import SwiftUI
import KlimaCore

/// The full run of one train or bus (docs/OEBB_LIVE.md §E3 „Abfahrten“): opens from a board row, shows every stop with
/// planned time, realtime and platform; the stop of the board is marked.
struct TripSheetView: View {
    var row: BoardRow
    /// HAFAS run id of the board entry (the row id is not it: a run id contains „|“).
    var tripID: String
    var station: PlannerPlace?
    var isArrival: Bool

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var details: TripDetails?
    @State private var failure: PlannerFailure?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    headerCard
                    if let details {
                        stopsCard(details)
                    } else if let failure {
                        PlannerErrorBanner(failure: failure) { Task { await load() } }
                    } else {
                        PlannerSkeletonList(count: 1)
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background { SetBackdrop(skyOpacity: 0.5, fadeEnd: 0.4) }
            .navigationTitle(row.lineTitle.isEmpty ? "Fahrt" : row.lineTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.fontWeight(.semibold) } }
        }
        .task { await load() }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.sheetBackground)
    }

    private var headerCard: some View {
        GlassCard(padding: Theme.Spacing.m, cornerRadius: Theme.Radius.formGroup) {
            HStack(spacing: Theme.Spacing.s) {
                PlannerLinePlate(row: row, size: .l)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(isArrival ? "von" : "nach") \(row.destination.name)").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    Text(row.lineTitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(row.time).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    if let text = row.realtime.text {
                        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(PlannerRealtimeStyle.text(row.realtime.state))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stopsCard(_ details: TripDetails) -> some View {
        let color = PlannerPalette.stroke(for: row.mode)
        let here = station.map { StationIndex.normalize($0.title) }
        return VStack(spacing: 0) {
            ForEach(Array(details.stopovers.enumerated()), id: \.offset) { index, stop in
                let isHere = here.map { StationIndex.normalize(DisplayNames.name(stop.location.name)).hasPrefix($0.prefix(8)) } ?? false
                let event = stop.departure ?? stop.arrival
                TimelineStopRow(role: index == 0 ? .start : (index == details.stopovers.count - 1 ? .end : .transfer),
                                planned: event?.planned, realtime: event.map(RealtimePresentation.label) ?? RealtimeLabel(state: .scheduled),
                                name: DisplayNames.make(stop.location.name), caption: isHere ? "Deine Station" : (stop.passesWithoutStop ? "Durchfahrt" : nil),
                                platform: event.flatMap { JourneyPresentation.platformLabel($0, mode: row.mode) },
                                above: index == 0 ? .none : .ride(color), below: index == details.stopovers.count - 1 ? .none : .ride(color))
                    .opacity(stop.passesWithoutStop ? 0.6 : 1)
                    .background(isHere ? Theme.accent.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(Theme.Spacing.m)
        .frostedCard(cornerRadius: Theme.Radius.card)
    }

    private func load() async {
        failure = nil
        guard let timetable = app.live.timetable else {
            failure = .unavailable(app.live.timetableUnavailable ?? .offline)
            return
        }
        do {
            let fetched = try await timetable.trip(tripID, includePolyline: false)
            withMotion(Motion.smooth) { details = fetched }
        } catch {
            failure = PlannerFailure(error)
        }
    }
}
