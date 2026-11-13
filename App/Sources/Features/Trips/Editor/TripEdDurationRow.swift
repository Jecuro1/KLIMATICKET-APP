import SwiftUI
import KlimaCore

// MARK: timebalance – „Dauer“ in the trip editor (docs/TIME_BALANCE.md §4): optional, „Unbekannt“ by default, a wheel in
// 5-minute steps. A trip without it is estimated in the Zeitbilanz; a connection from the Fahrplan shows its own times.

/// The optional ride duration of the selected leg (one direction).
struct TripEdDurationRow: View {
    let model: TripEditorModel

    /// CI: the scene `tripEditDuration` opens with the wheel showing.
    @State private var isExpanded = LaunchMode.screenshotScreen == "tripEditDuration"
    @Environment(\.dynamicTypeSize) private var typeSize

    private var minutes: Int { model.durationMinutes }

    var body: some View {
        SurfaceCard(padding: 0, cornerRadius: Theme.Radius.formGroup) {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, 9)
                if isExpanded {
                    TripEdRowDivider()
                    wheel
                        .motionTransition(.rise)
                }
            }
        }
        .haptic(.selection, trigger: minutes)
        .accessibilityIdentifier("tripEditor.duration")
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        let label = TripEdRowLabel(symbol: "timer", tint: Theme.dusk, title: title, subtitle: hint)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                label
                valueButton
            }
        } else {
            HStack(spacing: Theme.Spacing.s) {
                label
                Spacer(minLength: Theme.Spacing.xxs)
                valueButton
            }
        }
    }

    private var title: String {
        if model.isJourney { return "Dauer dieser Etappe" }
        return model.isRoundTrip ? "Dauer pro Richtung" : "Dauer"
    }

    private var hint: String {
        if minutes > 0 { return model.isRoundTrip && !model.isJourney ? "Eingetragen · zählt hin und zurück" : "Eingetragen" }
        if let fromConnection = model.durationFromConnection {
            return "Laut Verbindung \(TimeBalanceText.clock(fromConnection))"
        }
        guard model.distanceKm > 0 else { return "Optional – sonst grob geschätzt" }
        return "Optional – sonst geschätzt ≈ \(TimeBalanceText.clock(model.durationEstimate))"
    }

    private var valueButton: some View {
        Button {
            withMotion(Motion.smooth) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(minutes > 0 ? TimeBalanceText.clock(Double(minutes)) : "Unbekannt")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(minutes > 0 ? Theme.accentText : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surfaceSecondary, in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
        .accessibilityValue(minutes > 0 ? TimeBalanceText.spoken(Double(minutes), exact: true) : "Unbekannt")
        .accessibilityHint(isExpanded ? "Blendet das Rad aus" : "Zeigt das Rad für Stunden und Minuten")
        // VoiceOver: swipe up / down changes the duration in 5-minute steps without opening the wheel.
        .accessibilityAdjustableAction { direction in
            let base = minutes > 0 ? minutes : DurationWheel.snapped(model.durationSuggestion)
            switch direction {
            case .increment: model.setDurationMinutes(min(DurationWheel.maximumMinutes, base + DurationWheel.step))
            case .decrement: model.setDurationMinutes(max(DurationWheel.step, base - DurationWheel.step))
            @unknown default: break
            }
        }
    }

    // MARK: Wheel

    /// Hours and minutes in 5-minute steps. While the duration is unknown the wheel rests on the suggestion (the
    /// connection's or the estimate) without saving it – only turning it or „Übernehmen“ sets a duration.
    private var wheel: some View {
        let shown = DurationWheel.split(minutes > 0 ? DurationWheel.snapped(Double(minutes)) : DurationWheel.snapped(model.durationSuggestion))
        return VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                Picker("Stunden", selection: Binding(get: { shown.hours }, set: { new in
                    model.setDurationMinutes(DurationWheel.join(hours: new, minutes: shown.minutes))
                })) {
                    ForEach(DurationWheel.hours, id: \.self) { hour in
                        Text("\(hour) Std.").tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .accessibilityLabel("Stunden")
                Picker("Minuten", selection: Binding(get: { shown.minutes }, set: { new in
                    model.setDurationMinutes(DurationWheel.join(hours: shown.hours, minutes: new))
                })) {
                    ForEach(DurationWheel.minutes, id: \.self) { minute in
                        Text("\(minute) Min.").tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .accessibilityLabel("Minuten")
            }
            .frame(height: typeSize.isAccessibilitySize ? 200 : 140)
            .clipped()
            .opacity(minutes > 0 ? 1 : 0.55)
            HStack(spacing: Theme.Spacing.s) {
                if minutes > 0 {
                    Button {
                        withMotion(Motion.smooth) { model.setDurationMinutes(0) }
                    } label: {
                        Label("Unbekannt", systemImage: "xmark.circle")
                    }
                    .accessibilityHint("Die Dauer wird wieder geschätzt")
                } else {
                    Button {
                        withMotion(Motion.smooth) { model.setDurationMinutes(DurationWheel.snapped(model.durationSuggestion)) }
                    } label: {
                        Label("\(TimeBalanceText.clock(Double(DurationWheel.snapped(model.durationSuggestion)))) übernehmen",
                              systemImage: "checkmark.circle")
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .tint(Theme.accentText)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
        }
    }
}

// MARK: - Editor model

extension TripEditorModel {
    /// The selected leg's planner/recorded duration (arrival minus departure), when the leg is a saved one that has it
    /// and its route is unchanged.
    var durationFromConnection: Double? {
        guard legs.indices.contains(selectedLeg), let trip = legs[selectedLeg].trip, !legs[selectedLeg].routeChanged,
              trip.arrivalAt != nil else { return nil }
        let inputs = editingLegs.map { saved -> TimeTripInput in
            var input = saved.timeInput
            input.durationMinutes = 0
            // The date the form shows: a moved departure moves the saved arrival with it (see `TripEdDurationHook`).
            if let arrival = input.arrivalAt { input.arrivalAt = arrival.addingTimeInterval(date.timeIntervalSince(saved.date)) }
            input.date = date
            return input
        }
        guard let time = TravelTimeResolver.resolveAll(inputs)[trip.id], time.source == .timetable else { return nil }
        return time.minutesPerDirection
    }

    /// The speed model's guess for the selected leg (one direction).
    var durationEstimate: Double { TravelTimeModel.standard.minutes(mode, km: distanceKm) }

    /// Where the wheel rests while the duration is unknown.
    var durationSuggestion: Double { durationFromConnection ?? durationEstimate }
}

/// Before the editor writes a leg to its trip: the duration, and a stored arrival kept true to the ride. Planned times
/// belong to the route they were planned for – a new start, destination or place in the journey drops them; a new
/// departure time moves them along (the ride took as long as before).
enum TripEdDurationHook {
    @MainActor
    static func prepare(_ trip: TripEntity, leg: TripEdLeg, index: Int, from: String, to: String, date: Date, isJourney: Bool) {
        trip.durationMinutes = max(0, leg.durationMinutes)
        guard let arrival = trip.arrivalAt else { return }
        if leg.routeChanged || trip.fromName != from || trip.toName != to || trip.legIndex != (isJourney ? index : 0) {
            trip.arrivalAt = nil
        } else if trip.date != date {
            trip.arrivalAt = arrival.addingTimeInterval(date.timeIntervalSince(trip.date))
        }
    }
}
