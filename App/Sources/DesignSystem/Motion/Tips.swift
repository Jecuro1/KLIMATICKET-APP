import SwiftUI
import TipKit

/// TipKit catalogue (docs/MOTION.md §11): one tip per hidden gesture, German copy in du-Form, each shown at most a few
/// times and never again once the gesture was used (`KBTips.used(_:)`). Tips are configured once at launch
/// (`KBTips.configure()`, RootView) – never in screenshot or performance runs, so CI screens stay deterministic.
///
///     TipView(KBTips.TripSwipe()).kbTipStyle()           // inline, above the list it explains
///     favoriteChip.popoverTip(KBTips.QuickLog())         // anchored to the control
///     KBTips.used(KBTips.TripSwipe())                    // the user performed the gesture
enum KBTips {
    @MainActor private static var isConfigured = false

    /// Once per launch (RootView). One tip at a time, at most one new tip per hour.
    @MainActor
    static func configure() {
        guard !isConfigured, !LaunchMode.isSandboxed else { return }
        isConfigured = true
        do {
            try Tips.configure([.displayFrequency(.hourly), .datastoreLocation(.applicationDefault)])
        } catch {
            // Already configured (e.g. by a test host) – TipKit keeps the first configuration.
        }
    }

    /// Design-system gallery (DEBUG screenshot route only): every tip visible, independent of the tip history.
    @MainActor
    static func configureForGallery() {
        guard !isConfigured else { return }
        isConfigured = true
        Tips.showAllTipsForTesting()
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
    }

    /// The user performed what the tip explains: it never shows again.
    static func used(_ tip: some Tip) {
        tip.invalidate(reason: .actionPerformed)
    }

    // MARK: Catalogue

    /// Übersicht › Schnell erfassen: a favourite chip logs with one tap; long press for more.
    struct QuickLog: Tip {
        var title: Text { Text("Ein Tipp – erfasst") }
        var message: Text? { Text("Tipp auf einen Favoriten und die Fahrt ist gespeichert. Lang drücken zeigt weitere Optionen.") }
        var image: Image? { Image(systemName: "hand.tap.fill") }
        var options: [any TipOption] { Tips.MaxDisplayCount(3) }
    }

    /// Fahrten: swipe a row to delete, log again or star it.
    struct TripSwipe: Tip {
        var title: Text { Text("Wischen für mehr") }
        var message: Text? { Text("Wisch eine Fahrt nach links zum Löschen oder nach rechts, um sie nochmal zu erfassen oder als Favorit zu merken.") }
        var image: Image? { Image(systemName: "hand.draw.fill") }
        var options: [any TipOption] { Tips.MaxDisplayCount(3) }
    }

    /// Fahrt erfassen: the arrow swaps Von and Nach.
    struct SwapStations: Tip {
        var title: Text { Text("Heimfahrt in einem Tipp") }
        var message: Text? { Text("Der Pfeil tauscht Von und Nach – praktisch für den Rückweg.") }
        var image: Image? { Image(systemName: "arrow.up.arrow.down") }
        var options: [any TipOption] { Tips.MaxDisplayCount(2) }
    }

    /// Statistik / Übersicht: touch and drag across the chart.
    struct ChartScrub: Tip {
        var title: Text { Text("Fahr mit dem Finger drüber") }
        var message: Text? { Text("Halte und zieh über die Grafik, um jeden Tag deines Ticketjahres zu sehen.") }
        var image: Image? { Image(systemName: "hand.point.up.left.fill") }
        var options: [any TipOption] { Tips.MaxDisplayCount(2) }
    }

    /// Ticket: tap the card to see its back with the photo of the real ticket.
    struct TicketFlip: Tip {
        var title: Text { Text("Dreh dein Ticket um") }
        var message: Text? { Text("Tipp auf die Karte – auf der Rückseite hast du das Foto deines echten Tickets.") }
        var image: Image? { Image(systemName: "rotate.3d") }
        var options: [any TipOption] { Tips.MaxDisplayCount(2) }
    }

    /// Long press on a trip or favourite: preview and actions.
    struct LongPress: Tip {
        var title: Text { Text("Lang drücken") }
        var message: Text? { Text("Halte eine Fahrt gedrückt für Vorschau, Bearbeiten, Nochmal fahren und Teilen.") }
        var image: Image? { Image(systemName: "hand.point.up.fill") }
        var options: [any TipOption] { Tips.MaxDisplayCount(2) }
    }
}

extension View {
    /// Inline tips in the Alpine Glass look: frosted, card radius, glacier symbol.
    func kbTipStyle() -> some View {
        self
            .tipBackground(.regularMaterial)
            .tipCornerRadius(Theme.Radius.tile)
            .tint(Theme.accent)
    }
}
