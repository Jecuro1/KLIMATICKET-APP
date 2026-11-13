import SwiftUI
import WidgetKit
import KlimaCore

// MARK: smartwidgets – lock-screen privacy of the widget views (docs/WIDGETS_SMARTSTACK.md §1). Shared by the widget
// extension and the app's gallery. The extension puts the user's choice into the environment (`widPrivacy`); every
// route or amount text marks itself with `widPrivate(_:)`. While the device is locked the system renders the widget with
// the `.privacy` redaction reason and draws a placeholder of the same size in place of the marked texts, so nothing moves.
// The gallery shows the same thing with `.redacted(reason: .privacy)`.

extension EnvironmentValues {
    /// The privacy switches the widget follows (the gallery passes its own while the user flips them).
    @Entry var widPrivacy: WidgetPrivacy = .standard
}

extension WidgetPrivacy {
    /// True while content of `kind` is hidden right now: the switch is on and the view is being drawn redacted.
    func conceals(_ kind: WidgetPrivateKind, in reasons: RedactionReasons) -> Bool {
        hides(kind) && reasons.contains(.privacy)
    }

    /// VoiceOver word for a hidden text.
    static let hiddenSpeech = "Inhalt verborgen"
}

extension View {
    /// Marks a route (station, destination, trip or favourite title) or an amount as private when the matching switch
    /// is on. VoiceOver reads "Inhalt verborgen" for it while it is hidden.
    func widPrivate(_ kind: WidgetPrivateKind) -> some View {
        modifier(WidPrivateModifier(kind: kind, isActive: true))
    }

    /// `widPrivate(_:)` only when `condition` holds (a forecast block shows a date or, once paid off, an amount).
    func widPrivate(_ kind: WidgetPrivateKind, if condition: Bool) -> some View {
        modifier(WidPrivateModifier(kind: kind, isActive: condition))
    }
}

private struct WidPrivateModifier: ViewModifier {
    let kind: WidgetPrivateKind
    let isActive: Bool

    @Environment(\.widPrivacy) private var privacy
    @Environment(\.redactionReasons) private var reasons

    func body(content: Content) -> some View {
        if !isActive {
            content
        } else if privacy.conceals(kind, in: reasons) {
            content
                .privacySensitive(true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: WidgetPrivacy.hiddenSpeech))
        } else {
            content.privacySensitive(privacy.hides(kind))
        }
    }
}

extension EnvironmentValues {
    /// True while route texts are drawn as placeholders (the locked device, or the gallery's locked preview). Views that
    /// speak one sentence for several texts leave the hidden parts out of it.
    var widConcealsRoutes: Bool { widPrivacy.conceals(.route, in: redactionReasons) }
    /// True while euro amounts are drawn as placeholders.
    var widConcealsAmounts: Bool { widPrivacy.conceals(.amount, in: redactionReasons) }
}

extension WidgetPrivacy {
    /// The choice the widget extension follows: the app's stored key, else the ticket snapshot's copy, else the
    /// defaults (`WidgetPrivacy.resolve`).
    static func current(snapshot: WidgetSnapshot? = WidgetSnapshot.load()) -> WidgetPrivacy {
        resolve(stored: WidgetCache.privacy, snapshot: snapshot?.privacy)
    }
}
