import SwiftUI
import KlimaCore

// The stops and legs of a connection on one rail (split from ConnectionDetailView.swift).

// MARK: - Timeline list

/// The stops and legs of a connection on one rail.
struct TimelineList: View {
    var journey: Journey
    var summary: ConnectionSummary
    @Binding var expanded: Set<String>

    private enum Item: Identifiable {
        case stop(id: String, role: TimelineStopRow.Role, name: String, planned: Date?, event: StopEvent?, caption: String?, above: TimelineRail, below: TimelineRail, footnote: Bool)
        case ride(Leg)
        case walk(id: String, text: String, transfer: TransferInfo?)

        var id: String {
            switch self {
            case .stop(let id, _, _, _, _, _, _, _, _): "s-\(id)"
            case .ride(let leg): "r-\(leg.id)"
            case .walk(let id, _, _): "w-\(id)"
            }
        }
    }

    var body: some View {
        let items = build()
        VStack(spacing: 0) {
            ForEach(items) { item in
                switch item {
                case .stop(_, let role, let name, let planned, let event, let caption, let above, let below, let footnote):
                    TimelineStopRow(role: role, planned: planned,
                                    realtime: event.map(RealtimePresentation.label) ?? RealtimeLabel(state: .scheduled),
                                    name: DisplayNames.make(name), caption: caption,
                                    platform: event.flatMap { JourneyPresentation.platformLabel($0, mode: modeOf(name)) },
                                    above: above, below: below, isFootnote: footnote, showsScheduledHint: true)
                case .ride(let leg):
                    rideView(leg)
                case .walk(_, let text, let transfer):
                    TimelineWalkLeg(text: text, transfer: transfer)
                }
            }
        }
    }

    private func modeOf(_ name: String) -> TransportMode? {
        journey.legs.first { $0.origin.name == name || $0.destination.name == name }?.line?.mode
    }

    private func rideView(_ leg: Leg) -> some View {
        let line = leg.line
        let badge = line.map { LineBadge(line: $0, size: .m) } ?? LineBadge(kind: .sonst, text: "", spoken: "Fahrt")
        let minutes: Int = {
            guard let a = leg.departure.planned ?? leg.departure.effective, let b = leg.arrival.planned ?? leg.arrival.effective else { return 0 }
            return Int(b.timeIntervalSince(a) / 60)
        }()
        let kindText = line?.categoryLong?.trimmingCharacters(in: .whitespaces).nonEmpty ?? line?.operatorName.flatMap { $0 == "Nahreisezug" ? nil : $0 }
        let subtitle = [kindText, minutes > 0 ? JourneyPresentation.durationText(minutes: minutes) : nil].compactMap { $0 }.joined(separator: " · ")
        let stops = leg.intermediateStops.filter { !$0.passesWithoutStop }.enumerated().map { index, stop -> TimelineIntermediateStop in
            let event = stop.departure ?? stop.arrival
            return TimelineIntermediateStop(id: "\(leg.id)-\(index)", time: event?.planned,
                                            realtime: event.map(RealtimePresentation.label) ?? RealtimeLabel(state: .scheduled),
                                            name: DisplayNames.name(stop.location.name))
        }
        let notices = JourneyPresentation.notices(leg.remarks).filter { $0.severity >= .warning }
        return TimelineRideLeg(badge: badge, title: line.map(LinePresentation.title) ?? "Fahrt", direction: leg.direction.map(DisplayNames.name),
                               subtitle: subtitle.isEmpty ? nil : subtitle, attributes: JourneyPresentation.attributes(leg.remarks),
                               stops: stops, color: PlannerPalette.stroke(for: line?.mode ?? .train), notices: notices,
                               isCancelled: leg.isCancelled,
                               isExpanded: Binding(get: { expanded.contains(leg.id) },
                                                   set: { if $0 { expanded.insert(leg.id) } else { expanded.remove(leg.id) } }))
    }

    /// Stops at the boundaries of the legs, ride legs between them, walks and changes dotted.
    private func build() -> [Item] {
        var items: [Item] = []
        let legs = journey.legs
        var transfers = summary.transfers[...]
        for (index, leg) in legs.enumerated() {
            let previous = index > 0 ? legs[index - 1] : nil
            let next = index + 1 < legs.count ? legs[index + 1] : nil
            let railBefore = rail(for: previous), railHere = rail(for: leg), railAfter = rail(for: next)
            let isFootnoteStart = index == 0 && leg.kind != .ride
            // A stop row opens the journey and every place the traveller is on foot or changes.
            if index == 0 {
                let caption: String? = {
                    guard leg.kind == .ride, let t = leg.departure.effective, t > Date() else { return nil }
                    let m = Int(t.timeIntervalSinceNow / 60)
                    return m < 1 ? "Abfahrt jetzt" : "Abfahrt in \(m) min"
                }()
                items.append(.stop(id: "\(leg.id)-o", role: .start, name: leg.origin.name, planned: leg.departure.planned, event: leg.departure,
                                   caption: caption, above: .none, below: railHere, footnote: isFootnoteStart))
            } else if previous?.kind != .ride, leg.kind == .ride {
                // After a walk: the stop where the next ride starts.
                items.append(.stop(id: "\(leg.id)-o", role: .transfer, name: leg.origin.name, planned: leg.departure.planned, event: leg.departure,
                                   caption: nil, above: railBefore, below: railHere, footnote: false))
            }
            switch leg.kind {
            case .ride:
                items.append(.ride(leg))
                let isLast = next == nil
                items.append(.stop(id: "\(leg.id)-d", role: isLast ? .end : .transfer, name: leg.destination.name,
                                   planned: leg.arrival.planned, event: leg.arrival, caption: "Ankunft",
                                   above: railHere, below: isLast ? .none : railAfter, footnote: false))
            case .walk, .transfer:
                let info: TransferInfo? = (previous?.kind == .ride && next?.kind == .ride && !transfers.isEmpty) ? transfers.removeFirst() : nil
                items.append(.walk(id: leg.id, text: walkText(leg), transfer: info))
                if next == nil {
                    // A trailing walk ends at its own stop (address, POI).
                    items.append(.stop(id: "\(leg.id)-d", role: .end, name: leg.destination.name, planned: leg.arrival.planned, event: leg.arrival,
                                       caption: "Ziel", above: .walk, below: .none, footnote: true))
                }
            }
        }
        return items
    }

    private func rail(for leg: Leg?) -> TimelineRail {
        guard let leg else { return .none }
        return leg.kind == .ride ? .ride(PlannerPalette.stroke(for: leg.line?.mode ?? .train)) : .walk
    }

    private func walkText(_ leg: Leg) -> String {
        let minutes: Int = {
            if let a = leg.departure.effective, let b = leg.arrival.effective { return max(1, Int((b.timeIntervalSince(a) / 60).rounded())) }
            return max(1, (leg.walkDurationSeconds ?? 60) / 60)
        }()
        if leg.kind == .transfer { return "Umstieg · \(minutes) min" }
        var text = "\(minutes) min Fußweg"
        let sub = DisplayNames.make(leg.destination.name).sub
        if let meters = leg.walkDistanceMeters, meters > 0 { text += " · \(meters) m" + (sub.map { " zum \($0)" } ?? "") }
        else if let sub { text += " · zum \(sub)" }
        return text
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
