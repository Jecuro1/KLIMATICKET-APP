import Foundation

// MARK: radarmodes – which transport modes the radar shows (docs/RADAR_MODES.md §2). Persisted per device as a comma list under
// `radar.modes.v1` ("rail,suburban,bus"), like `map.layers`; unknown words are dropped, an empty list is the default. At least one mode stays on.

public struct RadarModeSelection: Hashable, Sendable {
    public private(set) var modes: Set<RadarMode>

    /// The modes; an empty set is the default (at least one stays on).
    public init(_ modes: Set<RadarMode>) {
        self.modes = modes.isEmpty ? RadarModeSelection.defaultModes : modes
    }

    /// {Züge, S-Bahn}: the request mask 4157 the radar always asked for by default.
    public static let defaultModes: Set<RadarMode> = [.rail, .suburban]
    public static let `default` = RadarModeSelection(defaultModes)
    /// UserDefaults key (per device, reset in screenshot launches).
    public static let storageKey = "radar.modes.v1"

    /// From the stored comma list: unknown words are dropped, nothing left is the default.
    public init(storage: String) {
        let words = storage.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        self.init(Set(words.compactMap(RadarMode.init(rawValue:))))
    }

    /// The comma list in chip order ("rail,suburban,bus").
    public var storageValue: String {
        RadarMode.allCases.filter(modes.contains).map(\.rawValue).joined(separator: ",")
    }

    public func contains(_ mode: RadarMode) -> Bool { modes.contains(mode) }

    /// Switches a mode on or off. The last mode stays on: false when nothing changed.
    @discardableResult
    public mutating func toggle(_ mode: RadarMode) -> Bool {
        if modes.contains(mode) {
            guard modes.count > 1 else { return false }
            modes.remove(mode)
        } else {
            modes.insert(mode)
        }
        return true
    }

    /// Sets a mode; switching off the last mode is refused (false).
    @discardableResult
    public mutating func set(_ mode: RadarMode, on: Bool) -> Bool {
        guard on != modes.contains(mode) else { return false }
        return toggle(mode)
    }

    /// Every product class the chips ask for.
    public var products: ProductMask {
        modes.reduce(into: ProductMask(rawValue: 0)) { $0.formUnion($1.products) }
    }

    /// Only Züge and S-Bahn are on: the Zeitreise (its snapshots are of trains) is offered, and the status says „Züge“.
    public var carriesOnlyTrains: Bool { modes.allSatisfy { !$0.isCity } }

    /// A mode of the city lane (Bus, Bim, U-Bahn) is on.
    public var hasCity: Bool { modes.contains { $0.isCity } }

    /// The chosen modes of one kind, in chip order.
    public var cityModes: [RadarMode] { RadarMode.allCases.filter { modes.contains($0) && $0.isCity } }
    public var wideModes: [RadarMode] { RadarMode.allCases.filter { modes.contains($0) && !$0.isCity } }

    /// In chip order.
    public var ordered: [RadarMode] { RadarMode.allCases.filter(modes.contains) }
}
