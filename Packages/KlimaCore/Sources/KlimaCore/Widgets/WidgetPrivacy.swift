import Foundation

// Lock-screen privacy of the widgets (docs/WIDGETS_SMARTSTACK.md §1). Two switches in the widget gallery: "Strecken auf
// dem Sperrbildschirm verbergen" (on unless the user turns it off) and "Beträge verbergen" (off unless turned on). The
// widget views mark station names, destinations and trip titles (routes) or euro amounts (amounts) as privacy sensitive;
// the system draws a placeholder in their place while the device is locked.

extension WidgetCacheKey {
    /// `WidgetPrivacy`: the user's choice, written by the app (the gallery switches). Widgets only read it.
    public static let privacy = "widgets.privacy.v1"
}

/// The two privacy switches. Both fields are optional: a value nobody has set (an older snapshot, a fresh install) reads
/// as the default. The coding keys are the ones `WidgetSnapshot` uses for the same flags, so this type also decodes the
/// flags straight out of a stored snapshot.
public struct WidgetPrivacy: Codable, Hashable, Sendable {
    /// Routes are hidden on the locked device unless the user turns it off.
    public static let defaultHidesRoutes = true
    /// Amounts stay visible unless the user turns it on.
    public static let defaultHidesAmounts = false

    public var hidesRoutesWhenLocked: Bool?
    public var hidesAmountsWhenLocked: Bool?

    public init(hidesRoutesWhenLocked: Bool? = nil, hidesAmountsWhenLocked: Bool? = nil) {
        self.hidesRoutesWhenLocked = hidesRoutesWhenLocked
        self.hidesAmountsWhenLocked = hidesAmountsWhenLocked
    }

    /// Nothing set: both defaults.
    public static let standard = WidgetPrivacy()

    /// Station names, destinations and trip titles are hidden while the device is locked.
    public var hidesRoutes: Bool { hidesRoutesWhenLocked ?? Self.defaultHidesRoutes }
    /// Euro amounts are hidden while the device is locked.
    public var hidesAmounts: Bool { hidesAmountsWhenLocked ?? Self.defaultHidesAmounts }

    /// Whether content of `kind` is hidden while locked.
    public func hides(_ kind: WidgetPrivateKind) -> Bool {
        switch kind {
        case .route: hidesRoutes
        case .amount: hidesAmounts
        }
    }

    /// Both switches resolved to plain values (what the gallery shows and the app stores once the user touches one).
    public var resolved: WidgetPrivacy {
        WidgetPrivacy(hidesRoutesWhenLocked: hidesRoutes, hidesAmountsWhenLocked: hidesAmounts)
    }

    /// The choice a widget follows: the app's stored key (written the moment a switch changes, also without a ticket),
    /// else the copy in the ticket snapshot, else the defaults. Field by field, so a half-set value never loses a flag.
    public static func resolve(stored: WidgetPrivacy?, snapshot: WidgetPrivacy?) -> WidgetPrivacy {
        WidgetPrivacy(hidesRoutesWhenLocked: stored?.hidesRoutesWhenLocked ?? snapshot?.hidesRoutesWhenLocked,
                      hidesAmountsWhenLocked: stored?.hidesAmountsWhenLocked ?? snapshot?.hidesAmountsWhenLocked)
    }

    /// Decodes the flags of a stored `WidgetSnapshot` (JSON); a snapshot written before the flags existed reads as
    /// `standard`. Nil only for data that is not a JSON object.
    public static func fromSnapshotJSON(_ data: Data) -> WidgetPrivacy? {
        try? JSONDecoder().decode(WidgetPrivacy.self, from: data)
    }
}

/// What a privacy-sensitive text in a widget is.
public enum WidgetPrivateKind: String, Sendable, CaseIterable {
    /// Station names, destinations, trip and favourite titles.
    case route
    /// Euro amounts (value, remaining, profit, a favourite's fare).
    case amount
}
