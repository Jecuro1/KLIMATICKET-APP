import Foundation

/// A saved „Was wäre wenn?“ scenario: the inputs, not the numbers – opening one calculates again with today's tariffs
/// (and, in the real-data mode, today's trips). Kept on this device only (UserDefaults JSON, never synced).
public struct WhatIfScenario: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    /// true = „Meine Fahrten“ (real data), false = „Eigene Annahmen“.
    public var usesHistory: Bool
    public var input: WhatIfInput
    /// The headline when it was saved, for the list ("KlimaTicket Ö Klassik · € 312 weniger im Jahr").
    public var savedHeadline: String

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), usesHistory: Bool, input: WhatIfInput,
                savedHeadline: String = "") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.usesHistory = usesHistory
        self.input = input
        self.savedHeadline = savedHeadline
    }
}

/// The saved scenarios as one versioned JSON document (max. 5). Pure value type; the app's `WhatIfStore` only moves
/// the bytes to and from UserDefaults.
public struct WhatIfScenarioBook: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var scenarios: [WhatIfScenario]

    public init(scenarios: [WhatIfScenario] = []) {
        version = Self.currentVersion
        self.scenarios = scenarios
    }

    public var isFull: Bool { scenarios.count >= WhatIfLimits.maxScenarios }

    /// Adds a scenario (newest first); false when the book is full – nothing is dropped silently.
    @discardableResult
    public mutating func add(_ scenario: WhatIfScenario) -> Bool {
        guard !isFull else { return false }
        scenarios.insert(scenario, at: 0)
        return true
    }

    public mutating func remove(id: UUID) {
        scenarios.removeAll { $0.id == id }
    }

    public mutating func rename(id: UUID, to name: String) {
        guard let index = scenarios.firstIndex(where: { $0.id == id }) else { return }
        scenarios[index].name = name
    }

    // MARK: Coding

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// The saved book; nil/garbage/unknown newer version → an empty book (a damaged save never crashes the screen).
    public static func decode(_ data: Data?) -> WhatIfScenarioBook {
        guard let data, let book = try? JSONDecoder().decode(WhatIfScenarioBook.self, from: data),
              book.version <= currentVersion else { return WhatIfScenarioBook() }
        var clean = book
        clean.scenarios = Array(book.scenarios.prefix(WhatIfLimits.maxScenarios))
        return clean
    }
}
