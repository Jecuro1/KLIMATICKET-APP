import WidgetKit
import SwiftUI
import AppIntents

/// Control Center / lock screen / Action button control: opens KlimaBilanz on "Fahrt erfassen".
struct KlimaControlWidget: ControlWidget {
    static let kind = WidControlKind.addTrip

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAddTripIntent()) {
                Label("Fahrt erfassen", systemImage: "plus.circle.fill")
            }
            .tint(Theme.accent)
        }
        .displayName("Fahrt erfassen")
        .description("Öffnet KlimaBilanz direkt beim Erfassen einer neuen Fahrt.")
    }
}

/// "Lieblingsfahrt erfassen": logs the favourite chosen when the control is added – one press in Control Center, on the
/// Lock Screen or on the Action button, no app. The label names the favourite and its value; while the log runs it
/// reads "Erfasst" with a checkmark.
struct KlimaFavoriteControl: ControlWidget {
    static let kind = WidControlKind.logFavorite

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: FavoriteControlProvider()) { value in
            ControlWidgetButton(value.title, action: LogFavoriteControlIntent(favorite: value.entity)) { isActive in
                Label(isActive ? "Erfasst" : value.detail,
                      systemImage: isActive ? "checkmark.circle.fill" : value.symbol)
                    .controlWidgetActionHint(value.entity == nil ? "Lieblingsfahrt wählen" : "\(value.title) erfassen")
            }
            .tint(Theme.gold)
        }
        .displayName("Lieblingsfahrt erfassen")
        .description("Erfasst deine gewählte Lieblingsfahrt mit einem Tipp – ohne die App zu öffnen.")
        .promptsForUserConfiguration()
    }
}

/// What the favourite control shows: the configured favourite, resolved against the current widget snapshot (its title,
/// mode or price may have changed since the control was set up).
struct FavoriteControlValue {
    var entity: FavoriteRouteAppEntity?
    var title: String
    /// "€ 22,80" · "Auswählen"
    var detail: String
    var symbol: String

    static let unconfigured = FavoriteControlValue(entity: nil, title: "Lieblingsfahrt", detail: "Auswählen", symbol: "star.fill")
}

struct FavoriteControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: LogFavoriteControlIntent) -> FavoriteControlValue {
        Self.value(for: configuration.favorite, snapshot: WidgetSnapshot.load())
            ?? FavoriteControlValue(entity: nil, title: "Pendeln", detail: WidFormat.euroPrecise(22.8), symbol: "train.side.front.car")
    }

    func currentValue(configuration: LogFavoriteControlIntent) async throws -> FavoriteControlValue {
        Self.value(for: configuration.favorite, snapshot: WidgetSnapshot.load()) ?? .unconfigured
    }

    private static func value(for entity: FavoriteRouteAppEntity?, snapshot: WidgetSnapshot?) -> FavoriteControlValue? {
        guard let entity else { return nil }
        guard let favorite = snapshot?.favorites.first(where: { $0.id == entity.id }) else {
            // Deleted since (or no snapshot yet): keep the name, ask for a new choice.
            return FavoriteControlValue(entity: entity, title: entity.title, detail: "Neu wählen", symbol: "star.slash")
        }
        return FavoriteControlValue(entity: FavoriteRouteAppEntity(favorite), title: favorite.title,
                                    detail: WidFormat.euroPrecise(favorite.value), symbol: favorite.modeSymbol)
    }
}
