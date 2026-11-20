import Foundation

// MARK: uebersicht – „Übersicht nach Maß“ (docs/DASHBOARD_LAYOUT.md): which cards the Übersicht shows and in which order. One JSON value
// under `dash.layout.v1` (UserDefaults, not synced; the daily backup carries it through its `dash.` prefix). Header, ticket pill, hero,
// the running-ride capsule and the update capsule are fixed above the list and never part of it. Decoding never fails: garbage, an unknown
// version or an unknown id give the default, and an id that is new in this app version joins after its neighbour of the default order.

/// The movable sections of the Übersicht. The raw strings are stored – never rename one.
public enum DashSectionID: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    /// The Bilanz card with „Warum lohnt sich mein Ticket?“ (or the invitation while there is no trip).
    case balance
    /// Jahresrückblick, 1 Dec – 31 Jan.
    case yearReview
    /// Pendel-Modus.
    case commute
    /// „Schnell erfassen“ – the favourites.
    case quickLog
    /// Fahrten-Vorschläge (Fahrten erkennen) and a running recording.
    case suggestions
    /// „Termine mit Zugfahrt?“
    case calendarSuggestions
    /// Letzte Fahrten.
    case recentTrips
    /// Own goals with their rings.
    case goals
    /// Own figures, up to four tiles.
    case kpis
    /// Nächster Erfolg (Gipfelbuch).
    case achievements
    /// Diese Woche.
    case week
    /// Vorteile.
    case perks

    public var id: String { rawValue }

    /// The order of a fresh install – the Übersicht as it was before the layout existed (goals and figures stay empty until picked).
    public static let defaultOrder: [DashSectionID] = [
        .balance, .yearReview, .commute, .quickLog, .suggestions, .calendarSuggestions, .recentTrips, .goals, .kpis,
        .achievements, .week, .perks,
    ]

    /// Sections that cannot be hidden: the Bilanz answers the question the app is for.
    public static let core: Set<DashSectionID> = [.balance]

    public var isCore: Bool { Self.core.contains(self) }

    /// German name in the editor.
    public var title: String {
        switch self {
        case .balance: "Bilanz"
        case .yearReview: "Jahresrückblick"
        case .commute: "Pendel-Modus"
        case .quickLog: "Schnell erfassen"
        case .suggestions: "Fahrten-Vorschläge"
        case .calendarSuggestions: "Termine mit Zugfahrt"
        case .recentTrips: "Letzte Fahrten"
        case .goals: "Ziele"
        case .kpis: "Kennzahlen"
        case .achievements: "Nächster Erfolg"
        case .week: "Diese Woche"
        case .perks: "Vorteile"
        }
    }

    /// When the card has something to show at all – the editor says it, so a visible but empty card is no surprise.
    public var whenShown: String {
        switch self {
        case .balance: "Immer da · lässt sich verschieben, nicht ausblenden"
        case .yearReview: "1. Dezember bis 31. Jänner"
        case .commute: "Wenn der Pendel-Modus an ist oder einen Weg vorschlägt"
        case .quickLog: "Sobald du Favoriten oder Fahrten hast"
        case .suggestions: "Wenn erkannte Fahrten auf dich warten"
        case .calendarSuggestions: "Wenn Kalender-Vorschläge an sind und ein Termin passt"
        case .recentTrips: "Deine fünf neuesten Fahrten"
        case .goals: "Sobald du ein Ziel anlegst"
        case .kpis: "Sobald du Kennzahlen wählst"
        case .achievements: "Der Erfolg, der dir am nächsten ist"
        case .week: "Fahrten und Wert gegen die Vorwoche"
        case .perks: "Deine Vorteile mit dem Ticket"
        }
    }

    /// SF Symbol of the row in the editor.
    public var symbol: String {
        switch self {
        case .balance: "chart.line.uptrend.xyaxis"
        case .yearReview: "sparkles"
        case .commute: "arrow.left.arrow.right"
        case .quickLog: "star.fill"
        case .suggestions: "location.fill.viewfinder"
        case .calendarSuggestions: "calendar"
        case .recentTrips: "clock.arrow.circlepath"
        case .goals: "target"
        case .kpis: "square.grid.2x2.fill"
        case .achievements: "mountain.2.fill"
        case .week: "chart.bar.fill"
        case .perks: "gift.fill"
        }
    }
}

