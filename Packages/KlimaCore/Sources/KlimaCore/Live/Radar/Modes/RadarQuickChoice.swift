import Foundation

// MARK: radarmodes – „Schnellwahl“ of the filter sheet (docs/RADAR_MODES.md §6): sets modes and filter at once; afterwards everything can be changed
// one by one, and a choice that no longer matches loses its mark.

public enum RadarQuickChoice: String, CaseIterable, Sendable, Identifiable {
    case all, longDistance, regional, city, lateOnly

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: "Alles"
        case .longDistance: "Fernverkehr"
        case .regional: "Regional & S-Bahn"
        case .city: "Öffis in der Stadt"
        case .lateOnly: "Nur Verspätete"
        }
    }

    public var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .longDistance: "train.side.front.car"
        case .regional: "lightrail"
        case .city: "bus"
        case .lateOnly: "clock.badge.exclamationmark"
        }
    }

    static let longDistanceClasses: Set<RadarTrainClass> = [.rjx, .rj, .icec, .njen, .wb]
    static let regionalClasses: Set<RadarTrainClass> = [.cjx, .rex, .r, .s]

    /// The modes and the filter the choice sets. „Nur Verspätete“ keeps the modes and the region.
    public func apply(to selection: RadarModeSelection, filter: RadarFilter) -> (RadarModeSelection, RadarFilter) {
        switch self {
        case .all:
            return (RadarModeSelection(Set(RadarMode.allCases)), RadarFilter())
        case .longDistance:
            return (RadarModeSelection([.rail]), RadarFilter(trainClasses: Self.longDistanceClasses))
        case .regional:
            return (RadarModeSelection([.rail, .suburban]), RadarFilter(trainClasses: Self.regionalClasses))
        case .city:
            return (RadarModeSelection([.suburban, .bus, .tram, .subway]), RadarFilter())
        case .lateOnly:
            return (selection, RadarFilter(state: filter.state, onlyLate: true))
        }
    }

    /// The choice the current modes and filter are exactly, if any (its chip shows as chosen).
    public static func current(selection: RadarModeSelection, filter: RadarFilter) -> RadarQuickChoice? {
        for choice in [RadarQuickChoice.all, .longDistance, .regional, .city] {
            let (modes, wanted) = choice.apply(to: selection, filter: filter)
            if modes == selection, wanted == filter { return choice }
        }
        if filter == RadarFilter(state: filter.state, onlyLate: true) { return .lateOnly }
        return nil
    }
}
