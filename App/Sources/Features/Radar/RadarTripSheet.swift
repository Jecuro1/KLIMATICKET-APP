import SwiftUI
import KlimaCore

// Tap a train on the radar: a sheet with three detents (peek, half, full). The route (JourneyDetails with polyline) and the
// stops with realtime labels are cached per trip in memory for five minutes. A stop opens its departures.

/// Trip details per trip id, in memory only: a trip changes during the day, so an entry lives five minutes.
@MainActor
final class RadarRouteCache {
    static let shared = RadarRouteCache()
    static let lifetime: TimeInterval = 300
    static let capacity = 30

    private var items: [String: (details: TripDetails, storedAt: Date)] = [:]

    func value(for tripID: String, now: Date = Date()) -> TripDetails? {
        guard let item = items[tripID] else { return nil }
        guard now.timeIntervalSince(item.storedAt) < Self.lifetime else {
            items[tripID] = nil
            return nil
        }
        return item.details
    }

    func store(_ details: TripDetails, now: Date = Date()) {
        if items[details.tripID] == nil, items.count >= Self.capacity,
           let oldest = items.min(by: { $0.value.storedAt < $1.value.storedAt }) {
            items[oldest.key] = nil
        }
        items[details.tripID] = (details, now)
    }
}

struct RadarTripSheet: View {
    let vehicle: RadarVehicle
    /// Centres the map on the train (the sheet closes).
    var onCenter: () -> Void = {}
    /// The polyline of the route, once the trip details are known.
    var onRoute: ([GeoPoint]) -> Void = { _ in }
    /// A stop was chosen: its departures open (the radar closes).
    var onStation: (Location) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var details: TripDetails?
    @State private var loadFailed = false

    /// The live run when the details are in, else the run the map already has.
    private var run: RadarVehicle {
        guard let details else { return vehicle }
        return RadarVehicle(tripID: vehicle.tripID, line: vehicle.line, direction: vehicle.direction,
                            coordinate: vehicle.coordinate, stopovers: details.stopovers, isCancelled: details.isCancelled)
    }

    private var nextStop: Stopover? {
        RadarRun.nextStop(of: run, now: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header
                    actions
                    stopsList
                    if loadFailed {
                        Text("Die Route kommt gerade nicht. Die Haltestellen von der Karte bleiben stehen.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Fahrt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Schließen") { dismiss() } } }
            .task(id: vehicle.tripID) { await loadDetails() }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let line = vehicle.line {
                PlannerLinePlate(line: line, size: .m)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.line.map { LinePresentation.title($0) } ?? "Zug")
                    .font(Theme.Typography.title)
                if let direction = vehicle.direction {
                    Text("Richtung \(direction)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(delayText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(delayColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var delayText: String {
        let now = Date()
        switch RadarDelay.state(of: run, now: now) {
        case .cancelled:
            return "Fällt aus"
        case .onTime:
            return "Pünktlich"
        case .late:
            let minutes = max((RadarDelay.currentDelay(of: run, now: now) ?? 0) / 60, 5)
            return "\(minutes) Minuten verspätet"
        case .unknown:
            return "Keine Echtzeit-Daten"
        }
    }

    private var delayColor: Color {
        RadarDelay.state(of: run, now: Date()).tint
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button { startFollowing() } label: {
                Label("Live verfolgen", systemImage: "location.fill").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.primary)
            .disabled(vehicle.stopovers.count < 2)

            HStack(spacing: Theme.Spacing.s) {
                Button { onCenter(); dismiss() } label: {
                    Label("Auf Karte zentrieren", systemImage: "scope").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button { if let nextStop { onStation(nextStop.location) } } label: {
                    Label("Haltestelle öffnen", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(nextStop == nil)
            }
        }
    }

    private var stopsList: some View {
        GlassCard(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(Array(run.stopovers.enumerated()), id: \.offset) { _, stop in
                    Button { onStation(stop.location) } label: {
                        HStack {
                            Text(stop.location.name)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if let event = stop.departure ?? stop.arrival {
                                let label = RealtimePresentation.label(event)
                                if let text = label.text {
                                    Text(text)
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(label.state == .onTime ? Theme.positiveText : Theme.summitText)
                                }
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abfahrten dieser Haltestelle öffnen")
                }
            }
        }
    }

    private func startFollowing() {
        guard let target = vehicle.followTarget else { return }
        LiveFollowTracker.shared.start(target, live: app.live)
        dismiss()
    }

    private func loadDetails() async {
        if let cached = RadarRouteCache.shared.value(for: vehicle.tripID) {
            details = cached
            if let polyline = cached.polyline, polyline.count > 1 { onRoute(polyline) }
            return
        }
        guard let service = app.live.timetable else { return }
        do {
            let trip = try await service.trip(vehicle.tripID, includePolyline: true)
            RadarRouteCache.shared.store(trip)
            details = trip
            loadFailed = false
            if let polyline = trip.polyline, polyline.count > 1 { onRoute(polyline) }
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }
}
