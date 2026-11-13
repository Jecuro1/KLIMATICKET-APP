import Foundation

// MARK: radarmodes – „Darstellung“ of the filter sheet (docs/RADAR_MODES.md §6): how the markers look and how often Bus, Bim and U-Bahn are asked.
// Stored per device under `radar.display.v1` (versioned JSON, tolerant: unknown values take their default), reset in screenshot launches.

public struct RadarDisplay: Hashable, Sendable {
    public enum Label: String, CaseIterable, Sendable, Identifiable {
        case line, lineAndDestination, dots
        public var id: Self { self }
        public var title: String {
            switch self {
            case .line: "Linie"
            case .lineAndDestination: "Linie und Ziel"
            case .dots: "Nur Punkte"
            }
        }
    }

    public enum Size: String, CaseIterable, Sendable, Identifiable {
        case small, normal, large
        public var id: Self { self }
        public var title: String {
            switch self {
            case .small: "Klein"
            case .normal: "Normal"
            case .large: "Groß"
            }
        }
        /// Points between two group cells: groups never overlap at any size.
        public var markerPitch: Double {
            switch self {
            case .small: 44
            case .normal: 56
            case .large: 70
            }
        }
    }

    public enum CityRefresh: String, CaseIterable, Sendable, Identifiable {
        case automatic, every20, every60
        public var id: Self { self }
        public var title: String {
            switch self {
            case .automatic: "Automatisch"
            case .every20: "Alle 20 s"
            case .every60: "Alle 60 s"
            }
        }
    }

    public var label: Label = .line
    public var size: Size = .normal
    /// „Gruppen zusammenfassen“; off only up to `ungroupedLimit` vehicles in view.
    public var groups = true
    /// „Richtungspfeil“.
    public var arrows = true
    public var cityRefresh: CityRefresh = .automatic

    public init(label: Label = .line, size: Size = .normal, groups: Bool = true, arrows: Bool = true, cityRefresh: CityRefresh = .automatic) {
        self.label = label
        self.size = size
        self.groups = groups
        self.arrows = arrows
        self.cityRefresh = cityRefresh
    }

    public static let standard = RadarDisplay()
    public static let storageKey = "radar.display.v1"
    /// „Aus“ for groups holds up to this many vehicles in view; above it the radar groups again (hundreds of single markers would freeze the map).
    public static let ungroupedLimit = 250
    /// The destination is shown only this close (latitude span) and with at most this many single markers.
    public static let destinationSpan = 0.3
    public static let destinationSingles = 80

    /// Whether markers are grouped for `pinCount` vehicles in view.
    public func groups(pinCount: Int) -> Bool { groups || pinCount > Self.ungroupedLimit }

    /// Whether the markers carry their destination now.
    public func showsDestination(latitudeSpan: Double, singles: Int) -> Bool {
        label == .lineAndDestination && latitudeSpan <= Self.destinationSpan && singles <= Self.destinationSingles
    }

    /// The city lane's refresh in seconds: „Automatisch“ follows the path (metered 60 s, else 20 s).
    public func cityInterval(metered: Bool) -> TimeInterval {
        switch cityRefresh {
        case .automatic: RadarLanePlan.automaticCityInterval(metered: metered)
        case .every20: RadarLanePlan.cityIntervalWiFi
        case .every60: RadarLanePlan.cityIntervalMetered
        }
    }

    /// The city refresh is 60 s because the path is metered (the status says it).
    public func meteredCity(metered: Bool) -> Bool { cityRefresh == .automatic && metered }

    // MARK: Storage

    public var storageValue: String {
        let object: [String: Any] = ["version": 1, "label": label.rawValue, "size": size.rawValue, "groups": groups, "arrows": arrows,
                                     "cityRefresh": cityRefresh.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public init(storage: String) {
        self.init()
        guard let data = storage.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        label = (object["label"] as? String).flatMap(Label.init(rawValue:)) ?? .line
        size = (object["size"] as? String).flatMap(Size.init(rawValue:)) ?? .normal
        groups = object["groups"] as? Bool ?? true
        arrows = object["arrows"] as? Bool ?? true
        cityRefresh = (object["cityRefresh"] as? String).flatMap(CityRefresh.init(rawValue:)) ?? .automatic
    }
}
