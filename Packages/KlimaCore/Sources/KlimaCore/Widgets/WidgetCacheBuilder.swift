import Foundation

/// Equipment of a station the data delivers (docs/WIDGETS.md §3.1): Bike+Ride, Park+Ride, barrier-free access. Lifts and
/// toilets are not in the place data, so there is no case for them. Train equipment is a different thing (`trainAttributes`).
public enum WidgetFacility: String, Codable, Sendable, CaseIterable {
    case bikeRide
    case parkRide
    case barrierFree
    case barrierFreePartial
}

/// Turns live answers into the widget cache. Pure mapping, no I/O: the app passes in what `HafasClient` returned.
public enum WidgetCacheBuilder {
    /// The next `limit` connections of one favourite route that are still ahead of `now`, cancelled ones included (they
    /// are shown as "fällt aus").
    public static func connections(from page: JourneyPage, now: Date, limit: Int = 3) -> [WidgetConnection] {
        WidgetFilter.upcoming(page.journeys.compactMap(connection(from:)), now: now, limit: limit)
    }

    /// One journey as the widget shows it: the first ride's departure and platform, the final arrival, changes, duration
    /// and the equipment of the first train. nil for a journey without a ride or without a planned departure.
    public static func connection(from journey: Journey) -> WidgetConnection? {
        let rides = journey.rideLegs
        guard let first = rides.first, let planned = first.departure.planned else { return nil }
        let last = rides.last ?? first
        let platform = JourneyPresentation.platformLabel(first.departure, mode: first.line?.mode)
        return WidgetConnection(
            id: journey.id,
            planned: planned,
            realtime: first.departure.realtime,
            arrival: journey.arrival?.effective,
            changes: journey.changes,
            durationMinutes: journey.durationSeconds.map { $0 / 60 },
            fromName: DisplayNames.name(first.origin.name),
            toName: DisplayNames.name(last.destination.name),
            lineName: first.line?.name ?? "Fahrt",
            modeSymbol: (first.line?.mode ?? .other).symbolName,
            direction: first.direction,
            platform: platform.map { "\($0.label) \($0.display)" },
            platformChanged: platform?.changed ?? false,
            isCancelled: rides.contains { $0.isCancelled },
            trainAttributes: trainEquipment(journey.remarks + first.remarks)
        )
    }

    /// SF Symbols of the equipment of a train from its attribute remarks, in the order of the planner's chips. Unlike the
    /// planner's chips (docs/OEBB_LIVE.md §C3.4, which show OC with the wheelchair), a rollstuhltaugliches WC (OC, OG) is
    /// a toilet here, because the widget names the equipment of the train, not a seat.
    public static func trainEquipment(_ remarks: [Remark]) -> [String] {
        let codes = Set(remarks.filter { $0.kind == .attribute }.compactMap(\.code))
        let table: [(codes: Set<String>, symbol: String)] = [
            (["WV"], "wifi"), (["BR"], "fork.knife"), (["HD"], "moon"), (["KN"], "figure.2.and.child.holdinghands"),
            (["RO", "OA", "EF"], "figure.roll"), (["OC", "OG"], "toilet"), (["FK", "FR"], "bicycle"), (["UA"], "briefcase"),
        ]
        return table.filter { !$0.codes.isDisjoint(with: codes) }.map(\.symbol).sorted()
    }

    /// Upcoming departures of a station board, cancelled ones included, first `limit` from `now` on.
    public static func departures(from board: Board, now: Date, limit: Int = 8) -> [WidgetDeparture] {
        let items: [WidgetDeparture] = board.entries.compactMap { entry in
            guard let planned = entry.event.planned else { return nil }
            let platform = JourneyPresentation.platformLabel(entry.event, mode: entry.line?.mode)
            return WidgetDeparture(
                id: entry.id,
                planned: planned,
                realtime: entry.event.realtime,
                lineName: entry.line?.name ?? "Fahrt",
                modeSymbol: (entry.line?.mode ?? .other).symbolName,
                direction: entry.direction,
                platform: platform.map { "\($0.label) \($0.display)" },
                platformChanged: platform?.changed ?? false,
                isCancelled: entry.event.isCancelled
            )
        }
        return WidgetFilter.upcoming(items, now: now, limit: limit)
    }

    /// Disruptions that name one of the `followedLines` and are still valid, most recent first, at most `limit`. The
    /// summary is shortened to whole words.
    public static func disruptions(_ remarks: [Remark], followedLines: [String], now: Date, limit: Int = 5) -> [WidgetDisruption] {
        let followed = Set(followedLines)
        var seen = Set<String>()
        var items: [(WidgetDisruption, Date)] = []
        for remark in remarks where remark.kind == .disruption {
            let lines = remark.affectedLines.filter(followed.contains)
            guard !lines.isEmpty else { continue }
            if let until = remark.validUntil, until < now { continue }
            let id = remark.id ?? "\(remark.title ?? "")|\(remark.text.prefix(60))"
            guard seen.insert(id).inserted else { continue }
            let item = WidgetDisruption(id: id, title: remark.title ?? "Störung", summary: shortened(remark.text, limit: 140),
                                        lines: lines, validFrom: remark.validFrom, validUntil: remark.validUntil)
            items.append((item, remark.modifiedAt ?? remark.validFrom ?? now))
        }
        return items.sorted { $0.1 > $1.1 }.prefix(max(0, limit)).map(\.0)
    }

    /// The widget equipment of a station from its place marks (`PlaceMarkSelection.detailMarks`), in a fixed order.
    public static func facilities(_ marks: [StopMark]) -> [WidgetFacility] {
        let kinds = Set(marks.map(\.kind))
        var out: [WidgetFacility] = []
        if kinds.contains(.bikeAndRide) { out.append(.bikeRide) }
        if kinds.contains(.parkAndRide) { out.append(.parkRide) }
        if let access = marks.first(where: { $0.kind == .barrierefrei }) {
            out.append(access.isPartial ? .barrierFreePartial : .barrierFree)
        }
        return out
    }

    /// The text cut at the last whole word before `limit` characters, with "…" when cut.
    public static func shortened(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let head = collapsed.prefix(limit)
        if let space = head.lastIndex(of: " ") {
            return String(head[..<space]) + "…"
        }
        return String(head) + "…"
    }
}
