import AppIntents
import Foundation

// Buttons of the "Unterwegs" Live Activity. `LiveActivityIntent`s always run in the app's process (the system launches
// it in the background if needed), but the widget extension renders the buttons, so the types live in Shared/.

/// "Fahrt speichern" – saves the running ride as a trip and ends the Live Activity.
struct RideSaveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fahrt speichern"
    static let description = IntentDescription("Speichert deine laufende Fahrt in KlimaBilanz und beendet die Live-Aktivität.")
    /// Only meaningful from the Live Activity itself (it needs the id of a running ride).
    static let isDiscoverable = false

    @Parameter(title: "Fahrt")
    var rideID: String

    init() {}

    init(rideID: UUID) {
        self.rideID = rideID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: rideID) {
            await RideActivityActions.save(rideID: id)
        }
        return .result()
    }
}

/// "Beenden" – ends the Live Activity without saving the ride.
struct RideDiscardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fahrt beenden"
    static let description = IntentDescription("Beendet die Live-Aktivität deiner laufenden Fahrt, ohne sie zu speichern.")
    static let isDiscoverable = false

    @Parameter(title: "Fahrt")
    var rideID: String

    init() {}

    init(rideID: UUID) {
        self.rideID = rideID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: rideID) {
            await RideActivityActions.discard(rideID: id)
        }
        return .result()
    }
}