/// Order and visibility of the Übersicht's sections.
public struct DashLayout: Equatable, Sendable {
    /// UserDefaults key.
    public static let storageKey = "dash.layout.v1"
    public static let currentVersion = 1

    /// Every section exactly once.
    public private(set) var order: [DashSectionID]
    /// Hidden sections (never a core one).
    public private(set) var hidden: Set<DashSectionID>

    /// `order` is completed (missing ids after their neighbour of the default order) and cleaned (duplicates dropped);
    /// core sections are never hidden.
    public init(order: [DashSectionID] = DashSectionID.defaultOrder, hidden: Set<DashSectionID> = []) {
        self.order = Self.completed(order)
        self.hidden = hidden.subtracting(DashSectionID.core)
    }

    public static let standard = DashLayout()

    public func isHidden(_ id: DashSectionID) -> Bool { hidden.contains(id) }

    /// The sections the list shows, in order (a shown section may still render nothing when it has no content).
    public var visibleOrder: [DashSectionID] { order.filter { !hidden.contains($0) } }

    public var isStandard: Bool { self == .standard }

    // MARK: Editing

    /// Hides or shows `id`. Idempotent; a core section stays shown.
    public mutating func setHidden(_ id: DashSectionID, _ isHidden: Bool) {
        guard !id.isCore else { return }
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
    }

    /// Same result as SwiftUI's `Array.move(fromOffsets:toOffset:)` (List's `onMove`): the moved elements keep their relative
    /// order and land before the element that was at `destination` (`order.count` = the end). Invalid offsets are ignored.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order = Self.moved(order, fromOffsets: source, toOffset: destination)
    }

    /// One place up (VoiceOver „Nach oben“). False at the top.
    @discardableResult
    public mutating func moveUp(_ id: DashSectionID) -> Bool {
        guard let index = order.firstIndex(of: id), index > 0 else { return false }
        order.swapAt(index, index - 1)
        return true
    }

    /// One place down (VoiceOver „Nach unten“). False at the bottom.
    @discardableResult
    public mutating func moveDown(_ id: DashSectionID) -> Bool {
        guard let index = order.firstIndex(of: id), index < order.count - 1 else { return false }
        order.swapAt(index, index + 1)
        return true
    }

    /// Moves `id` directly after `anchor` (the presets put Ziele and Kennzahlen under the Bilanz).
    public mutating func place(_ id: DashSectionID, after anchor: DashSectionID) {
        guard id != anchor, order.contains(anchor) else { return }
        order.removeAll { $0 == id }
        let index = (order.firstIndex(of: anchor) ?? -1) + 1
        order.insert(id, at: index)
    }

    /// The Array semantics of `move(fromOffsets:toOffset:)`, pure.
    public static func moved<T>(_ array: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        let valid = source.filter { array.indices.contains($0) }
        guard !valid.isEmpty, destination >= 0, destination <= array.count else { return array }
        let picked = valid.map { array[$0] }
        var rest: [T] = []
        var insertAt = destination
        for (index, element) in array.enumerated() {
            if valid.contains(index) {
                if index < destination { insertAt -= 1 }
            } else {
                rest.append(element)
            }
        }
        rest.insert(contentsOf: picked, at: max(0, min(insertAt, rest.count)))
        return rest
    }

    /// Completes a stored order: unknown and duplicate ids were already dropped by the caller; every id of `defaultOrder` that is
    /// missing joins directly after its nearest predecessor of the default order (the start when it has none), so a card that is
    /// new in this app version appears where it would in a fresh install without wiping the person's order.
    static func completed(_ stored: [DashSectionID]) -> [DashSectionID] {
        var result: [DashSectionID] = []
        for id in stored where !result.contains(id) { result.append(id) }
        for (index, id) in DashSectionID.defaultOrder.enumerated() where !result.contains(id) {
            let predecessors = DashSectionID.defaultOrder[..<index].reversed()
            if let anchor = predecessors.first(where: { result.contains($0) }), let at = result.firstIndex(of: anchor) {
                result.insert(id, at: at + 1)
            } else {
                result.insert(id, at: 0)
            }
        }
        return result
    }

    // MARK: Storage

    /// The stored layout, or the default for nothing, garbage, a non-object or an unreadable version. Unknown ids are dropped.
    public static func decode(_ data: Data?) -> DashLayout {
        guard let data, !data.isEmpty, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .standard }
        guard let version = stored.version, version >= 1, version <= currentVersion else { return .standard }
        let order = stored.order.compactMap(DashSectionID.init(rawValue:))
        let hidden = Set(stored.hidden.compactMap(DashSectionID.init(rawValue:)))
        // An order that names no known section at all is as good as none.
        guard !order.isEmpty || !hidden.isEmpty else { return .standard }
        return DashLayout(order: order, hidden: hidden)
    }

    public func encoded() -> Data {
        let stored = Stored(version: Self.currentVersion, order: order.map(\.rawValue),
                            hidden: hidden.map(\.rawValue).sorted())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(stored)) ?? Data()
    }

    /// The JSON shape. Each key is read on its own: a bad value drops that value, not the layout.
    private struct Stored: Codable {
        var version: Int?
        var order: [String]
        var hidden: [String]

        init(version: Int?, order: [String], hidden: [String]) {
            self.version = version
            self.order = order
            self.hidden = hidden
        }

        private enum CodingKeys: String, CodingKey { case version, order, hidden }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try? c.decodeIfPresent(Int.self, forKey: .version)
            order = DashTolerant.strings(c, .order)
            hidden = DashTolerant.strings(c, .hidden)
        }
    }
}

