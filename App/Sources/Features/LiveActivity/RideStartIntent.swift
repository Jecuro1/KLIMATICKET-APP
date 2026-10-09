import ActivityKit
import AppIntents
import Foundation
import KlimaCore

/// "Fahrt starten" for Shortcuts, Siri and the Action button: starts a favourite route as the "Unterwegs" Live Activity.
/// A `LiveActivityIntent` runs in the app's process, so it may start the activity from the background; if the system
/// still wants the app in front, it continues there.
struct RideStartIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fahrt starten"
    static let description = IntentDescription(
        "Startet eine Lieblingsfahrt als Live-Aktivität am Sperrbildschirm und in der Dynamic Island. Beim Ankommen speicherst du sie mit einem Tipp.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Fahrt")
    var favorite: FavoriteRouteAppEntity

    init() {}

    init(favoriteID: UUID, title: String) {
        self.favorite = FavoriteRouteAppEntity(id: favoriteID, title: title)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .result(dialog: "Live-Aktivitäten sind für KlimaBilanz ausgeschaltet. Du kannst sie in den Einstellungen bei „KlimaBilanz“ einschalten.")
        }
        guard let ride = RidePlanner.ride(favoriteID: favorite.id) else {
            return .result(dialog: "Diese Lieblingsfahrt gibt es nicht mehr. Wähle in KlimaBilanz eine andere aus.")
        }
        let controller = RideActivityController.shared
        do {
            try await controller.start(ride: ride)
        } catch RideActivityError.notInForeground where systemContext.currentMode.canContinueInForeground {
            try await continueInForeground(alwaysConfirm: false)
            do {
                try await controller.start(ride: ride)
            } catch {
                return .result(dialog: "\(Self.message(for: error))")
            }
        } catch {
            return .result(dialog: "\(Self.message(for: error))")
        }
        let route = RideNames.route(from: ride.trip.fromName, to: ride.trip.toName, roundTrip: ride.trip.isRoundTrip)
        return .result(dialog: "Gute Fahrt! \(route) läuft jetzt als Live-Aktivität. Tippe beim Ankommen auf „Fahrt speichern“.")
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? RideActivityError.failed.errorDescription ?? ""
    }
}
