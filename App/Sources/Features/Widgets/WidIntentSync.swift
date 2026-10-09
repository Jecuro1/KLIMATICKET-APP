import AppIntents
import CoreSpotlight
import Foundation
import WidgetKit
import os

/// Keeps what the system knows about the favourites in step with the widget snapshot (`Repository.refreshWidgets()`):
/// • the Siri phrases with a favourite ("Pendeln in KlimaBilanz erfassen") – `updateAppShortcutParameters()`,
/// • the favourites in Spotlight (`FavoriteRouteAppEntity` is an `IndexedEntity`),
/// • the "Lieblingsfahrt erfassen" control's label.
/// Runs only when the favourites really changed (persisted signature), so launches and ordinary saves cost nothing.
@MainActor
enum WidIntentSync {
    private static let signatureKey = "widgets.intentSync.favorites.v1"
    nonisolated private static let log = Logger(subsystem: "com.knitelarlberg.klimabilanz", category: "WidIntentSync")

    static func favoritesDidChange(to favorites: [WidgetSnapshot.Favorite]) {
        let signature = favorites.map { "\($0.id.uuidString)|\($0.title)|\($0.modeSymbol)|\($0.value)|\($0.fromName)|\($0.toName)" }
            .joined(separator: "\n")
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: signatureKey) != signature else { return }
        defaults.set(signature, forKey: signatureKey)

        KlimaBilanzShortcuts.updateAppShortcutParameters()
        ControlCenter.shared.reloadControls(ofKind: WidControlKind.logFavorite)
        let entities = favorites.map(FavoriteRouteAppEntity.init)
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            do {
                try await index.deleteAppEntities(ofType: FavoriteRouteAppEntity.self)
                if !entities.isEmpty { try await index.indexAppEntities(entities) }
            } catch {
                log.error("Spotlight indexing failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