/// Tolerant JSON reading shared by the Übersicht's stores.
enum DashTolerant {
    /// The strings of an array under `key`, skipping anything that is not one; [] when the key is missing or not an array.
    static func strings<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String] {
        guard var array = try? c.nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [String] = []
        while !array.isAtEnd {
            if let value = try? array.decode(String.self) {
                result.append(value)
            } else if (try? array.decode(DashSkip.self)) == nil {
                break
            }
        }
        return result
    }
}

// MARK: - Presets

/// Ready-made layouts, one tap in the editor. A preset sets order and visibility; Kennzahlen and Ziele keep what was picked.
public enum DashPreset: String, CaseIterable, Sendable, Identifiable {
    case standard, quiet, numbers, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .quiet: "Ruhig"
        case .numbers: "Zahlen"
        case .all: "Alles"
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: "Wie ausgeliefert"
        case .quiet: "Bilanz, Erfassen, letzte Fahrten"
        case .numbers: "Kennzahlen und Ziele oben"
        case .all: "Jede Karte, vier Kennzahlen"
        }
    }

    public var symbol: String {
        switch self {
        case .standard: "rectangle.stack"
        case .quiet: "leaf"
        case .numbers: "number"
        case .all: "square.grid.3x3.fill"
        }
    }

    /// Sections „Ruhig“ hides: what informs or invites, not what needs you (Vorschläge, Pendel-Modus and Termine stay; they show
    /// only when something waits).
    public static let quietHidden: Set<DashSectionID> = [.yearReview, .kpis, .achievements, .week, .perks]

    public var layout: DashLayout {
        switch self {
        case .standard, .all:
            return .standard
        case .quiet:
            return DashLayout(hidden: Self.quietHidden)
        case .numbers:
            var layout = DashLayout(hidden: [.perks])
            layout.place(.kpis, after: .balance)
            layout.place(.goals, after: .kpis)
            layout.place(.week, after: .goals)
            return layout
        }
    }

    /// „Zahlen“ and „Alles“ are about figures: with no tile picked they pick the four default tiles.
    public var fillsEmptyKpis: Bool { self == .numbers || self == .all }

    /// The preset that gives exactly `layout`, if any („Alles“ and „Standard“ share a layout – the standard one is named).
    public static func matching(_ layout: DashLayout) -> DashPreset? {
        [DashPreset.standard, .quiet, .numbers].first { $0.layout == layout }
    }
}
