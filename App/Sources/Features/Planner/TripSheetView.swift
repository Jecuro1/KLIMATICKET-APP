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
                    Text("\(isArrival ? "von" : "nach") \(row.destination.name)")
                        .font(.system(.title3, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    Text(row.lineTitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(row.time).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                    if let text = row.realtime.text {
                        Text(text).font(.system(.footnote, weight: .semibold)).foregroundStyle(PlannerRealtimeStyle.text(row.realtime.state))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stopsCard(_ details: TripDetails) -> some View {
        let color = PlannerPalette.stroke(for: row.mode)
        return VStack(spacing: 0) {
            ForEach(Array(details.stopovers.enumerated()), id: \.offset) { index, stop in
                let isHere = marksBoardStop(stop.location)
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

    /// The stop of the board: the same station id, else the same name (exact, not a prefix: „Wien Mitte“ must not mark
    /// „Wien Mitterndorf“). A different id does not end the check: the name still decides when the two id schemes differ.
    private func marksBoardStop(_ location: Location) -> Bool {
        if let boardID = boardExtID, let stopID = location.extId, stopID == boardID { return true }
        guard let title = station?.title else { return false }
        return StationIndex.normalize(DisplayNames.name(location.name)) == StationIndex.normalize(title)
    }

    private var boardExtID: String? {
        switch station {
        case .station(let s)?: s.id.hasPrefix("uic:") ? String(s.id.dropFirst(4)) : s.id
        case .live(let l)?: l.extId
        case .currentLocation?, nil: nil
        }
    }

    private func load() async {
        failure = nil
        // A row without its run id has nothing to ask ÖBB for: no request.
        guard !tripID.isEmpty else {
            failure = .tripGone
            return
        }
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
