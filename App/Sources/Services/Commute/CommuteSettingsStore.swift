import Foundation
import Observation
import KlimaCore

// Pendel-Modus (docs/COMMUTE.md §8): the settings as versioned JSON in the app's own UserDefaults – no SwiftData, nothing
// synced, nothing in the App Group (no widget reads them). CI screenshot and perf runs keep them in memory only.

/// Everything the commute remembers.
struct CommuteSettings: Codable, Equatable {
    static let currentVersion = 1
    /// How long a „Nein“ on the Übersicht invitation keeps that pair quiet.
    static let declineDays = 30

    enum RouteSource: String, Codable, CaseIterable, Identifiable {
        /// „Vorschlag aus deinen Fahrten“ (`CommuteDetector`).
        case suggestion
        /// A route of „Meine Routen“.
        case savedRoute
        /// Two stations picked by hand.
        case stations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .suggestion: "Vorschlag"
            case .savedRoute: "Meine Routen"
            case .stations: "Zwei Stationen"
            }
        }
    }

    var version = CommuteSettings.currentVersion
    var isEnabled = false
    var source: RouteSource = .suggestion
    /// The saved route the commute came from (its schedule prefilled the plan).
    var savedRouteID: UUID?
    var origin: CommuteEndpoint?
    var destination: CommuteEndpoint?
    var plan = CommutePlan()
    /// The mode a logged commute gets (a saved route's own mode, else train).
    var mode: TransportMode = .train
    /// „Als Hin- und Rückfahrt erfassen“ – remembered for the card and for Siri.
    var logsRoundTrip = false
    /// pairKey → the moment of the „Nein“.
    var declinedPairs: [String: Date] = [:]

    init() {}

    /// Both ends known by an app station: the card can search.
    var hasRoute: Bool {
        guard let origin, let destination, origin.stationID?.isEmpty == false, destination.stationID?.isEmpty == false else { return false }
        return origin.key != destination.key
    }

    /// The mode is on and has a route.
    var isActive: Bool { isEnabled && hasRoute }

    func isDeclined(_ pairKey: String, now: Date) -> Bool {
        guard let at = declinedPairs[pairKey] else { return false }
        return now.timeIntervalSince(at) < Double(Self.declineDays) * 86_400
    }

    // Every field optional on decoding: a newer or older stored form never resets the user's choice.
    private enum CodingKeys: String, CodingKey {
        case version, isEnabled, source, savedRouteID, origin, destination, plan, mode, logsRoundTrip, declinedPairs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        source = (try? c.decodeIfPresent(RouteSource.self, forKey: .source)) ?? .suggestion
        savedRouteID = try? c.decodeIfPresent(UUID.self, forKey: .savedRouteID)
        origin = try? c.decodeIfPresent(CommuteEndpoint.self, forKey: .origin)
        destination = try? c.decodeIfPresent(CommuteEndpoint.self, forKey: .destination)
        plan = (try? c.decodeIfPresent(CommutePlan.self, forKey: .plan)) ?? CommutePlan()
        mode = (try? c.decodeIfPresent(TransportMode.self, forKey: .mode)) ?? .train
        logsRoundTrip = (try? c.decodeIfPresent(Bool.self, forKey: .logsRoundTrip)) ?? false
        declinedPairs = (try? c.decodeIfPresent([String: Date].self, forKey: .declinedPairs)) ?? [:]
    }
}

/// The one owner of `CommuteSettings`.
@MainActor
@Observable
final class CommuteSettingsStore {
    static let shared = CommuteSettingsStore()
    static let key = "commute.settings.v1"

    private(set) var settings: CommuteSettings
    /// nil: memory only (CI screenshots, perf runs).
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = LaunchMode.isSandboxed ? nil : .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key), let stored = try? JSONDecoder().decode(CommuteSettings.self, from: data) {
            settings = stored
        } else {
            settings = CommuteSettings()
        }
    }

    func update(_ change: (inout CommuteSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        save()
    }

    /// Replaces everything (demo scenes).
    func replace(with settings: CommuteSettings) {
        self.settings = settings
        save()
    }

    /// „Nein“ on the invitation: this pair stays quiet for 30 days. Old entries are dropped on the way.
    func decline(pairKey: String, now: Date = Date()) {
        update { s in
            s.declinedPairs = s.declinedPairs.filter { now.timeIntervalSince($0.value) < Double(CommuteSettings.declineDays) * 86_400 }
            s.declinedPairs[pairKey] = now
        }
    }

    func undoDecline(pairKey: String) {
        update { $0.declinedPairs[pairKey] = nil }
    }

    /// „Alle Daten löschen“ and a fresh start.
    func reset() {
        settings = CommuteSettings()
        defaults?.removeObject(forKey: Self.key)
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
