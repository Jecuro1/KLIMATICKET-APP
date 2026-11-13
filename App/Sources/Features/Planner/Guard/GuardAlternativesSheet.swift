import SwiftUI
import KlimaCore

// MARK: anschluss – „Weiter ab …“: the alternatives when the change is gone or shaky (docs/CONNECTION_GUARD.md §5). One TripSearch
// through the app's throttle, searched like the planner; the best three with their delay against the planned arrival;
// „Verfolgen“ starts the follow (and a new guard when the alternative has a change), „Im Fahrplan öffnen“ the Fahrplan.

struct GuardAlternativesSheet: View {
    /// Closes the sheets around it when the Fahrplan opens.
    var onPlanner: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private var service: ConnectionGuardService { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                            .reveal(order: 0)
                    }
                    content
                    Label(GuardText.alternativesTip, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let record = service.engine?.record {
                        Text(GuardText.alternativesFooter(klimaTicketOnly: record.klimaTicketOnly))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardGutter)
                .padding(.vertical, Theme.Spacing.s)
            }
            .revealScope()
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var query: JourneyQuery? {
        switch service.alternatives {
        case .loading(let q), .loaded(_, let q): return q
        case .failed(_, let q): return q
        case .idle: return nil
        }
    }

    private var title: String {
        if let query { return GuardText.alternativesTitle(query.origin.name) }
        return GuardText.alternativesTitle(service.assessment?.stationName ?? "Umstieg")
    }

    private var subtitle: String? {
        guard let query else { return nil }
        return GuardText.alternativesSubtitle(destination: query.destination.name, from: query.date)
    }

    private var originalArrival: Date? { service.engine?.record.journey.arrival?.planned }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch service.alternatives {
        case .idle:
            searchAgain
        case .loading:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text(GuardText.alternativesLoading).font(.body).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .loaded(let journeys, let query):
            if journeys.isEmpty {
                empty(GuardText.alternativesEmpty, query: query)
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(Array(journeys.enumerated()), id: \.element.id) { index, journey in
                        row(journey).reveal(order: index + 1)
                    }
                }
                searchAgain
            }
        case .failed(let message, let query):
            empty(message, query: query)
        }
    }

    private func empty(_ message: String, query: JourneyQuery?) -> some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label(message, systemImage: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let query {
                    Button { openPlanner(from: query.origin, to: query.destination, at: query.date) } label: {
                        Label(GuardText.plannerSearchButton, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    /// „Neu suchen“, or the three-minute limit.
    private var searchAgain: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let wait = GuardAlternatives.secondsUntilSearch(lastSearchAt: service.engine?.lastAlternativesSearchAt, now: context.date)
            if wait > 0 {
                Text(GuardText.searchLimit(wait))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            } else {
                Button { service.searchAlternatives() } label: {
                    Label(GuardText.alternativesNewSearch, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: Rows

    private func row(_ journey: Journey) -> some View {
        let lines = journey.rideLegs.compactMap(\.line)
        let delta = GuardAlternatives.deltaMinutes(journey, originalArrival: originalArrival)
        let large = typeSize.isAccessibilitySize
        return GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    LinePlateRow(badges: lines.map { LineBadge(line: $0, size: .m) }, size: .m)
                    if large {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GuardText.alternativeDeparture(journey)).font(.headline)
                            Text(GuardText.alternativeArrival(journey)).font(.headline)
                        }
                        .monospacedDigit()
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(GuardText.alternativeDeparture(journey)).font(.headline)
                            Spacer(minLength: 8)
                            Text(GuardText.alternativeArrival(journey)).font(.headline)
                        }
                        .monospacedDigit()
                    }
                    HStack(spacing: 6) {
                        if let text = GuardText.delta(delta) {
                            Text(text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle((delta ?? 0) > 0 ? Theme.summitText : Theme.positiveText)
                            Text("·").foregroundStyle(Theme.textTertiary)
                        }
                        Text(GuardText.changes(journey)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(GuardText.alternativeSpoken(journey, originalArrival: originalArrival))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { rowButtons(journey) }
                    VStack(alignment: .leading, spacing: 8) { rowButtons(journey) }
                }
            }
        }
    }

    @ViewBuilder
    private func rowButtons(_ journey: Journey) -> some View {
        if GuardAlternatives.followTarget(journey) != nil, app.live.timetable != nil {
            Button { follow(journey) } label: {
                Label(GuardText.followButton, systemImage: "location.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentTint)
            .accessibilityLabel(GuardText.followButtonSpoken)
        }
        if let from = journey.origin, let to = journey.destination {
            Button { openPlanner(from: from, to: to, at: journey.departure?.planned) } label: {
                Label(GuardText.plannerButton, systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: Actions

    /// „Verfolgen“: the alternative's first ride becomes the follow; a change in it gets its own guard.
    private func follow(_ journey: Journey) {
        guard let target = GuardAlternatives.followTarget(journey) else { return }
        let previous = service.engine?.record
        LiveFollowTracker.shared.start(target, live: app.live)
        if let previous {
            service.register(journey: journey, followTripID: target.tripID, products: previous.products,
                             klimaTicketOnly: previous.klimaTicketOnly, live: app.live)
        }
        let time = journey.departure?.effective.map { " · ab \(RealtimePresentation.time($0))" } ?? ""
        app.showToast("location.fill", "Live verfolgen", "\(target.lineName)\(time)", haptic: .start)
        dismiss()
    }

    private func openPlanner(from: Location, to: Location, at: Date?) {
        dismiss()
        onPlanner()
        app.selectedTab = .planner
        app.planner.openGuardSearch(from: from, to: to, at: at)
    }
}
